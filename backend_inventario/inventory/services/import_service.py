"""
Servicios de importación de inventario.

Este módulo concentra la lectura de archivos Excel/CSV,
la normalización de datos y la creación en lote de entidades
de inventario para mantener las vistas HTTP delgadas.
"""

import io
import importlib.util
import logging
import os
import re
import tempfile
from datetime import date, datetime
from decimal import Decimal
from functools import lru_cache
from zipfile import BadZipFile

import pandas as pd
from django.http import JsonResponse
from django.utils import timezone

from ..models import ImportBatch, Product, InventoryRecord, WarehouseDetail
from ..utils import (
    clean_number, parse_date, map_localizacion, map_categoria,
    calculate_file_checksum, parse_document
)

logger = logging.getLogger(__name__)
BASE_FILE_COLUMNS = [
    'fecha_corte', 'mes', 'almacen', 'grupo', 'codigo',
    'descripcion', 'cantidad', 'unidad_medida', 'costo_unitario', 'valor_total'
]

UPDATE_FILE_COLUMNS = [
    'item', 'desc_item', 'localizacion', 'categoria',
    'fecha', 'documento', 'entradas', 'salidas',
    'unitario', 'total', 'cantidad', 'cost_center'
]

UPDATE_REQUIRED_COLUMNS = [
    'item', 'desc_item', 'localizacion', 'categoria',
    'fecha', 'documento', 'entradas', 'salidas',
    'unitario', 'total', 'cantidad'
]

UPDATE_NUMERIC_COLUMNS = ['entradas', 'salidas', 'cantidad', 'unitario', 'total']
CSV_CHUNK_SIZE = 15000
MOVEMENT_BULK_SIZE = 2000
SIMPLE_NUMERIC_RE = re.compile(r'^-?\d+(?:\.\d+)?$')
UPDATE_COLUMN_SYNONYMS = {
    'item': ['item', 'codigo', 'code', 'producto', 'cod', 'código'],
    'desc_item': ['desc_item', 'descripcion', 'description', 'desc', 'producto_desc', 'descripción'],
    'localizacion': ['localizacion', 'local', 'almacen', 'warehouse', 'location', 'localización'],
    'categoria': ['categoria', 'category', 'grupo', 'group', 'tipo', 'categoría'],
    'fecha': ['fecha', 'date', 'fecha_mov', 'fecha_documento', 'fecha_registro'],
    'documento': ['documento', 'doc', 'document', 'numero_documento', 'número_documento'],
    'entradas': ['entradas', 'entrada', 'in', 'input', 'ingreso'],
    'salidas': ['salidas', 'salida', 'out', 'output', 'egreso'],
    'unitario': ['unitario', 'unit_cost', 'costo_unitario', 'precio_unitario', 'unit', 'costo_unit'],
    'total': ['total', 'total_cost', 'valor_total', 'monto'],
    'cantidad': ['cantidad', 'quantity', 'qty', 'cant', 'amount'],
    'cost_center': ['cost_center', 'centro_costo', 'cc', 'costcenter', 'centro_costo'],
}
UPDATE_READABLE_COLUMNS = {
    synonym.lower().strip()
    for synonyms in UPDATE_COLUMN_SYNONYMS.values()
    for synonym in synonyms
}


def _decimal_or_clean(value):
    """
    Convierte valores numéricos a Decimal de forma segura.

    Si el valor ya es Decimal, se retorna tal cual para evitar
    procesamiento innecesario.
    """
    if isinstance(value, Decimal):
        return value
    if value is None:
        return Decimal('0.0')

    if isinstance(value, (int, float)):
        if pd.isna(value):
            return Decimal('0.0')
        return Decimal(str(value))

    raw = str(value).strip()
    if not raw or raw.lower() in ('nan', 'none', 'nat'):
        return Decimal('0.0')

    normalized = raw.replace(',', '.')
    if SIMPLE_NUMERIC_RE.match(normalized):
        try:
            return Decimal(normalized)
        except Exception:
            pass

    return _clean_number_cached(raw)


@lru_cache(maxsize=50000)
def _clean_number_cached(raw):
    """
    Cache para conversiones numéricas repetidas.
    """
    return clean_number(raw)


def _normalize_signature_value(value):
    """
    Normaliza valores para crear firmas estables de deduplicación.
    """
    if value is None:
        return ''

    if isinstance(value, float) and pd.isna(value):
        return ''

    if isinstance(value, Decimal):
        if value == 0:
            return '0'
        return format(value.normalize(), 'f')

    raw = str(value).strip()
    if raw.lower() in ('nan', 'none', 'nat'):
        return ''
    return raw


def _build_row_signature(*values):
    """
    Construye una firma hashable de una fila para detectar duplicados.
    """
    return tuple(_normalize_signature_value(v) for v in values)


@lru_cache(maxsize=512)
def _map_localizacion_cached(raw_value):
    """
    Cache para mapear localizaciones repetidas.
    """
    return map_localizacion(raw_value)


@lru_cache(maxsize=512)
def _map_categoria_cached(raw_value):
    """
    Cache para mapear categorías repetidas.
    """
    return map_categoria(raw_value)


def _parse_date_fast(value):
    """
    Parseo de fecha optimizado con fast-path para formatos comunes.
    """
    if value is None:
        return None

    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, pd.Timestamp):
        return value.date()

    raw = str(value).strip()
    return _parse_date_from_raw_cached(raw)


@lru_cache(maxsize=50000)
def _parse_date_from_raw_cached(raw):
    """
    Cache para parseo de fechas repetidas provenientes de texto.
    """
    if not raw or raw.lower() in ('nan', 'none', 'nat'):
        return None

    # Fast path: YYYY-MM-DD
    if len(raw) == 10 and raw[4] == '-' and raw[7] == '-':
        try:
            return datetime.strptime(raw, '%Y-%m-%d').date()
        except ValueError:
            pass

    # Fast path: YYYYMMDD
    if len(raw) == 8 and raw.isdigit():
        try:
            return datetime.strptime(raw, '%Y%m%d').date()
        except ValueError:
            pass

    return parse_date(raw)


def _write_dataframe_to_temp_csv(df, prefix):
    """
    Persiste un DataFrame en un CSV temporal para procesarlo por chunks.
    """
    temp_file = tempfile.NamedTemporaryFile(
        mode='w',
        suffix='.csv',
        prefix=prefix,
        delete=False,
        newline='',
        encoding='utf-8'
    )
    try:
        df.to_csv(temp_file.name, index=False)
        return temp_file.name
    finally:
        temp_file.close()


def _iter_csv_chunks(csv_path, chunk_size=CSV_CHUNK_SIZE):
    """
    Itera un CSV en bloques para controlar uso de memoria.
    """
    for chunk in pd.read_csv(
        csv_path,
        dtype='object',
        chunksize=chunk_size,
        na_filter=False,
        keep_default_na=False,
    ):
        yield chunk


def _iter_dataframe_chunks(df, chunk_size=CSV_CHUNK_SIZE):
    """
    Itera un DataFrame en bloques sin pasar por disco.
    """
    total_rows = len(df.index)
    for start in range(0, total_rows, chunk_size):
        yield df.iloc[start:start + chunk_size]


def _remove_temp_file(file_path):
    """
    Elimina archivo temporal si existe.
    """
    if not file_path:
        return
    try:
        os.remove(file_path)
    except OSError:
        logger.warning(f"No se pudo eliminar archivo temporal: {file_path}")


def _looks_like_html_table(file_content):
    """
    Detecta archivos .xls que en realidad son tablas HTML exportadas.
    """
    if not file_content:
        return False
    sample = file_content[:4096].lower()
    return b'<html' in sample or b'<table' in sample


def _candidate_excel_engines(file_name, file_content):
    """
    Selecciona motores de lectura priorizando precisión y velocidad.
    """
    lower_name = (file_name or '').lower()
    looks_like_xlsx_zip = file_content[:2] == b'PK'

    if looks_like_xlsx_zip:
        # `calamine` es más rápido si está disponible; si no, hacemos fallback.
        ordered = ['calamine', 'openpyxl', 'xlrd']
    elif lower_name.endswith('.xls'):
        # Para .xls priorizamos xlrd; openpyxl queda como fallback en archivos mal renombrados.
        ordered = ['calamine', 'xlrd', 'openpyxl']
    else:
        ordered = ['calamine', 'openpyxl', 'xlrd']

    result = []
    seen = set()
    for engine in ordered:
        if engine == 'calamine' and importlib.util.find_spec('python_calamine') is None:
            continue
        if engine not in seen:
            seen.add(engine)
            result.append(engine)
    return result


def _update_usecols_filter(column_name):
    """
    Selecciona solo columnas potencialmente útiles para archivos de actualización.
    """
    normalized = str(column_name).lower().strip()
    return normalized in UPDATE_READABLE_COLUMNS


def _read_excel_bytes(file_content, engine, **kwargs):
    """
    Ejecuta `pandas.read_excel` usando bytes en memoria.
    """
    read_kwargs = dict(kwargs)
    read_kwargs['engine'] = engine
    if engine == 'openpyxl':
        # read_only/data_only reduce costo de lectura para archivos grandes.
        read_kwargs['engine_kwargs'] = {'read_only': True, 'data_only': True}
    return pd.read_excel(io.BytesIO(file_content), **read_kwargs)


def _read_base_dataframe(base_content, base_filename):
    """
    Lectura robusta del archivo base manteniendo valores en tipo object
    para preservar precisión hasta la fase de normalización.
    """
    last_error = None
    for engine in _candidate_excel_engines(base_filename, base_content):
        try:
            return _read_excel_bytes(
                base_content,
                engine=engine,
                header=0,
                usecols='A:J',
                names=BASE_FILE_COLUMNS,
                dtype='object',
            )
        except Exception as exc:
            last_error = exc
            logger.warning(f"Error leyendo base con engine '{engine}': {exc}")

    if last_error:
        raise last_error
    raise ValueError('No se pudo leer el archivo base')


def _normalize_date_value(value):
    """
    Convierte fechas heterogéneas a YYYY-MM-DD.
    """
    parsed = _parse_date_fast(value)
    if parsed is None:
        return None
    return parsed.isoformat()


def _normalize_document_value(value):
    """
    Normaliza documento a prefijo+numero (SA/EA) cuando sea posible.
    """
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None

    raw = str(value).strip()
    return _normalize_document_cached(raw)


@lru_cache(maxsize=100000)
def _normalize_document_cached(raw):
    """
    Cache para normalizar documentos repetidos.
    """
    if not raw or raw.lower() in ('nan', 'none'):
        return None

    doc_type, doc_number = parse_document(raw)
    if doc_type and doc_number:
        return f'{doc_type}{doc_number}'

    return re.sub(r'\s+', '', raw.upper())


def _strip_object_series(series):
    """
    Convierte una serie a string y remueve espacios en blanco.
    """
    return series.fillna('').astype(str).str.strip()


def _normalize_update_dataframe(df):
    """
    Limpia dataframe de actualización preservando precisión numérica.
    """
    if df is None:
        return df

    df = df.copy()

    # Asegurar columnas esperadas para no romper procesamiento posterior.
    for col in UPDATE_FILE_COLUMNS:
        if col not in df.columns:
            df[col] = None

    df.loc[:, 'item'] = df['item'].apply(lambda x: str(x).strip() if pd.notna(x) else '')
    df = df.loc[df['item'] != ''].copy()
    df = df.loc[df['item'].str.lower() != 'nan'].copy()
    df.loc[:, 'item'] = df['item'].str.lstrip('0')

    # Estandarizamos texto y dejamos parseo numérico/fecha para la fase final.
    df.loc[:, 'fecha'] = df['fecha'].apply(
        lambda x: str(x).strip() if pd.notna(x) else ''
    )
    df.loc[:, 'documento'] = df['documento'].apply(_normalize_document_value)

    for col in UPDATE_NUMERIC_COLUMNS:
        df.loc[:, col] = df[col].apply(
            lambda x: str(x).strip() if pd.notna(x) else ''
        )

    df.loc[:, 'cost_center'] = df['cost_center'].apply(
        lambda x: str(x).strip() if pd.notna(x) else None
    )
    df.loc[df['cost_center'] == '', 'cost_center'] = None

    return df


def _read_update_dataframe(update_content, file_name):
    """
    Lee archivo de actualización con estrategia de fallback optimizada.
    """
    lower_name = (file_name or '').lower()

    if lower_name.endswith('.xls') and _looks_like_html_table(update_content):
        logger.info(f"El archivo '{file_name}' parece una tabla HTML. Intentando read_html.")
        try:
            dfs = pd.read_html(io.BytesIO(update_content), encoding='utf-8', header=3)
            for html_df in dfs:
                html_df, missing_cols = _normalize_update_df_columns(html_df)
                if not missing_cols:
                    return html_df
            logger.warning(f"El parseo HTML de '{file_name}' no coincide con columnas requeridas.")
        except Exception as exc:
            logger.warning(f"No se pudo parsear '{file_name}' como HTML: {exc}")

    # Intento rápido con encabezado habitual (fila 4)
    for engine in _candidate_excel_engines(file_name, update_content):
        try:
            update_df = _read_excel_bytes(
                update_content,
                engine=engine,
                header=3,
                dtype='object',
                usecols=_update_usecols_filter,
            )
            update_df, missing_cols = _normalize_update_df_columns(update_df)
            if not missing_cols:
                return update_df
            logger.warning(
                f"Lectura rápida incompleta en '{file_name}' con engine '{engine}': {missing_cols}"
            )
        except Exception as exc:
            logger.warning(f"Lectura rápida falló en '{file_name}' con engine '{engine}': {exc}")

    # Fallback por posiciones fijas de columnas y múltiples posibles headers.
    header_positions = [0, 1, 2, 3, 4]
    usecols = [0, 2, 3, 4, 13, 14, 17, 18, 19, 20, 21, 22]
    last_error = None

    for header_idx in header_positions:
        for engine in _candidate_excel_engines(file_name, update_content):
            try:
                return _read_excel_bytes(
                    update_content,
                    engine=engine,
                    header=header_idx,
                    usecols=usecols,
                    names=UPDATE_FILE_COLUMNS,
                    dtype='object',
                )
            except Exception as exc:
                last_error = exc
                logger.warning(
                    f"Fallback falló en '{file_name}' con engine '{engine}' "
                    f"y fila de encabezado {header_idx + 1}: {exc}"
                )

    if last_error:
        raise last_error
    raise ValueError(f"No se pudo leer el archivo '{file_name}'")


def _normalize_update_df_columns(df):
    """
    Normaliza columnas del DataFrame de actualización usando sinónimos.

    Retorna:
        tuple[pd.DataFrame, list[str]]: dataframe normalizado y
        lista de columnas requeridas faltantes.
    """
    if df is None:
        return None, []
    
    df.columns = df.columns.str.lower().str.strip()
    column_mapping = {}
    
    for expected, syn_list in UPDATE_COLUMN_SYNONYMS.items():
        if expected in df.columns:
            continue
        for syn in syn_list:
            if syn in df.columns:
                column_mapping[syn] = expected
                break
    df.rename(columns=column_mapping, inplace=True)
    
    missing_columns = [col for col in UPDATE_REQUIRED_COLUMNS if col not in df.columns]
    
    return df, missing_columns


def procesar_importacion_inventario(request, inventory_name='default'):
    """
    Procesa una importación completa de inventario.

    El flujo soporta:
    - Carga de archivo base para inicialización.
    - Carga de uno o varios archivos de actualización.
    - Normalización y validación de estructura.
    - Importación por lotes con deduplicación por checksum.

    Parámetros:
        request: solicitud HTTP que contiene `base_file` y/o `update_files`.
        inventory_name (str): nombre lógico del inventario.

    Retorna:
        JsonResponse con resultado de la importación.
    """
    # Manejo de error en caso de que no se envíe Excel válido.
    temp_csv_files = []
    try:
        inventory_name = str(inventory_name).strip().lower() or 'default'

        # Validación inicial: base para primera carga, updates para cargas posteriores.
        base_file = request.FILES.get('base_file')
        base_content = b''
        if base_file:
            # Validar formato y tamaño del archivo base.
            if not base_file.name.lower().endswith(('.xls', '.xlsx')):
                return JsonResponse({'ok': False, 'error': 'Formato de archivo base no válido. Solo se permiten archivos .xls o .xlsx'}, status=400)
            if base_file.size == 0:
                return JsonResponse({'ok': False, 'error': 'El archivo base está vacío'}, status=400)
            base_content = base_file.read()

        update_files = request.FILES.getlist('update_files')
        update_files_data = []
        for update_file in update_files:
            # Validar formato y tamaño de cada archivo de actualización.
            if not update_file.name.lower().endswith(('.xls', '.xlsx')):
                return JsonResponse({'ok': False, 'error': f'Formato de archivo de actualización "{update_file.name}" no válido. Solo se permiten archivos .xls o .xlsx'}, status=400)
            if update_file.size == 0:
                return JsonResponse({'ok': False, 'error': f'El archivo de actualización "{update_file.name}" está vacío'}, status=400)
            file_content = update_file.read()
            update_files_data.append((update_file.name, file_content))

        # Verificar si el inventario ya está inicializado.
        has_base_data = Product.objects.filter(inventory_name=inventory_name).exists()

        # If base file already exists and user is trying to upload base file again, reject
        if has_base_data and base_file:
            return JsonResponse(
                {'ok': False, 'error': 'El archivo base ya ha sido cargado. Solo puede cargar archivos de actualización.'},
                status=400
            )

        if not has_base_data and not base_file:
            return JsonResponse(
                {'ok': False, 'error': 'Debe cargar primero el archivo base para inicializar el inventario'},
                status=400
            )

        # For update files, ensure we have base data
        if update_files and not has_base_data:
            return JsonResponse(
                {'ok': False, 'error': 'Debe cargar el archivo base antes de cargar archivos de actualización'},
                status=400
            )

        if not base_file and not update_files:
            return JsonResponse(
                {'ok': False, 'error': 'Debe proporcionar un archivo (base para inicialización o actualización)'},
                status=400
            )
        # Leemos el contenido del archivo
        try:
            # contenido_base is already read above if base_file exists
            # contenido_actulizacion = update_file.read()  # Already read above
            
            # Leemos el archivo base con estrategia optimizada
            base_df = None
            base_rows = 0
            base_csv_path = None
            if base_file is not None:
                base_df = _read_base_dataframe(base_content, base_file.name)

            # datamanejamos los datos para que no sean nulos
            if base_df is not None:
                base_df = base_df.dropna(subset=['codigo']).copy()
                base_df.loc[:, 'codigo'] = base_df['codigo'].astype(str).str.strip()
                # Eliminar ceros a la izquierda de los códigos de producto en archivo base
                base_df.loc[:, 'codigo'] = base_df['codigo'].str.lstrip('0')
                base_rows = len(base_df)
                base_csv_path = _write_dataframe_to_temp_csv(base_df, prefix='inventory_base_')
                temp_csv_files.append(base_csv_path)
                base_df = None



        except BadZipFile as e:
            logger.error(f"Archivo no es un archivo Excel válido: {str(e)}", exc_info=True)
            return JsonResponse(
                {'ok': False, 'error': 'Uno o más archivos no son archivos Excel válidos (.xls o .xlsx). Verifique que los archivos no estén corruptos.'},
                status=400
            )
        except Exception as e:
            logger.error(f"Error al leer archivos: {str(e)}", exc_info=True)
            return JsonResponse(
                {'ok': False, 'error': 'Error al procesar los archivos. Asegúrese de que sean archivos Excel válidos.'},
                status=400
            )

        # Calculate checksum based on provided files (order-independent)
        file_hashes = []
        if base_content:
            file_hashes.append(calculate_file_checksum(base_content))
        for _, update_file_content in update_files_data:
            file_hashes.append(calculate_file_checksum(update_file_content))

        if file_hashes:
            # Sort hashes to make checksum order-independent
            file_hashes.sort()
            combined_hash_input = ''.join(file_hashes).encode('utf-8')
            checksum = calculate_file_checksum(combined_hash_input)
        else:
            checksum = 'no-files'

        # Crear lote de importación.
        batch_file_names = []
        if base_file:
            batch_file_names.append(base_file.name)
        if update_files:
            batch_file_names.extend([f.name for f in update_files])

        # Si existe un lote igual, se reemplaza para permitir reimportación.
        existing_batch = ImportBatch.objects.filter(
            checksum=checksum,
            inventory_name=inventory_name
        ).first()
        if existing_batch:
            logger.info(f"Eliminando lote existente {existing_batch.id} para reimportación")
            # Eliminar primero los movimientos asociados al lote previo.
            InventoryRecord.objects.filter(batch=existing_batch).delete()
            existing_batch.delete()

        batch = ImportBatch.objects.create(
            file_name=' + '.join(batch_file_names) if batch_file_names else 'no-files',
            inventory_name=inventory_name,
            checksum=checksum
        )

        base_records_count = 0
        base_duplicates_count = 0
        if base_csv_path is not None:
            # Limpiamos productos existentes para este inventario solo si estamos cargando un nuevo base
            # Primero eliminamos registros de inventario para evitar violación de llave foránea
            InventoryRecord.objects.filter(product__inventory_name=inventory_name).delete()
            Product.objects.filter(inventory_name=inventory_name).delete()
            # procesamos el archivo base
            base_records_count, base_duplicates_count = _process_base_csv(
                base_csv_path,
                inventory_name
            )

        # ── Validación de continuidad de fechas ───────────────────────────────
        # Regla de negocio:
        #   1. La fecha mínima del archivo a subir debe ser >= la fecha máxima
        #      ya registrada en BD para no dejar huecos en la serie.
        #   2. Si la fecha mínima del archivo == la fecha máxima en BD (mismo día),
        #      se permite la re-carga: se eliminan primero los registros de ese día
        #      y se reemplazan con los datos nuevos.
        #   3. Si la fecha mínima del archivo > fecha máxima + 1 día, hay un hueco
        #      → se rechaza la carga con mensaje explicativo.
        if update_files_data:
            from ..models import InventoryRecord as _IR
            from django.db.models import Max as _Max
            import datetime as _dt

            # Fecha máxima ya existente en BD para este inventario
            last_date_in_db = _IR.objects.filter(
                product__inventory_name=inventory_name
            ).aggregate(max_date=_Max('date'))['max_date']

            if last_date_in_db is not None:
                # Fecha mínima en los archivos que se van a subir
                min_file_date = None
                for _fname, _fcontent in update_files_data:
                    try:
                        _df_tmp = _read_update_dataframe(_fcontent, _fname)
                        _df_tmp = _normalize_update_dataframe(_df_tmp)
                        _dates = _df_tmp['fecha'].apply(_parse_date_fast).dropna()
                        if not _dates.empty:
                            _file_min = _dates.min()
                            if isinstance(_file_min, _dt.datetime):
                                _file_min = _file_min.date()
                            if min_file_date is None or _file_min < min_file_date:
                                min_file_date = _file_min
                        del _df_tmp
                    except Exception as _exc:
                        logger.warning(f"No se pudo leer fecha mínima de '{_fname}': {_exc}")

                if min_file_date is not None:
                    if isinstance(last_date_in_db, _dt.datetime):
                        last_date_in_db = last_date_in_db.date()

                    if min_file_date < last_date_in_db:
                        # Hueco hacia atrás → rechazo total
                        return JsonResponse({
                            'ok': False,
                            'error': (
                                f'El archivo contiene movimientos desde {min_file_date.strftime("%d/%m/%Y")}, '
                                f'pero ya existen registros hasta {last_date_in_db.strftime("%d/%m/%Y")}. '
                                f'Los archivos de actualización deben empezar desde '
                                f'{last_date_in_db.strftime("%d/%m/%Y")} en adelante '
                                f'para no dejar vacíos en el inventario.'
                            )
                        }, status=400)

                    if min_file_date == last_date_in_db:
                        # Re-carga del último día: eliminar registros de ese día para reemplazarlos
                        deleted_count, _ = _IR.objects.filter(
                            product__inventory_name=inventory_name,
                            date=last_date_in_db
                        ).delete()
                        logger.info(
                            f"Re-carga del día {last_date_in_db}: "
                            f"eliminados {deleted_count} registros previos de ese día."
                        )

                    # min_file_date > last_date_in_db → continuidad normal, sin huecos
        # ── Fin validación de continuidad ─────────────────────────────────────

        # Procesamos los archivos de actualizacion (solo si hay archivos de actualizacion)
        update_records_count = 0
        total_duplicates = 0
        update_rows = 0
        update_files_summary = []
        seen_update_unique_keys = set()
        seen_update_row_signatures = set()
        if update_files_data:
            for file_name, update_content in update_files_data:
                try:
                    update_df = _read_update_dataframe(update_content, file_name)
                    update_df = _normalize_update_dataframe(update_df)
                    file_rows = len(update_df)
                    update_rows += file_rows
                except Exception as exc:
                    logger.error(f"Error reading update file '{file_name}': {exc}", exc_info=True)
                    return JsonResponse(
                        {'ok': False, 'error': f"El archivo de actualización '{file_name}' no se pudo leer. Verifique que sea un archivo Excel válido con la estructura esperada."},
                        status=400
                    )

                records_count, duplicates_count = _process_update_dataframe(
                    batch,
                    update_df,
                    inventory_name,
                    seen_unique_keys=seen_update_unique_keys,
                    seen_row_signatures=seen_update_row_signatures,
                )
                del update_df
                update_records_count += records_count
                total_duplicates += duplicates_count
                skipped_count = max(file_rows - records_count - duplicates_count, 0)
                update_files_summary.append({
                    'file_name': file_name,
                    'rows_input': file_rows,
                    'rows_registered': records_count,
                    'rows_repeated': duplicates_count,
                    'rows_skipped': skipped_count,
                })

        total_imported = base_records_count + update_records_count

        if total_imported == 0:
            # Si no se importaron los registros mandamos alerta
            raise ValueError('No se importaron registros válidos')

        # Cargamos la informacion del lote
        batch.rows_imported = total_imported
        batch.rows_total = base_rows + update_rows
        batch.processed_at = timezone.now()
        batch.save()

        logger.info(f"Importación exitosa. Lote: {batch.id}, Registros: {total_imported}")

        return JsonResponse({
            'ok': True,
            'inventory_name': inventory_name,
            'batch_id': batch.id,
            'summary': {
                'base_records': base_records_count,
                'update_records': update_records_count,
                'total_processed': total_imported,
                'duplicates_base': base_duplicates_count,
                'duplicates_update': total_duplicates,
                'duplicates_total': base_duplicates_count + total_duplicates,
                'update_input_rows': update_rows,
                'update_registered_records': update_records_count,
                'update_repeated_records': total_duplicates,
                'update_files': update_files_summary,
            },
        })

    except Exception as e:
        logger.error(f"Error en update_inventory: {str(e)}", exc_info=True)
        return JsonResponse(
            {'ok': False, 'error': f"Error al procesar la solicitud: {str(e)}"}, 
            status=500
        )
    finally:
        for csv_file in temp_csv_files:
            _remove_temp_file(csv_file)


def _process_base_csv(csv_path, inventory_name):
    """
    Procesa archivo base desde CSV temporal en streaming para reducir RAM.

    Detecta filas repetidas exactas para evitar sumar cantidades/valores duplicados.
    """
    required_columns = BASE_FILE_COLUMNS
    records_processed = 0
    errors = 0
    duplicates_count = 0

    product_aggregates = {}
    warehouse_aggregates = {}
    seen_base_signatures = set()

    for chunk in _iter_csv_chunks(csv_path):
        if not all(col in chunk.columns for col in required_columns):
            logger.error(f"Faltan columnas requeridas en el CSV base: {required_columns}")
            return 0, 0

        chunk = chunk.dropna(subset=['codigo']).copy()
        chunk.loc[:, 'codigo'] = chunk['codigo'].astype(str).str.strip().str.lstrip('0')
        chunk = chunk.loc[
            (chunk['codigo'] != '') & (chunk['codigo'].str.lower() != 'nan')
        ].copy()

        chunk.loc[:, 'descripcion'] = chunk['descripcion'].fillna('').astype(str).str.strip()
        chunk = chunk.loc[chunk['descripcion'] != ''].copy()

        if chunk.empty:
            continue

        # Deduplicado exacto temprano dentro del chunk para reducir trabajo.
        initial_chunk_rows = len(chunk)
        chunk = chunk.drop_duplicates(subset=BASE_FILE_COLUMNS, keep='first').copy()
        duplicates_count += max(initial_chunk_rows - len(chunk), 0)

        for numeric_col in ['cantidad', 'valor_total', 'costo_unitario']:
            chunk.loc[:, numeric_col] = chunk[numeric_col].apply(_decimal_or_clean)

        for row in chunk.itertuples(index=False):
            try:
                codigo = str(getattr(row, 'codigo', '') or '').strip()
                if not codigo:
                    continue

                descripcion = str(getattr(row, 'descripcion', '') or '').strip()
                if not descripcion:
                    continue

                grupo = str(getattr(row, 'grupo', '') or '').strip()
                almacen = str(getattr(row, 'almacen', '') or '').strip()

                cantidad = _decimal_or_clean(getattr(row, 'cantidad', 0))
                valor_total = _decimal_or_clean(getattr(row, 'valor_total', 0))
                costo_unitario = _decimal_or_clean(getattr(row, 'costo_unitario', 0))

                # Firma exacta de fila base para saltar repeticiones idénticas.
                base_signature = _build_row_signature(
                    getattr(row, 'fecha_corte', ''),
                    getattr(row, 'mes', ''),
                    almacen,
                    grupo,
                    codigo,
                    descripcion,
                    cantidad,
                    getattr(row, 'unidad_medida', ''),
                    costo_unitario,
                    valor_total,
                )
                if base_signature in seen_base_signatures:
                    duplicates_count += 1
                    continue
                seen_base_signatures.add(base_signature)

                if codigo not in product_aggregates:
                    product_aggregates[codigo] = {
                        'description': descripcion,
                        'group': grupo,
                        'quantity': Decimal('0'),
                        'value': Decimal('0'),
                        'fallback_unit_cost': costo_unitario,
                    }

                product_data = product_aggregates[codigo]
                product_data['quantity'] += cantidad
                product_data['value'] += valor_total

                if product_data['fallback_unit_cost'] == 0 and costo_unitario != 0:
                    product_data['fallback_unit_cost'] = costo_unitario

                if not product_data['group'] and grupo:
                    product_data['group'] = grupo

                if almacen:
                    warehouse_key = (codigo, almacen)
                    if warehouse_key not in warehouse_aggregates:
                        warehouse_aggregates[warehouse_key] = {
                            'quantity': Decimal('0'),
                            'value': Decimal('0'),
                        }
                    warehouse_aggregates[warehouse_key]['quantity'] += cantidad
                    warehouse_aggregates[warehouse_key]['value'] += valor_total

            except Exception as exc:
                errors += 1
                logger.error(f"Error procesando fila de base CSV: {exc}")

    existing_codes = set(
        Product.objects.filter(inventory_name=inventory_name).values_list('code', flat=True)
    )

    products_to_create = []
    for codigo, product_data in product_aggregates.items():
        if codigo in existing_codes:
            continue

        cantidad_total = product_data['quantity']
        valor_total = product_data['value']
        costo_unitario = (
            valor_total / cantidad_total
            if cantidad_total != 0
            else _decimal_or_clean(product_data['fallback_unit_cost'])
        )

        if cantidad_total == 0 and valor_total > 0:
            if costo_unitario > 0:
                cantidad_total = valor_total / costo_unitario
            else:
                costo_unitario = Decimal('1')
                cantidad_total = valor_total

        descripcion = product_data['description']
        if not descripcion:
            logger.warning(f"Producto con código {codigo} sin descripción, se omitirá")
            continue

        products_to_create.append(Product(
            code=codigo,
            description=descripcion,
            group=_map_categoria_cached(product_data['group']),
            inventory_name=inventory_name,
            initial_balance=cantidad_total,
            initial_unit_cost=costo_unitario,
        ))
        records_processed += 1

        if len(products_to_create) >= 500:
            Product.objects.bulk_create(products_to_create, ignore_conflicts=True)
            products_to_create = []

    if products_to_create:
        try:
            Product.objects.bulk_create(products_to_create, ignore_conflicts=True)
        except Exception as exc:
            logger.error(f"Error en bulk_create de productos base: {exc}")
            for product in products_to_create:
                try:
                    product.save(force_insert=True)
                except Exception:
                    continue

    warehouse_codes = list({code for code, _ in warehouse_aggregates.keys()})
    product_map = {
        p.code: p
        for p in Product.objects.filter(
            inventory_name=inventory_name,
            code__in=warehouse_codes,
        ).only('id', 'code')
    }

    warehouse_details_to_create = []
    for (codigo, almacen), warehouse_data in warehouse_aggregates.items():
        product = product_map.get(codigo)
        if not product:
            logger.warning(f"Producto {codigo} no encontrado para crear detalle de almacén")
            continue

        warehouse_details_to_create.append(WarehouseDetail(
            product=product,
            warehouse=almacen,
            initial_quantity=warehouse_data['quantity'],
            initial_value=warehouse_data['value'],
        ))

        if len(warehouse_details_to_create) >= 1000:
            WarehouseDetail.objects.bulk_create(warehouse_details_to_create, ignore_conflicts=True)
            warehouse_details_to_create = []

    if warehouse_details_to_create:
        try:
            WarehouseDetail.objects.bulk_create(warehouse_details_to_create, ignore_conflicts=True)
        except Exception as exc:
            logger.error(f"Error en bulk_create de warehouse_details: {exc}")
            for wd in warehouse_details_to_create:
                try:
                    wd.save(force_insert=True)
                except Exception:
                    continue

    logger.info(
        f"Procesados {records_processed} productos del archivo base CSV "
        f"({duplicates_count} duplicados, {errors} errores)"
    )
    return records_processed, duplicates_count


def _process_update_csv(
    batch,
    csv_path,
    inventory_name,
    seen_unique_keys=None,
    seen_row_signatures=None,
):
    """
    Procesa CSV de movimientos en chunks para limitar uso de memoria.

    Mantiene sets compartidos para deduplicar también entre chunks
    y entre múltiples archivos de actualización del mismo request.
    """
    total_processed = 0
    total_duplicates = 0
    if seen_unique_keys is None:
        seen_unique_keys = set()
    if seen_row_signatures is None:
        seen_row_signatures = set()

    for chunk_df in _iter_csv_chunks(csv_path):
        if chunk_df.empty:
            continue

        records_count, duplicates_count = _process_update_file(
            batch,
            chunk_df,
            inventory_name,
            seen_unique_keys=seen_unique_keys,
            seen_row_signatures=seen_row_signatures,
        )
        total_processed += records_count
        total_duplicates += duplicates_count

    return total_processed, total_duplicates


def _process_update_dataframe(
    batch,
    update_df,
    inventory_name,
    seen_unique_keys=None,
    seen_row_signatures=None,
):
    """
    Procesa movimientos directamente desde DataFrame en chunks en memoria.
    """
    total_processed = 0
    total_duplicates = 0
    if seen_unique_keys is None:
        seen_unique_keys = set()
    if seen_row_signatures is None:
        seen_row_signatures = set()

    for chunk_df in _iter_dataframe_chunks(update_df):
        if chunk_df.empty:
            continue

        records_count, duplicates_count = _process_update_file(
            batch,
            chunk_df,
            inventory_name,
            seen_unique_keys=seen_unique_keys,
            seen_row_signatures=seen_row_signatures,
        )
        total_processed += records_count
        total_duplicates += duplicates_count

    return total_processed, total_duplicates


def _process_update_file(
    batch,
    df,
    inventory_name,
    seen_unique_keys=None,
    seen_row_signatures=None,
):
    """
    Procesa un bloque de actualización y crea movimientos de inventario.

    Incluye:
    - validación de columnas,
    - creación de productos faltantes,
    - deduplicación contra base de datos y dentro del mismo archivo,
    - inserción masiva con fallback individual.
    """
    # Creamos la base de datos para movimientos de inventario
    records_to_create = []
    records_processed = 0
    duplicates_count = 0
    errors = 0
    if seen_unique_keys is None:
        seen_unique_keys = set()
    if seen_row_signatures is None:
        seen_row_signatures = set()

    # Columnas requeridas para el archivo de actualización
    required_columns = ['item', 'desc_item', 'localizacion', 'categoria', 'fecha', 'documento', 'entradas', 'salidas', 'unitario', 'total']
    if not all(col in df.columns for col in required_columns):
        logger.error(f"Faltan columnas requeridas en el archivo de actualización: {required_columns}")
        return 0, 0

    # Limpiamos y validamos los datos del dataframe
    df = df.dropna(subset=['item', 'fecha', 'documento']).copy()
    df.loc[:, 'item'] = df['item'].astype(str).str.strip()
    df = df.loc[(df['item'] != '') & (df['item'].str.lower() != 'nan')].copy()

    # Eliminar ceros a la izquierda de los códigos de producto
    df.loc[:, 'item'] = df['item'].str.lstrip('0')

    # Recorte temprano de duplicados exactos para reducir costo de CPU.
    initial_rows = len(df)
    dedupe_subset = [col for col in UPDATE_FILE_COLUMNS if col in df.columns]
    df = df.drop_duplicates(subset=dedupe_subset, keep='first').copy()
    duplicates_count += max(initial_rows - len(df), 0)

    if df.empty:
        return 0, duplicates_count

    # Traemos todos los códigos de los productos existentes en una sola consulta
    product_codes = df['item'].unique().tolist()
    products = {
        p.code: p
        for p in Product.objects.filter(
            code__in=product_codes,
            inventory_name=inventory_name
        ).only('id', 'code')
    }

    # Crear productos faltantes en bloque
    missing_products = set(product_codes) - set(products.keys())
    if missing_products:
        logger.info(f"Productos incorporados o agregados al inventario: {sorted(missing_products)}")
        missing_rows = df.loc[df['item'].isin(missing_products)].drop_duplicates(subset=['item'])
        missing_to_create = []
        for product_row in missing_rows.itertuples(index=False):
            missing_code = getattr(product_row, 'item', None)
            if not missing_code:
                continue
            description = str(getattr(product_row, 'desc_item', '') or '').strip()
            if not description:
                description = f'Producto {missing_code}'
            missing_to_create.append(Product(
                code=missing_code,
                description=description,
                group=_map_categoria_cached(
                    str(getattr(product_row, 'categoria', '')).strip()
                ),
                inventory_name=inventory_name,
                initial_balance=0,
                initial_unit_cost=0
            ))

        if missing_to_create:
            try:
                Product.objects.bulk_create(missing_to_create, ignore_conflicts=True)
            except Exception as e:
                logger.error(f"Error en bulk_create de productos faltantes: {str(e)}")

        created_or_existing = Product.objects.filter(
            code__in=missing_products,
            inventory_name=inventory_name
        ).only('id', 'code')
        for product in created_or_existing:
            products[product.code] = product

        unresolved_missing = missing_products - set(products.keys())
        if unresolved_missing:
            logger.warning(f"No se pudieron crear algunos productos faltantes: {sorted(unresolved_missing)}")
            df = df.loc[~df['item'].isin(unresolved_missing)].copy()

    # Preparamos filas válidas primero para evitar consultas por fila
    prepared_rows = []
    candidate_product_ids = set()
    candidate_dates = []

    for idx, row in enumerate(df.itertuples(index=False), start=1):
        try:
            codigo = getattr(row, 'item', None)
            if not codigo:
                continue

            product = products.get(codigo)
            if not product:
                logger.warning(f"Producto {codigo} no encontrado en base de datos, omitiendo")
                errors += 1
                continue

            doc_info = str(getattr(row, 'documento', '') or '')
            if doc_info and len(doc_info) >= 2:
                doc_type = doc_info[:2]
                doc_number = doc_info[2:]
            else:
                doc_type, doc_number = None, None

            final_quantity = _decimal_or_clean(getattr(row, 'cantidad', None))
            entradas = _decimal_or_clean(getattr(row, 'entradas', None))
            salidas = _decimal_or_clean(getattr(row, 'salidas', None))
            quantity = entradas - salidas

            if quantity == 0:
                continue

            unit_cost = _decimal_or_clean(getattr(row, 'unitario', None))
            total = _decimal_or_clean(getattr(row, 'total', None)) or (quantity * unit_cost)
            if unit_cost == 0 and total != 0 and quantity != 0:
                unit_cost = total / abs(quantity)

            fecha_valor = getattr(row, 'fecha', None)
            date_value = _parse_date_fast(fecha_valor)
            if not date_value:
                logger.warning(f"Fecha inválida en fila {idx}: {fecha_valor}")
                errors += 1
                continue

            warehouse = _map_localizacion_cached(
                str(getattr(row, 'localizacion', '')).strip()
            )
            category = _map_categoria_cached(
                str(getattr(row, 'categoria', '')).strip()
            )
            row_cost_center = getattr(row, 'cost_center', None)
            cost_center = str(row_cost_center).strip() if pd.notna(row_cost_center) else None
            if cost_center == '':
                cost_center = None

            # Duplicado de contenido exacto (misma fila de movimiento).
            row_signature = _build_row_signature(
                codigo,
                getattr(row, 'desc_item', ''),
                warehouse,
                category,
                date_value,
                doc_type,
                doc_number,
                entradas,
                salidas,
                quantity,
                unit_cost,
                total,
                final_quantity,
                cost_center,
            )
            if row_signature in seen_row_signatures:
                duplicates_count += 1
                continue
            seen_row_signatures.add(row_signature)

            unique_key = (doc_type, doc_number, product.id, cost_center, date_value, warehouse)

            prepared_rows.append({
                'key': unique_key,
                'product': product,
                'warehouse': warehouse,
                'date': date_value,
                'document_type': doc_type,
                'document_number': doc_number,
                'quantity': quantity,
                'unit_cost': unit_cost,
                'total': total,
                'category': category,
                'final_quantity': final_quantity,
                'cost_center': cost_center,
            })
            candidate_product_ids.add(product.id)
            candidate_dates.append(date_value)

        except Exception as e:
            logger.error(f"Error inesperado al preparar fila {idx}: {str(e)}")
            errors += 1
            continue

    # Cargamos duplicados existentes en una sola consulta acotada
    existing_keys = set()
    if candidate_product_ids and candidate_dates:
        min_date = min(candidate_dates)
        max_date = max(candidate_dates)
        existing_keys = set(
            InventoryRecord.objects.filter(
                product_id__in=candidate_product_ids,
                date__gte=min_date,
                date__lte=max_date
            ).values_list(
                'document_type',
                'document_number',
                'product_id',
                'cost_center',
                'date',
                'warehouse'
            )
        )

    # Procesamos filas preparadas y evitamos duplicados en BD y dentro del mismo archivo
    seen_new_keys = set()
    for prepared in prepared_rows:
        unique_key = prepared['key']
        if (
            unique_key in existing_keys
            or unique_key in seen_new_keys
            or unique_key in seen_unique_keys
        ):
            duplicates_count += 1
            continue

        seen_new_keys.add(unique_key)
        seen_unique_keys.add(unique_key)
        records_to_create.append(InventoryRecord(
            batch=batch,
            product=prepared['product'],
            warehouse=prepared['warehouse'],
            date=prepared['date'],
            document_type=prepared['document_type'],
            document_number=prepared['document_number'],
            quantity=prepared['quantity'],
            unit_cost=prepared['unit_cost'],
            total=prepared['total'],
            category=prepared['category'],
            final_quantity=prepared['final_quantity'],
            cost_center=prepared['cost_center']
        ))

        records_processed += 1

        if len(records_to_create) >= 500:
            try:
                InventoryRecord.objects.bulk_create(records_to_create, ignore_conflicts=True)
                records_to_create = []
            except Exception as e:
                logger.error(f"Error en bulk_create: {str(e)}")
                for rec in records_to_create:
                    try:
                        rec.save(force_insert=True)
                    except Exception as e2:
                        logger.error(f"Error saving individual record: {str(e2)}")
                        continue
                records_to_create = []

    # INSERTAMOS LOS REGISTROS RESTANTES
    if records_to_create:
        try:
            InventoryRecord.objects.bulk_create(records_to_create, ignore_conflicts=True)
        except Exception as e:
            logger.error(f"Error en bulk_create final: {str(e)}")
            # INSERTAMOS INDIVIDUALMENTE EN CASO DE FALLA
            for rec in records_to_create:
                try:
                    rec.save(force_insert=True)
                except Exception as e2:
                    logger.error(f"Error saving final individual record: {str(e2)}")
                    continue

    logger.info(f"Procesados {records_processed} registros de movimientos ({duplicates_count} duplicados, {errors} errores)")
    return records_processed, duplicates_count