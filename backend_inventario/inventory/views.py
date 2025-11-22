import logging
import io
import re
import json
from decimal import Decimal, InvalidOperation
from datetime import datetime
from zipfile import BadZipFile

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter, A4
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from io import BytesIO
import pandas as pd

def safe_decimal(value):
    """
    Safely converts a value to Decimal, handling empty, None, or invalid values.
    """
    if pd.isna(value) or value == '' or str(value).strip() == '':
        return Decimal('0')
    try:
        # Handle Colombian format (comma as decimal separator)
        cleaned_value = str(value).replace(',', '.').strip()
        return Decimal(cleaned_value)
    except (ValueError, TypeError, InvalidOperation):
        return Decimal('0')
from django.http import JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_date
from django.db.models import Sum, F, Q, Case, When, DecimalField, Value, Subquery, OuterRef, Exists, Min
from django.db.models.functions import Coalesce, TruncMonth

from .models import ImportBatch, Product, InventoryRecord
from .utils import (
    clean_number, parse_date, map_localizacion, map_categoria,
    calculate_file_checksum, parse_document, validate_row_data, clean_text
)


logger = logging.getLogger(__name__)

@csrf_exempt
@require_http_methods(["POST"])
def update_inventory(request, inventory_name='default'):
    """
    Updates inventory by processing base files and/or update files.

    This function handles the upload and processing of Excel files (.xls or .xlsx) for inventory management.
    It supports both initial inventory setup (base files) and subsequent updates (update files).
    The function validates file formats, processes the data, and creates appropriate database records.

    Args:
        request: Django HttpRequest object containing uploaded files
        inventory_name (str): Name of the inventory to update (default: 'default')

    Returns:
        JsonResponse: Success response with batch information and summary, or error response

    Raises:
        JsonResponse with error details on validation failures or processing errors
    """
    #Manejo de error en caso de que el usuario no envie el .xlsx
    try:
        inventory_name = str(inventory_name).strip().lower() or 'default'

        # Validate request - base file is required for initial setup, update file for subsequent updates
        base_file = request.FILES.get('base_file')
        base_content = b''
        if base_file:
            # Validate file format and size
            if not base_file.name.lower().endswith(('.xls', '.xlsx')):
                return JsonResponse({'ok': False, 'error': 'Formato de archivo base no válido. Solo se permiten archivos .xls o .xlsx'}, status=400)
            if base_file.size == 0:
                return JsonResponse({'ok': False, 'error': 'El archivo base está vacío'}, status=400)
            base_content = base_file.read()

        update_files = request.FILES.getlist('update_files')
        update_files_data = []
        update_content = b''
        for update_file in update_files:
            # Validate file format and size
            if not update_file.name.lower().endswith(('.xls', '.xlsx')):
                return JsonResponse({'ok': False, 'error': f'Formato de archivo de actualización "{update_file.name}" no válido. Solo se permiten archivos .xls o .xlsx'}, status=400)
            if update_file.size == 0:
                return JsonResponse({'ok': False, 'error': f'El archivo de actualización "{update_file.name}" está vacío'}, status=400)
            file_content = update_file.read()
            update_files_data.append((update_file.name, file_content))
            update_content += file_content

        # Check if base file has been uploaded before
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
            
            # Leemos el archivo base con nombres de columnas específicos
            base_df = None
            if base_file is not None:
                # Support both .xlsx and .xls formats
                if base_file.name.endswith('.xls'):
                    base_df = pd.read_excel(
                        io.BytesIO(base_content),
                        engine='xlrd',
                        header=0,  # Row 1 contains headers
                        usecols='A:J',  # Columns A to J (0-9)
                        names=['fecha_corte', 'mes', 'almacen', 'grupo', 'codigo', 'descripcion', 'cantidad', 'unidad_medida', 'costo_unitario', 'valor_total'],
                        dtype={
                            'fecha_corte': str, 'mes': str, 'almacen': str, 'grupo': str,
                            'codigo': str, 'descripcion': str, 'cantidad': float,
                            'unidad_medida': str, 'costo_unitario': float, 'valor_total': float
                        }
                    )
                else:
                    base_df = pd.read_excel(
                        io.BytesIO(base_content),
                        header=0,  # Row 1 contains headers
                        usecols='A:J',  # Columns A to J (0-9)
                        names=['fecha_corte', 'mes', 'almacen', 'grupo', 'codigo', 'descripcion', 'cantidad', 'unidad_medida', 'costo_unitario', 'valor_total'],
                        dtype={
                            'fecha_corte': str, 'mes': str, 'almacen': str, 'grupo': str,
                            'codigo': str, 'descripcion': str, 'cantidad': float,
                            'unidad_medida': str, 'costo_unitario': float, 'valor_total': float
                        }
                    )

            # datamanejamos los datos para que no sean nulos
            if base_df is not None:
                base_df = base_df.dropna(subset=['codigo'])
                base_df['codigo'] = base_df['codigo'].astype(str).str.strip()
                # Eliminar ceros a la izquierda de los códigos de producto en archivo base
                base_df['codigo'] = base_df['codigo'].str.lstrip('0')



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

        # Calculate checksum based on provided files
        checksum_content = b''
        if base_content:
            checksum_content += base_content
        if update_content:
            checksum_content += update_content

        if checksum_content:
            checksum = calculate_file_checksum(checksum_content)
        else:
            checksum = 'no-files'

        # Create a new import batch
        batch_file_names = []
        if base_file:
            batch_file_names.append(base_file.name)
        if update_files:
            batch_file_names.extend([f.name for f in update_files])

        # Check if batch with same checksum already exists and delete it to allow re-import
        existing_batch = ImportBatch.objects.filter(
            checksum=checksum,
            inventory_name=inventory_name
        ).first()
        if existing_batch:
            logger.info(f"Deleting existing batch {existing_batch.id} with same checksum for re-import")
            existing_batch.delete()

        batch = ImportBatch.objects.create(
            file_name=' + '.join(batch_file_names) if batch_file_names else 'no-files',
            inventory_name=inventory_name,
            checksum=checksum
        )

        base_records_count = 0
        if base_df is not None:
            # Limpiamos productos existentes para este inventario solo si estamos cargando un nuevo base
            # Primero eliminamos registros de inventario para evitar violación de llave foránea
            InventoryRecord.objects.filter(product__inventory_name=inventory_name).delete()
            Product.objects.filter(inventory_name=inventory_name).delete()
            # procesamos el archivo base
            base_records_count = _process_base_file(base_df, inventory_name)

        # Procesamos los archivos de actualizacion (solo si hay archivos de actualizacion)
        update_records_count = 0
        if update_files_data:
            for file_name, update_content in update_files_data:
                # Support both .xlsx and .xls formats for update files
                # Try flexible reading first, then specific column positions
                update_df = None
                read_success = False

                # First, try flexible reading with header=3 (row 4)
                try:
                    update_df = pd.read_excel(io.BytesIO(update_content), header=3)
                    logger.info(f"Trying flexible read for '{file_name}' with header=3, columns found: {list(update_df.columns)}")
                    # Normalize column names to lowercase for case-insensitive matching
                    update_df.columns = update_df.columns.str.lower().str.strip()
                    # Rename columns to match expected names using synonyms
                    column_mapping = {}
                    synonyms = {
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
                        'cost_center': ['cost_center', 'centro_costo', 'cc', 'costcenter', 'centro_costo']
                    }
                    expected_names = list(synonyms.keys())
                    for expected in expected_names:
                        if expected in update_df.columns:
                            continue  # Already correct
                        for syn in synonyms[expected]:
                            if syn in update_df.columns:
                                column_mapping[syn] = expected
                                break
                    update_df.rename(columns=column_mapping, inplace=True)
                    # Check if required columns are present
                    required_columns = ['item', 'desc_item', 'localizacion', 'categoria', 'fecha', 'documento', 'entradas', 'salidas', 'unitario', 'total', 'cantidad']
                    missing_columns = [col for col in required_columns if col not in update_df.columns]
                    if not missing_columns:
                        read_success = True
                        logger.info(f"Flexible read successful for '{file_name}' with header=3")
                    else:
                        logger.warning(f"Flexible read missing columns for '{file_name}': {missing_columns}. Available: {list(update_df.columns)}")
                except Exception as e:
                    logger.warning(f"Flexible read failed for '{file_name}': {str(e)}")

                # If flexible read failed, try specific column positions with different headers
                if not read_success:
                    header_positions = [0, 1, 2, 3, 4]  # Try row 1 to 5 (indices 0 to 4)
                    engines = ['xlrd', 'openpyxl', None]  # None lets pandas choose

                    for header_idx in header_positions:
                        for engine in engines:
                            try:
                                kwargs = {
                                    'header': header_idx,
                                    'usecols': [0, 2, 3, 4, 13, 14, 17, 18, 19, 20, 21, 22],
                                    'names': [
                                        'item', 'desc_item', 'localizacion', 'categoria',
                                        'fecha', 'documento', 'entradas', 'salidas', 'unitario', 'total', 'cantidad', 'cost_center'
                                    ],
                                    'dtype': {
                                        'item': str, 'desc_item': str, 'localizacion': str, 'categoria': str,
                                        'fecha': str, 'documento': str, 'entradas': float, 'salidas': float,
                                        'unitario': float, 'total': float, 'cantidad': float, 'cost_center': str
                                    }
                                }
                                if engine is not None:
                                    kwargs['engine'] = engine

                                update_df = pd.read_excel(io.BytesIO(update_content), **kwargs)
                                read_success = True
                                logger.info(f"Successfully read update file '{file_name}' with specific columns, engine '{engine}' and header row {header_idx + 1}")
                                break
                            except Exception as e:
                                logger.warning(f"Failed specific read with engine '{engine}' and header {header_idx + 1}: {str(e)}")
                                continue
                        if read_success:
                            break

                if not read_success or update_df is None:
                    return JsonResponse(
                        {'ok': False, 'error': f"El archivo de actualización '{file_name}' no se pudo leer. Verifique que sea un archivo Excel válido con la estructura esperada."},
                        status=400
                    )

                # Convertir fecha de YYYYMMDD a formato legible
                update_df['fecha'] = update_df['fecha'].astype(str).str.strip()
                update_df['fecha'] = update_df['fecha'].apply(lambda x: f"{x[:4]}-{x[4:6]}-{x[6:]}" if len(x) == 8 and x.isdigit() else x)

                # Limpiar documento: extraer solo SA/EA y número
                update_df['documento'] = update_df['documento'].astype(str).str.strip()
                update_df['documento'] = update_df['documento'].apply(lambda x: re.sub(r'^[^SAEA]*?(SA|EA)', r'\1', x.upper()) if x else x)

                # Limpiamos datos basura como celdas vacías o nulos
                update_df = update_df.dropna(subset=['item'])  # Remove rows with no code
                update_df['item'] = update_df['item'].astype(str).str.strip()

                # Limpiar las columnas 'entradas' y 'salidas' para manejar valores decimales
                update_df['entradas'] = update_df['entradas'].astype(str).str.strip()
                update_df['entradas'] = update_df['entradas'].str.replace(',', '.', regex=False)
                update_df['entradas'] = update_df['entradas'].str.replace('[^0-9.-]', '', regex=True)
                update_df['entradas'] = pd.to_numeric(update_df['entradas'], errors='coerce').fillna(0)

                update_df['salidas'] = update_df['salidas'].astype(str).str.strip()
                update_df['salidas'] = update_df['salidas'].str.replace(',', '.', regex=False)
                update_df['salidas'] = update_df['salidas'].str.replace('[^0-9.-]', '', regex=True)
                update_df['salidas'] = pd.to_numeric(update_df['salidas'], errors='coerce').fillna(0)

                # Limpiar la columna 'cantidad' para manejar valores no numéricos
                update_df['cantidad'] = update_df['cantidad'].astype(str).str.strip()
                update_df['cantidad'] = update_df['cantidad'].str.replace(',', '.', regex=False)
                update_df['cantidad'] = update_df['cantidad'].str.replace('[^0-9.-]', '', regex=True)
                update_df['cantidad'] = pd.to_numeric(update_df['cantidad'], errors='coerce').fillna(0)

                update_records_count += _process_update_file(batch, update_df, inventory_name)

        total_imported = base_records_count + update_records_count

        if total_imported == 0:
            # Si no se importaron los registros mandamos alerta
            raise ValueError('No se importaron registros válidos')

        # Cargamos la informacion del lote
        base_rows = len(base_df) if base_df is not None else 0
        update_rows = 0
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
                'total_processed': total_imported
            }
        })

    except Exception as e:
        logger.error(f"Error en update_inventory: {str(e)}", exc_info=True)
        return JsonResponse(
            {'ok': False, 'error': f"Error al procesar la solicitud: {str(e)}"}, 
            status=500
        )


def _process_base_file(df, inventory_name):
    """
    Processes the base inventory file to create initial product records.

    This function takes a pandas DataFrame from the base Excel file, validates and cleans the data,
    groups products by code, and creates Product objects in the database. It handles duplicate products
    across different warehouses by aggregating quantities and values.

    Args:
        df (pd.DataFrame): DataFrame containing base file data with columns like 'codigo', 'descripcion', etc.
        inventory_name (str): Name of the inventory to associate products with

    Returns:
        int: Number of product records processed and created

    Raises:
        Logs errors for invalid data but continues processing other records
    """
    #Creamos la base de datos para los productos
    products_to_create = []
    processed_codes = set()
    records_processed = 0
    errors = 0

    # Requiere columnas para el archivo base
    required_columns = ['fecha_corte', 'mes', 'almacen', 'grupo', 'codigo', 'descripcion', 'cantidad', 'unidad_medida', 'costo_unitario', 'valor_total']
    if not all(col in df.columns for col in required_columns):
        logger.error(f"Faltan columnas requeridas en el archivo base: {required_columns}")
        return 0

    # LIMPIAMOS Y VALIDAMOS EL DATAFRAME
    df = df.dropna(subset=['codigo'])
    df['codigo'] = df['codigo'].astype(str).str.strip()
    df['descripcion'] = df['descripcion'].astype(str).str.strip()

    # Filtrar productos sin descripción válida
    df = df[df['descripcion'].notna() & (df['descripcion'].str.strip() != '')]

    # Agrupar por código de producto para sumar cantidades y valores de productos repetidos en diferentes almacenes
    df_grouped = df.groupby(['codigo', 'descripcion', 'grupo']).agg({
        'cantidad': 'sum',
        'valor_total': 'sum',
        'costo_unitario': 'last',  # Tomar el último costo unitario del archivo base
        'almacen': lambda x: ', '.join(sorted(set(x))),  # Concatenar almacenes únicos
        'fecha_corte': 'first',
        'mes': 'first',
        'unidad_medida': 'first'
    }).reset_index()


    # Crear un DataFrame con información detallada por almacén para productos agrupados
    # Esto permitirá filtrar por almacén en el frontend
    warehouse_details = []
    for _, group in df.groupby(['codigo']):
        for _, row in group.iterrows():
            warehouse_details.append({
                'codigo': row['codigo'],
                'almacen': row['almacen'],
                'cantidad': row['cantidad'],
                'valor_total': row['valor_total']
            })

    # Convertir a DataFrame para facilitar consultas posteriores
    warehouse_df = pd.DataFrame(warehouse_details)

    # traer todos los codigos de productos existentes de una vez para reducir consultas a la base de datos
    existing_codes = set(Product.objects.filter(
        inventory_name=inventory_name
    ).values_list('code', flat=True))

    # Preparar cada fila agrupada
    for _, row in df_grouped.iterrows():
        try:
            codigo = row['codigo']
            if not codigo or codigo in processed_codes or codigo in existing_codes:
                continue

            # traer valores de la fila agrupada
            cantidad_total = safe_decimal(row.get('cantidad'))
            costo_unitario = safe_decimal(row.get('costo_unitario'))
            descripcion = row.get('descripcion', '').strip()

            if not descripcion:
                logger.warning(f"Producto con código {codigo} sin descripción, se omitirá")
                continue

            products_to_create.append(Product(
                code=codigo,
                description=descripcion,
                group=map_categoria(str(row.get('grupo', '')).strip()),
                inventory_name=inventory_name,
                initial_balance=cantidad_total,
                initial_unit_cost=costo_unitario
            ))

            processed_codes.add(codigo)
            records_processed += 1

            # INSERTAMOS EN BLOQUE DE 500
            if len(products_to_create) >= 500:
                Product.objects.bulk_create(products_to_create, ignore_conflicts=True)
                products_to_create = []

        except Exception as e:
            errors += 1
            logger.error(f"Error procesando producto {row.get('codigo', '')}: {str(e)}")
            continue

    # Insertamos los productos restantes
    if products_to_create:
        try:
            Product.objects.bulk_create(products_to_create, ignore_conflicts=True)
        except Exception as e:
            logger.error(f"Error en bulk_create: {str(e)}")
            # individual insertamos los productos restantes
            for product in products_to_create:
                try:
                    product.save(force_insert=True)
                    records_processed += 1
                except:
                    continue

    logger.info(f"Procesados {records_processed} productos del archivo base ({errors} errores)")
    return records_processed


def _process_update_file(batch, df, inventory_name):
    """
    Processes update files to create inventory movement records.

    This function takes a pandas DataFrame from update Excel files, validates and cleans the data,
    and creates InventoryRecord objects for each movement. It handles missing products by creating
    them with zero initial balance if needed.

    Args:
        batch (ImportBatch): The import batch to associate records with
        df (pd.DataFrame): DataFrame containing update file data
        inventory_name (str): Name of the inventory

    Returns:
        int: Number of inventory records processed and created

    Raises:
        Logs errors for invalid data but continues processing other records
    """
    # Creamos la base de datos para movimientos de inventario
    records_to_create = []
    records_processed = 0
    errors = 0

    # Columnas requeridas para el archivo de actualización
    required_columns = ['item', 'desc_item', 'localizacion', 'categoria', 'fecha', 'documento', 'entradas', 'salidas', 'unitario', 'total']
    if not all(col in df.columns for col in required_columns):
        logger.error(f"Faltan columnas requeridas en el archivo de actualización: {required_columns}")
        return 0

    # Limpiamos y validamos los datos del dataframe
    df = df.dropna(subset=['item', 'fecha', 'documento'])
    df['item'] = df['item'].astype(str).str.strip()

    # Eliminar ceros a la izquierda de los códigos de producto
    df['item'] = df['item'].str.lstrip('0')

    # Traemos todos los códigos de los productos existentes para reducir consultas en la base de datos
    # Solo productos que ya existen del archivo base
    product_codes = df['item'].unique()
    products = {p.code: p for p in Product.objects.filter(
        code__in=product_codes,
        inventory_name=inventory_name
    )}

    # Verificar que todos los productos del archivo de actualización existan en el base
    missing_products = set(product_codes) - set(products.keys())
    new_products_count = 0
    if missing_products:
        print(f"Productos incorporados o agregados al inventario: {sorted(missing_products)}")
        logger.info(f"Productos incorporados o agregados al inventario: {sorted(missing_products)}")
        # Para archivos de actualización, permitimos productos que no existen en base
        # pero los creamos con saldo inicial 0 (solo para movimientos históricos)
        # Usamos una transacción separada para asegurar que los productos se guarden incluso si falla el procesamiento de registros
        for missing_code in missing_products:
            try:
                # Buscar la primera fila de este producto para obtener descripción y categoría
                product_row = df[df['item'] == missing_code].iloc[0] if len(df[df['item'] == missing_code]) > 0 else None
                if product_row is not None:
                    Product.objects.create(
                        code=missing_code,
                        description=product_row.get('desc_item', f'Producto {missing_code}').strip(),
                        group=map_categoria(str(product_row.get('categoria', '')).strip()),
                        inventory_name=inventory_name,
                        initial_balance=0,
                        initial_unit_cost=0
                    )
                    products[missing_code] = Product.objects.get(code=missing_code, inventory_name=inventory_name)
                    new_products_count += 1
                    print(f"Creado producto faltante: {missing_code}")
                    logger.info(f"Creado producto faltante: {missing_code}")
            except Exception as e:
                logger.error(f"Error creando producto faltante {missing_code}: {str(e)}")
                # Filtrar filas de productos que no se pudieron crear
                df = df[df['item'] != missing_code]

    # Procesamos cada una de las filas
    for idx, row in df.iterrows():
        try:
            codigo = row['item']
            if not codigo:
                continue

            # El producto debe existir (ya sea del base o creado arriba)
            if codigo not in products:
                logger.warning(f"Producto {codigo} no encontrado en base de datos, omitiendo")
                errors += 1
                continue

            product = products[codigo]

            # Documento information - usar el documento ya limpiado
            doc_info = str(row.get('documento', ''))
            if doc_info and len(doc_info) >= 2:
                doc_type = doc_info[:2]  # SA o EA
                doc_number = doc_info[2:]  # número restante
            else:
                doc_type, doc_number = None, None

            # Get quantities - usar la columna 'cantidad' como cantidad final después del movimiento
            try:
                final_quantity = safe_decimal(row.get('cantidad'))

                # Para calcular el movimiento neto, necesitamos el saldo anterior
                # Pero como no tenemos el saldo anterior aquí, calculamos el movimiento basado en entradas y salidas
                entradas = safe_decimal(row.get('entradas'))
                salidas = safe_decimal(row.get('salidas'))
                quantity = entradas - salidas

                if quantity == 0:
                    logger.info(f"Skipping row {idx}: quantity is 0 (entradas={entradas}, salidas={salidas})")
                    continue  # Saltamos registros sin movimiento

                # Traemos costos y totales
                unit_cost = safe_decimal(row.get('unitario'))
                total = safe_decimal(row.get('total')) or (abs(quantity) * unit_cost)

                # Calculate unit_cost from total if missing
                if unit_cost == 0 and total != 0 and quantity != 0:
                    unit_cost = total / abs(quantity)

                # FECHA de movimiento - usar la fecha ya convertida
                date_str = str(row.get('fecha', ''))
                try:
                    # Intentar parsear fecha en formato YYYY-MM-DD
                    date = datetime.strptime(date_str, '%Y-%m-%d').date()
                except ValueError:
                    logger.warning(f"Fecha inválida en fila {idx}: {date_str}")
                    errors += 1
                    continue

                # Creamos el registro de inventario
                records_to_create.append(InventoryRecord(
                    batch=batch,
                    product=product,
                    warehouse=map_localizacion(str(row.get('localizacion', '')).strip()),
                    date=date,
                    document_type=doc_type,
                    document_number=doc_number,
                    quantity=quantity,
                    unit_cost=unit_cost,
                    total=total,
                    category=map_categoria(str(row.get('categoria', '')).strip()),
                    final_quantity=final_quantity,
                    cost_center=str(row.get('cost_center', '')).strip() if pd.notna(row.get('cost_center')) else None
                ))

                # No actualizamos información del producto desde archivo de actualización
                # Solo registramos los movimientos

                records_processed += 1

                # INSERTAMOS EN BLOQUES DE 500
                if len(records_to_create) >= 500:
                    try:
                        InventoryRecord.objects.bulk_create(records_to_create, ignore_conflicts=True)
                        records_to_create = []
                    except Exception as e:
                        logger.error(f"Error en bulk_create: {str(e)}")
                        # INSERTAMOS INDIVIDUALMENTE EN CASO DE FALLA
                        for rec in records_to_create:
                            try:
                                rec.save(force_insert=True)
                            except Exception as e2:
                                logger.error(f"Error saving individual record: {str(e2)}")
                                continue
                        records_to_create = []

            except (ValueError, TypeError) as e:
                logger.warning(f"Error en valores numéricos en fila {idx}: {str(e)}")
                errors += 1
                continue

        except Exception as e:
            logger.error(f"Error inesperado al procesar fila {idx}: {str(e)}")
            errors += 1
            continue

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

    logger.info(f"Procesados {records_processed} registros de movimientos ({errors} errores)")
    return records_processed


@require_http_methods(["GET"])
def get_product_analysis(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    category_filter = request.GET.get('category', '')

    try:
        products_query = Product.objects.filter(inventory_name=inventory_name)

        if category_filter:
            products_query = products_query.filter(group__icontains=category_filter)



        products = products_query
    except Exception as e:
        logger.error(f"Error in product analysis query: {str(e)}", exc_info=True)
        return JsonResponse([], safe=False)

    analysis_data = []
    current_year = datetime.now().year

    for p in products:
        try:
            # Get the most recent inventory record to determine current stock and cost
            last_record = InventoryRecord.objects.filter(product=p).order_by('-date', '-id').first()

            if last_record:
                current_stock = Decimal(last_record.final_quantity or 0)
                current_unit_cost = Decimal(last_record.unit_cost or p.initial_unit_cost or 0)
            else:
                current_stock = Decimal(p.initial_balance or 0)
                current_unit_cost = Decimal(p.initial_unit_cost or 0)

            # Producto consumido
            is_consumed = (current_stock <= 0)

            # ------------------------------------------
            #        ROTACIÓN / ESTANCAMIENTO
            # ------------------------------------------
            pre_year_sum = InventoryRecord.objects.filter(
                product=p,
                date__year__lt=current_year
            ).aggregate(s=Sum('quantity'))['s'] or Decimal('0')

            balance_pre_year = Decimal(p.initial_balance or 0) + Decimal(pre_year_sum)

            monthly_movements = InventoryRecord.objects.filter(
                product=p,
                date__year=current_year
            ).annotate(month=TruncMonth('date')).values('month').annotate(
                monthly_total=Sum('quantity')
            ).order_by('month')

            movements_by_month = {m['month'].month: m['monthly_total'] for m in monthly_movements}

            monthly_balances = []
            running_balance = balance_pre_year
            for m in range(1, 13):
                running_balance += movements_by_month.get(m, Decimal('0'))
                monthly_balances.append(running_balance)

            all_zero_balance = all(b == 0 for b in monthly_balances)
            unique_balances = set(monthly_balances)

            # Rotación logic
            if all_zero_balance and balance_pre_year == 0:
                rotation = "Activo"
            elif all_zero_balance and balance_pre_year > 0:
                rotation = "Obsoleto"
            elif len(unique_balances) == 1 and monthly_balances[0] > 0:
                rotation = "Obsoleto"
            elif len(monthly_balances) >= 3 and len(set(monthly_balances[-3:])) == 1 and monthly_balances[-1] > 0:
                rotation = "Estancado"
            else:
                rotation = "Activo"

            is_stagnant = rotation in ["Estancado", "Obsoleto"]

            consecutive_changes = sum(
                1 for i in range(len(monthly_balances)-1)
                if monthly_balances[i] != monthly_balances[i+1]
            )
            high_rotation = 'Sí' if consecutive_changes >= 2 else 'No'

            analysis_data.append({
                'codigo': p.code,
                'nombre_producto': p.description,
                'grupo': p.group,
                'cantidad_saldo_actual': float(current_stock),
                'valor_saldo_actual': float(current_stock * current_unit_cost),
                'costo_unitario': float(current_unit_cost),
                'consumed': 'Sí' if is_consumed else 'No',
                'estancado': 'Sí' if is_stagnant else 'No',
                'rotacion': rotation,
                'alta_rotacion': high_rotation,
                'almacen': 'almacen',
            })

        except Exception as e:
            logger.error(f"Error processing product {p.code}: {str(e)}", exc_info=True)
            continue

    return JsonResponse(analysis_data, safe=False)



@require_http_methods(["GET"])
def get_batches(request):
    """
    Retrieves a list of import batches for the specified inventory.

    Args:
        request: Django HttpRequest with query parameter 'inventory_name'

    Returns:
        JsonResponse: List of batch data including IDs, file names, timestamps, and processing stats
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    batches = ImportBatch.objects.filter(inventory_name=inventory_name).order_by('-started_at')
    
    batches_data = [{
        'id': batch.id,
        'file_name': batch.file_name,
        'inventory_name': batch.inventory_name,
        'started_at': batch.started_at.isoformat(),
        'processed_at': batch.processed_at.isoformat() if batch.processed_at else None,
        'rows_imported': batch.rows_imported,
        'rows_total': batch.rows_total,
        'checksum': batch.checksum,
    } for batch in batches]
    return JsonResponse(batches_data, safe=False)

@require_http_methods(["GET"])
def get_products(request):
    """
    Retrieves a list of products for the specified inventory.

    Args:
        request: Django HttpRequest with query parameter 'inventory_name'

    Returns:
        JsonResponse: List of product data including codes, descriptions, groups, and balances
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    products = Product.objects.filter(inventory_name=inventory_name)
    products_data = [{
        'code': p.code,
        'description': p.description,
        'group': p.group,
        'initial_balance': float(p.initial_balance),
        'initial_unit_cost': float(p.initial_unit_cost),
    } for p in products]
    return JsonResponse(products_data, safe=False)

@require_http_methods(["GET"])
def get_records(request):
    """
    Retrieves inventory records with optional filtering.

    Args:
        request: Django HttpRequest with query parameters for filtering

    Query Parameters:
        inventory_name (str): Name of the inventory
        warehouse (str): Filter by warehouse
        category (str): Filter by category
        date_from (str): Start date filter
        date_to (str): End date filter

    Returns:
        JsonResponse: List of inventory records or empty list on error
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    date_from = request.GET.get('date_from', '')
    date_to = request.GET.get('date_to', '')

    try:
        records_query = InventoryRecord.objects.filter(product__inventory_name=inventory_name).select_related('product', 'batch')

        # Aplicar filtros
        if warehouse_filter:
            records_query = records_query.filter(warehouse__icontains=warehouse_filter)
        if category_filter:
            records_query = records_query.filter(category__icontains=category_filter)
        if date_from:
            records_query = records_query.filter(date__gte=date_from)
        if date_to:
            records_query = records_query.filter(date__lte=date_to)

        # Limit records for performance - return only recent 1000 records
        records = records_query.order_by('-date')[:1000]
        records_data = [{
            'id': r.id,
            'product_code': r.product.code,
            'product_description': r.product.description,
            'warehouse': r.warehouse,
            'date': r.date.isoformat(),
            'document_type': r.document_type,
            'document_number': r.document_number,
            'quantity': float(r.quantity),
            'unit_cost': float(r.unit_cost),
            'total': float(r.total),
            'category': r.category,
            'batch_id': r.batch.id,
        } for r in records]
        return JsonResponse(records_data, safe=False)

    except Exception as e:
        logger.error(f"Error retrieving records: {str(e)}", exc_info=True)
        return JsonResponse([], safe=False)


@require_http_methods(["POST"])
def create_inventory(request):
    """
    Creates a new inventory.

    Args:
        request: Django HttpRequest with inventory data

    Returns:
        JsonResponse: Success or error response
    """
    try:
        data = json.loads(request.body)
        inventory_name = data.get('inventory_name', '').strip().lower()
        if not inventory_name:
            return JsonResponse({'ok': False, 'error': 'Nombre de inventario requerido'}, status=400)

        # Check if inventory already exists
        if Product.objects.filter(inventory_name=inventory_name).exists():
            return JsonResponse({'ok': False, 'error': 'El inventario ya existe'}, status=400)

        return JsonResponse({'ok': True, 'inventory_name': inventory_name})
    except Exception as e:
        logger.error(f"Error creating inventory: {str(e)}", exc_info=True)
        return JsonResponse({'ok': False, 'error': str(e)}, status=500)


@require_http_methods(["GET"])
def get_product_history(request, product_code, inventory_name='default'):
    """
    Retrieves the history of movements for a specific product.

    Args:
        request: Django HttpRequest
        product_code (str): Product code
        inventory_name (str): Inventory name

    Returns:
        JsonResponse: List of product movement records
    """
    try:
        records = InventoryRecord.objects.filter(
            product__code=product_code,
            product__inventory_name=inventory_name
        ).select_related('product', 'batch').order_by('date')

        history_data = [{
            'id': r.id,
            'date': r.date.isoformat(),
            'quantity': float(r.quantity),
            'unit_cost': float(r.unit_cost),
            'total': float(r.total),
            'warehouse': r.warehouse,
            'document_type': r.document_type,
            'document_number': r.document_number,
            'batch_id': r.batch.id,
        } for r in records]

        return JsonResponse(history_data, safe=False)
    except Exception as e:
        logger.error(f"Error retrieving product history: {str(e)}", exc_info=True)
        return JsonResponse([], safe=False)


@require_http_methods(["GET"])
def get_summary(request):
    """
    Retrieves a summary of the inventory.

    Args:
        request: Django HttpRequest

    Returns:
        JsonResponse: Inventory summary data
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    try:
        total_products = Product.objects.filter(inventory_name=inventory_name).count()
        total_records = InventoryRecord.objects.filter(product__inventory_name=inventory_name).count()
        total_batches = ImportBatch.objects.filter(inventory_name=inventory_name).count()

        # Get analysis data to calculate totals
        analysis_response = get_product_analysis(request)
        if analysis_response.status_code == 200:
            analysis_data = json.loads(analysis_response.content)
            total_quantity = sum(item['cantidad_saldo_actual'] for item in analysis_data if item['cantidad_saldo_actual'] > 0)
            total_value = sum(item['valor_saldo_actual'] for item in analysis_data)
        else:
            total_quantity = 0
            total_value = 0

        return JsonResponse({
            'inventory_name': inventory_name,
            'total_products': total_products,
            'total_records': total_records,
            'total_batches': total_batches,
            'total_quantity': total_quantity,
            'total_value': total_value,
        })
    except Exception as e:
        logger.error(f"Error retrieving summary: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


@require_http_methods(["GET"])
def export_analysis(request, inventory_name='default', format_type='excel'):
    """
    Exports product analysis data.

    Args:
        request: Django HttpRequest
        inventory_name (str): Inventory name
        format_type (str): Export format (excel or pdf)

    Returns:
        HttpResponse: File response
    """
    try:
        # Get analysis data
        analysis_data = get_product_analysis(request).content
        analysis_list = json.loads(analysis_data)

        if format_type == 'excel':
            # Create Excel file
            df = pd.DataFrame(analysis_list)
            response = HttpResponse(content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            response['Content-Disposition'] = f'attachment; filename="inventory_analysis_{inventory_name}.xlsx"'
            df.to_excel(response, index=False)
            return response
        elif format_type == 'pdf':
            # Create PDF file
            buffer = BytesIO()
            doc = SimpleDocTemplate(buffer, pagesize=A4)
            elements = []

            # Use Times fonts which support Unicode/Latin characters
            styles = getSampleStyleSheet()
            title_style = ParagraphStyle(
                'CustomTitle',
                parent=styles['Title'],
                fontName='Times-Bold',
                fontSize=18,
            )
            title = Paragraph(f"Análisis de Inventario - {inventory_name}", title_style)
            elements.append(title)
            elements.append(Spacer(1, 12))

            # Prepare data for table
            if analysis_list:
                headers = list(analysis_list[0].keys())
                data = [headers] + [list(item.values()) for item in analysis_list]

                # Create table
                table = Table(data)
                style = TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Times-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 14),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
                    ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
                    ('FONTNAME', (0, 1), (-1, -1), 'Times-Roman'),
                    ('FONTSIZE', (0, 1), (-1, -1), 10),
                    ('GRID', (0, 0), (-1, -1), 1, colors.black)
                ])
                table.setStyle(style)
                elements.append(table)

            doc.build(elements)
            buffer.seek(0)

            response = HttpResponse(buffer.getvalue(), content_type='application/pdf')
            response['Content-Disposition'] = f'attachment; filename="inventory_analysis_{inventory_name}.pdf"'
            return response
        else:
            return JsonResponse({'error': 'Formato no soportado'}, status=400)
    except Exception as e:
        logger.error(f"Error exporting analysis: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


@require_http_methods(["GET"])
def list_inventories(request):
    """
    Lists all available inventories.

    Args:
        request: Django HttpRequest

    Returns:
        JsonResponse: List of inventory names
    """
    try:
        inventories = Product.objects.values_list('inventory_name', flat=True).distinct()
        return JsonResponse(list(inventories), safe=False)
    except Exception as e:
        logger.error(f"Error listing inventories: {str(e)}", exc_info=True)
        return JsonResponse([], safe=False)


@csrf_exempt
@require_http_methods(["POST"])
def upload_base_file(request, inventory_name='default'):
    """
    Uploads a base file for inventory initialization.

    Args:
        request: Django HttpRequest with uploaded file
        inventory_name (str): Inventory name

    Returns:
        JsonResponse: Success or error response
    """
    # This is similar to update_inventory but only for base files
    return update_inventory(request, inventory_name)


@require_http_methods(["GET"])
def welcome(request):
    """
    Returns a welcome message for the API.

    Args:
        request: Django HttpRequest

    Returns:
        JsonResponse: Welcome message
    """
    logger.info(f"Request received: {request.method} {request.path}")
    return JsonResponse({'message': 'Welcome to the Inventory API Service!'})
