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
from django.db import transaction, IntegrityError
from django.utils import timezone
from django.utils.dateparse import parse_date
from django.db.models import Sum, F, Q, Case, When, DecimalField, Value, Subquery, OuterRef, Exists, Min
from django.db.models.functions import Coalesce, TruncMonth
from django.contrib.postgres.aggregates import StringAgg as GroupConcat
from django.utils.timezone import now
from dateutil.relativedelta import relativedelta

from .models import ImportBatch, Product, InventoryRecord, WarehouseDetail
from .utils import (
    clean_number, parse_date, map_localizacion, map_categoria,
    calculate_file_checksum, parse_document, validate_row_data, clean_text
)


logger = logging.getLogger(__name__)

def _normalize_update_df_columns(df):
    """
    Normalizes column names of an update-file DataFrame using a synonym map.
    Returns the normalized DataFrame and a list of missing required columns.
    """
    if df is None:
        return None, []
    
    df.columns = df.columns.str.lower().str.strip()
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
    
    for expected, syn_list in synonyms.items():
        if expected in df.columns:
            continue
        for syn in syn_list:
            if syn in df.columns:
                column_mapping[syn] = expected
                break
    df.rename(columns=column_mapping, inplace=True)
    
    required_columns = ['item', 'desc_item', 'localizacion', 'categoria', 'fecha', 'documento', 'entradas', 'salidas', 'unitario', 'total', 'cantidad']
    missing_columns = [col for col in required_columns if col not in df.columns]
    
    return df, missing_columns


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

        # Calculate checksum based on provided files (order-independent)
        file_hashes = []
        if base_content:
            file_hashes.append(calculate_file_checksum(base_content))
        for update_content in update_files_data:
            file_hashes.append(calculate_file_checksum(update_content[1]))  # update_content[1] is the file content

        if file_hashes:
            # Sort hashes to make checksum order-independent
            file_hashes.sort()
            combined_hash_input = ''.join(file_hashes).encode('utf-8')
            checksum = calculate_file_checksum(combined_hash_input)
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
            logger.info(f"Deleting existing batch {existing_batch.id} and its records for re-import")
            # Delete associated inventory records first
            InventoryRecord.objects.filter(batch=existing_batch).delete()
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
        total_duplicates = 0
        if update_files_data:
            for file_name, update_content in update_files_data:
                # Support both .xlsx and .xls formats for update files
                # Try flexible reading first, then specific column positions
                update_df = None
                read_success = False

                # If file appears to be HTML, try parsing it first
                if file_name.lower().endswith('.xls') and b'<html' in update_content.lower():
                    logger.info(f"File '{file_name}' appears to be an HTML table, attempting to parse.")
                    try:
                        dfs = pd.read_html(io.BytesIO(update_content), encoding='utf-8', header=3)
                        if dfs:
                            update_df = dfs[0]
                            update_df, missing_cols = _normalize_update_df_columns(update_df)
                            if not missing_cols:
                                read_success = True
                                logger.info(f"Successfully parsed HTML file '{file_name}'.")
                            else:
                                logger.warning(f"HTML parse missing columns for '{file_name}': {missing_cols}")
                                update_df = None  # Invalidate df if columns are wrong
                        else:
                            logger.warning(f"No tables found in HTML file '{file_name}'.")
                    except Exception as e:
                        logger.warning(f"Could not parse file '{file_name}' as HTML: {e}")

                # If not successfully read as HTML, try as Excel (flexible read)
                if not read_success:
                    try:
                        update_df = pd.read_excel(io.BytesIO(update_content), header=3)
                        update_df, missing_cols = _normalize_update_df_columns(update_df)
                        if not missing_cols:
                            read_success = True
                            logger.info(f"Flexible Excel read successful for '{file_name}'.")
                        else:
                            logger.warning(f"Flexible Excel read missing columns for '{file_name}': {missing_cols}")
                            update_df = None # Invalidate df
                    except Exception as e:
                        logger.warning(f"Flexible Excel read failed for '{file_name}': {str(e)}")

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

                records_count, duplicates_count = _process_update_file(batch, update_df, inventory_name)
                update_records_count += records_count
                total_duplicates += duplicates_count

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
    # Calcular costo unitario ponderado cuando hay productos en múltiples almacenes
    def process_group(group):
        total_quantity = group['cantidad'].sum()
        total_value = group['valor_total'].sum()
        if total_quantity != 0:
            weighted_cost = total_value / total_quantity
        else:
            weighted_cost = group['costo_unitario'].iloc[0] if not group.empty else 0
        
        return pd.Series({
            'cantidad': total_quantity,
            'valor_total': total_value,
            'costo_unitario': weighted_cost,
            'almacen': ', '.join(sorted(set(group['almacen']))),
            'fecha_corte': group['fecha_corte'].iloc[0],
            'mes': group['mes'].iloc[0],
            'unidad_medida': group['unidad_medida'].iloc[0]
        })

    df_grouped = df.groupby(['codigo', 'descripcion', 'grupo']).apply(process_group).reset_index()


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
            valor_total = safe_decimal(row.get('valor_total'))
            costo_unitario = safe_decimal(row.get('costo_unitario'))
            descripcion = row.get('descripcion', '').strip()

            # Si cantidad es 0 pero hay valor_total, ajustar para preservar el valor
            if cantidad_total == 0 and valor_total > 0:
                if costo_unitario > 0:
                    cantidad_total = valor_total / costo_unitario
                else:
                    # Si no hay costo unitario, asumir costo 1 para preservar valor
                    costo_unitario = Decimal('1')
                    cantidad_total = valor_total

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

    # Crear detalles por almacén para productos del archivo base
    warehouse_details_to_create = []
    for _, row in warehouse_df.iterrows():
        try:
            codigo = row['codigo']
            almacen = row['almacen']
            cantidad = safe_decimal(row['cantidad'])
            valor_total = safe_decimal(row['valor_total'])

            # Buscar el producto creado
            try:
                product = Product.objects.get(code=codigo, inventory_name=inventory_name)
                warehouse_details_to_create.append(WarehouseDetail(
                    product=product,
                    warehouse=almacen,
                    initial_quantity=cantidad,
                    initial_value=valor_total
                ))
            except Product.DoesNotExist:
                logger.warning(f"Producto {codigo} no encontrado para crear detalle de almacén")
                continue

        except Exception as e:
            logger.error(f"Error creando detalle de almacén para {row.get('codigo', '')}: {str(e)}")
            continue

    # Insertar detalles de almacén en bloques
    if warehouse_details_to_create:
        try:
            WarehouseDetail.objects.bulk_create(warehouse_details_to_create, ignore_conflicts=True)
        except Exception as e:
            logger.error(f"Error en bulk_create de warehouse_details: {str(e)}")
            # Insertar individualmente en caso de falla
            for wd in warehouse_details_to_create:
                try:
                    wd.save(force_insert=True)
                except Exception as e2:
                    logger.error(f"Error saving warehouse detail: {str(e2)}")
                    continue

    logger.info(f"Procesados {records_processed} productos del archivo base ({errors} errores)")
    return records_processed


def _process_update_file(batch, df, inventory_name):
    """
    Processes update files to create inventory movement records.

    This function takes a pandas DataFrame from update Excel files, validates and cleans the data,
    and creates InventoryRecord objects for each movement. It handles missing products by creating
    them with zero initial balance if needed. It also detects and counts duplicate records based on
    the unique_together constraint.

    Args:
        batch (ImportBatch): The import batch to associate records with
        df (pd.DataFrame): DataFrame containing update file data
        inventory_name (str): Name of the inventory

    Returns:
        tuple: (int, int) Number of inventory records processed and created, number of duplicates found

    Raises:
        Logs errors for invalid data but continues processing other records
    """
    # Creamos la base de datos para movimientos de inventario
    records_to_create = []
    records_processed = 0
    duplicates_count = 0
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

                # Create inventory record - check for duplicates across all batches
                warehouse = map_localizacion(str(row.get('localizacion', '')).strip())
                category = map_categoria(str(row.get('categoria', '')).strip())
                cost_center = str(row.get('cost_center', '')).strip() if pd.notna(row.get('cost_center')) else None

                # Check if record already exists across all batches
                existing_record = InventoryRecord.objects.filter(
                    document_type=doc_type,
                    document_number=doc_number,
                    product=product,
                    cost_center=cost_center,
                    date=date,
                    warehouse=warehouse
                ).first()

                if existing_record:
                    duplicates_count += 1
                    logger.info(f"Duplicate record skipped: {doc_type}-{doc_number} for product {product.code} on {date}")
                    continue

                # Creamos el registro de inventario
                records_to_create.append(InventoryRecord(
                    batch=batch,
                    product=product,
                    warehouse=warehouse,
                    date=date,
                    document_type=doc_type,
                    document_number=doc_number,
                    quantity=quantity,
                    unit_cost=unit_cost,
                    total=total,
                    category=category,
                    final_quantity=final_quantity,
                    cost_center=cost_center
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

    logger.info(f"Procesados {records_processed} registros de movimientos ({duplicates_count} duplicados, {errors} errores)")
    return records_processed, duplicates_count


@require_http_methods(["GET"])
def get_monthly_movements(request):
    """
    Retornamos las entradas y salidas por mes y el saldo final de cada mes en inventario
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    search_filter = request.GET.get('search', '')

    try:
        # Determinamos un periodos de 12 meses de movimientos
        today = now().date()
        twelve_months_ago = today - relativedelta(months=11)
        start_of_period = twelve_months_ago.replace(day=1)

        # Base queryset for filtering
        base_queryset = InventoryRecord.objects.filter(product__inventory_name=inventory_name)

        # Apply filters
        if warehouse_filter:
            base_queryset = base_queryset.filter(warehouse__icontains=warehouse_filter)
        if category_filter:
            base_queryset = base_queryset.filter(category__icontains=category_filter)
        if search_filter:
            base_queryset = base_queryset.filter(
                Q(product__code__icontains=search_filter) | Q(product__description__icontains=search_filter)
            )

        # 1. Obtenemos el total inicial de todos los productos (filtered if applicable)
        if warehouse_filter:
            # When filtering by warehouse, use WarehouseDetail for accurate initial values per warehouse
            initial_stock_query = WarehouseDetail.objects.filter(
                product__inventory_name=inventory_name,
                warehouse__icontains=warehouse_filter
            )
            if category_filter:
                initial_stock_query = initial_stock_query.filter(product__group__icontains=category_filter)
            initial_stock_value = initial_stock_query.aggregate(
                total_initial_value=Sum('initial_value')
            )['total_initial_value'] or Decimal('0')
        else:
            # No warehouse filter, use Product initial balances
            initial_stock_query = Product.objects.filter(inventory_name=inventory_name)
            if category_filter:
                initial_stock_query = initial_stock_query.filter(group__icontains=category_filter)
            initial_stock_value = initial_stock_query.aggregate(
                total_initial_value=Sum(F('initial_balance') * F('initial_unit_cost'))
            )['total_initial_value'] or Decimal('0')

        # 2. Obtenemos el valor total de los movimientos antes de los 12 meses (filtered)
        past_movements_value = base_queryset.filter(
            date__lt=start_of_period
        ).aggregate(
            total_value=Sum('total')
        )['total_value'] or Decimal('0')

        # 3. Calcular el saldo inicial para el período
        # Incluye el stock inicial del archivo base (filtrado por almacén si aplica) más los movimientos pasados
        starting_balance = initial_stock_value + past_movements_value

        # 4. Obtenga movimientos agregados mensuales de los últimos 12 meses (filtered)
        monthly_movements = base_queryset.filter(
            date__gte=start_of_period
        ).annotate(
            month=TruncMonth('date')
        ).values('month').annotate(
            total_entries=Sum('total', filter=Q(quantity__gt=0)),
            total_exits=Sum('total', filter=Q(quantity__lt=0))
        ).order_by('month')

        # 5. Procesar datos y calcular el saldo de cierre de cada mes
        result_data = []
        monthly_data = {
            item['month'].strftime('%Y-%m'): {
                'entries': item['total_entries'] or Decimal('0'),
                'exits': abs(item['total_exits'] or Decimal('0'))
            }
            for item in monthly_movements
        }

        current_balance = starting_balance
        for i in range(12):
            current_month_date = (twelve_months_ago + relativedelta(months=i))
            month_key = current_month_date.strftime('%Y-%m')

            month_data = monthly_data.get(month_key, {'entries': Decimal('0'), 'exits': Decimal('0')})

            entries = month_data['entries']
            exits = month_data['exits']

            current_balance += entries - exits

            result_data.append({
                'month': month_key,
                'total_entries': float(entries),
                'total_exits': float(exits),
                'closing_balance': float(current_balance)
            })

        return JsonResponse(result_data, safe=False)

    except Exception as e:
        logger.error(f"Error in get_monthly_movements: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


@require_http_methods(["GET"])
def get_product_analysis(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    category_filter = request.GET.get('category', '')
    warehouse_filter = request.GET.get('warehouse', '')
    rotation_filter = request.GET.get('rotation', '')
    stagnant_filter = request.GET.get('stagnant', '')
    high_rotation_filter = request.GET.get('high_rotation', '')
    date_from = request.GET.get('date_from', '')
    date_to = request.GET.get('date_to', '')
    search_filter = request.GET.get('search', '')
    limit = request.GET.get('limit', '')

    try:
        # Base product query with filters
        products_query = Product.objects.filter(inventory_name=inventory_name)

        # Apply limit if specified (for exports)
        if limit:
            try:
                limit_int = int(limit)
                products_query = products_query[:limit_int]
            except ValueError:
                pass  # Ignore invalid limit

        if category_filter:
            products_query = products_query.filter(group__icontains=category_filter)

        # Apply warehouse filter at product level using WarehouseDetail
        if warehouse_filter:
            products_query = products_query.filter(
                warehousedetail__warehouse__icontains=warehouse_filter
            ).distinct()

        # Get product IDs for bulk queries
        product_ids = list(products_query.values_list('id', flat=True))
        if not product_ids:
            return JsonResponse([], safe=False)

        # BULK QUERY 1: Get last records for all products per warehouse (for current stock calculation)
        # Note: Warehouse filter is NOT applied here because current stock is total across all warehouses
        # Date filters are not applied to current stock calculation to always get the latest stock

        # Get latest record per product per warehouse by date, not by id
        last_records_per_warehouse = InventoryRecord.objects.filter(
            id__in=InventoryRecord.objects.values('product_id', 'warehouse').annotate(
                latest_id=Subquery(
                    InventoryRecord.objects.filter(
                        product_id=OuterRef('product_id'),
                        warehouse=OuterRef('warehouse')
                    ).order_by('-date').values('id')[:1]
                )
            ).values('latest_id')
        ).select_related('product')

        # Group by product
        last_records_dict = {}
        for record in last_records_per_warehouse:
            product_id = record.product_id
            if product_id not in last_records_dict:
                last_records_dict[product_id] = []
            last_records_dict[product_id].append(record)

        # BULK QUERY 2: Get pre-year sums for all products
        pre_year_sums = InventoryRecord.objects.filter(
            product_id__in=product_ids,
            date__year__lt=datetime.now().year
        ).values('product_id').annotate(
            total_quantity=Sum('quantity')
        )

        pre_year_dict = {item['product_id']: item['total_quantity'] or Decimal('0')
                        for item in pre_year_sums}

        # BULK QUERY 3: Get monthly movements for current year for all products
        monthly_movements = InventoryRecord.objects.filter(
            product_id__in=product_ids,
            date__year=datetime.now().year
        ).annotate(month=TruncMonth('date')).values('product_id', 'month').annotate(
            monthly_total=Sum('quantity')
        ).order_by('product_id', 'month')

        # Group monthly movements by product
        monthly_dict = {}
        for movement in monthly_movements:
            product_id = movement['product_id']
            if product_id not in monthly_dict:
                monthly_dict[product_id] = {}
            monthly_dict[product_id][movement['month'].month] = movement['monthly_total']

        # BULK QUERY 4: Get warehouses for all products
        warehouse_details = WarehouseDetail.objects.filter(
            product_id__in=product_ids
        ).values('product_id').annotate(
            warehouses=GroupConcat('warehouse', delimiter=', ', distinct=True)
        )

        warehouses_dict = {item['product_id']: item['warehouses'] or 'Todos'
                          for item in warehouse_details}

        # BULK QUERY 5: Get warehouse details for current stock calculation
        warehouse_detail_records = WarehouseDetail.objects.filter(
            product_id__in=product_ids
        ).select_related('product')

        warehouse_detail_dict = {}
        for wd in warehouse_detail_records:
            product_id = wd.product_id
            if product_id not in warehouse_detail_dict:
                warehouse_detail_dict[product_id] = {}
            warehouse_detail_dict[product_id][wd.warehouse] = wd

        # Process all products in memory
        analysis_data = []
        current_year = datetime.now().year

        for product in products_query:
            try:
                # Get current stock and cost from last records per warehouse or initial values
                last_records = last_records_dict.get(product.id, [])
                warehouse_details = warehouse_detail_dict.get(product.id, {})

                # Calculate current stock as initial balance + sum of all quantity movements
                total_movements = InventoryRecord.objects.filter(product=product).aggregate(
                    total_quantity=Sum('quantity')
                )['total_quantity'] or Decimal('0')
                current_stock = Decimal(product.initial_balance or 0) + total_movements

                # Get unit cost from the most recent record with non-zero unit_cost across warehouses
                if last_records:
                    recent_records_with_cost = [r for r in last_records if r.unit_cost and r.unit_cost > 0]
                    if recent_records_with_cost:
                        most_recent_with_cost = max(recent_records_with_cost, key=lambda r: r.date)
                        current_unit_cost = Decimal(most_recent_with_cost.unit_cost)
                    else:
                        current_unit_cost = Decimal(product.initial_unit_cost or 0)
                else:
                    current_unit_cost = Decimal(product.initial_unit_cost or 0)

                # Producto consumido
                is_consumed = (current_stock <= 0)

                # ------------------------------------------#
                #        ROTACIÓN / ESTANCAMIENTO
                # ------------------------------------------#
                pre_year_sum = pre_year_dict.get(product.id, Decimal('0'))
                balance_pre_year = Decimal(product.initial_balance or 0) + pre_year_sum

                movements_by_month = monthly_dict.get(product.id, {})

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

                # Apply filters
                if rotation_filter and rotation != rotation_filter:
                    continue
                if stagnant_filter:
                    if stagnant_filter == 'Sí' and not is_stagnant:
                        continue
                    elif stagnant_filter == 'No' and is_stagnant:
                        continue
                if high_rotation_filter:
                    if high_rotation_filter == 'Sí' and high_rotation != 'Sí':
                        continue
                    elif high_rotation_filter == 'No' and high_rotation == 'Sí':
                        continue
                if search_filter:
                    search_lower = search_filter.lower()
                    if not (search_lower in product.code.lower() or search_lower in product.description.lower()):
                        continue

                # Get warehouses for this product
                product_warehouses = warehouses_dict.get(product.id, 'Todos')

                analysis_data.append({
                    'codigo': product.code,
                    'nombre_producto': product.description,
                    'grupo': product.group,
                    'cantidad_saldo_actual': float(current_stock),
                    'valor_saldo_actual': float(current_stock * current_unit_cost),
                    'costo_unitario': float(current_unit_cost),
                    'consumed': 'Sí' if is_consumed else 'No',
                    'estancado': 'Sí' if is_stagnant else 'No',
                    'rotacion': rotation,
                    'alta_rotacion': high_rotation,
                    'almacen': product_warehouses,
                })

            except Exception as e:
                logger.error(f"Error processing product {product.code}: {str(e)}", exc_info=True)
                continue

        return JsonResponse(analysis_data, safe=False)

    except Exception as e:
        logger.error(f"Error in product analysis: {str(e)}", exc_info=True)
        return JsonResponse([], safe=False)



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
        search (str): Search by product code or description

    Returns:
        JsonResponse: List of inventory records or empty list on error
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    date_from = request.GET.get('date_from', '')
    date_to = request.GET.get('date_to', '')
    search_filter = request.GET.get('search', '')

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
        if search_filter:
            records_query = records_query.filter(
                Q(product__code__icontains=search_filter) | Q(product__description__icontains=search_filter)
            )

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
def export_analysis(request, inventory_name='default'):
    """
    Exports product analysis data.

    Args:
        request: Django HttpRequest
        inventory_name (str): Inventory name

    Returns:
        HttpResponse: File response
    """
    try:
        # Get format from query params
        format_type = request.GET.get('format', 'excel')

        # Get analysis data (no limit for complete export)
        analysis_response = get_product_analysis(request)
        analysis_data = analysis_response.content
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
                headers = ['Código', 'Producto', 'Grupo', 'Cantidad Actual', 'Valor Actual', 'Costo Unitario', 'Consumido', 'Estancado', 'Rotación', 'Alta Rotación', 'Almacén']
                formatted_data = []
                for item in analysis_list:
                    formatted_item = [
                        str(item['codigo']),
                        str(item['nombre_producto'])[:30] + '...' if len(str(item['nombre_producto'])) > 30 else str(item['nombre_producto']),
                        str(item['grupo']),
                        f"{item['cantidad_saldo_actual']:,.2f}",
                        f"${item['valor_saldo_actual']:,.2f}",
                        f"${item['costo_unitario']:,.2f}",
                        str(item['consumed']),
                        str(item['estancado']),
                        str(item['rotacion']),
                        str(item['alta_rotacion']),
                        str(item['almacen'])[:15] + '...' if len(str(item['almacen'])) > 15 else str(item['almacen']),
                    ]
                    formatted_data.append(formatted_item)
                data = [headers] + formatted_data

                # Define column widths to fit A4 page (total ~267 points)
                colWidths = [18, 35, 22, 28, 28, 28, 18, 18, 22, 22, 28]

                # Create table with column widths
                table = Table(data, colWidths=colWidths, repeatRows=1)  # Repeat headers on each page
                style = TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('ALIGN', (3, 1), (5, -1), 'RIGHT'),  # Right align numeric columns
                    ('FONTNAME', (0, 0), (-1, 0), 'Times-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 10),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 8),
                    ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
                    ('FONTNAME', (0, 1), (-1, -1), 'Times-Roman'),
                    ('FONTSIZE', (0, 1), (-1, -1), 8),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.black),
                    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
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
def export_movements(request, inventory_name='default'):
    """
    Exports inventory movements data.

    Args:
        request: Django HttpRequest
        inventory_name (str): Inventory name

    Returns:
        HttpResponse: File response
    """
    try:
        # Get format from query params
        format_type = request.GET.get('format', 'excel')

        # Get movements data using the same filtering as get_records
        inventory_name_param = request.GET.get('inventory_name', inventory_name)
        warehouse_filter = request.GET.get('warehouse', '')
        category_filter = request.GET.get('category', '')
        date_from = request.GET.get('date_from', '')
        date_to = request.GET.get('date_to', '')
        search_filter = request.GET.get('search', '')

        records_query = InventoryRecord.objects.filter(product__inventory_name=inventory_name_param).select_related('product', 'batch')

        # Apply filters
        if warehouse_filter:
            records_query = records_query.filter(warehouse__icontains=warehouse_filter)
        if category_filter:
            records_query = records_query.filter(category__icontains=category_filter)
        if date_from:
            records_query = records_query.filter(date__gte=date_from)
        if date_to:
            records_query = records_query.filter(date__lte=date_to)
        if search_filter:
            records_query = records_query.filter(
                Q(product__code__icontains=search_filter) | Q(product__description__icontains=search_filter)
            )

        # Limit records for performance - export up to 5000 records
        records = records_query.order_by('-date')[:5000]
        movements_data = [{
            'fecha': r.date.isoformat(),
            'codigo': r.product.code,
            'nombre_producto': r.product.description,
            'almacen': r.warehouse,
            'tipo_documento': r.document_type,
            'documento': r.document_number,
            'cantidad': float(r.quantity),
            'costo_unitario': float(r.unit_cost),
            'costo_total': float(r.total),
            'categoria': r.category,
        } for r in records]

        if format_type == 'excel':
            # Cracion archivo excel
            df = pd.DataFrame(movements_data)
            response = HttpResponse(content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            response['Content-Disposition'] = f'attachment; filename="movimientos_inventario_{inventory_name_param}.xlsx"'
            df.to_excel(response, index=False)
            return response
        elif format_type == 'pdf':
            # creacion archivo pdf
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
                alignment=1,  # alineacion hacia el centro 
            )
            title = Paragraph(f"Movimientos de Inventario - {inventory_name_param}", title_style)
            elements.append(title)
            elements.append(Spacer(1, 12))

            # Prepare data for table
            if movements_data:
                headers = ['Fecha', 'Código', 'Producto', 'Almacén', 'Tipo Doc.', 'Documento', 'Cantidad', 'Costo Unit.', 'Total', 'Categoría']
                formatted_data = []
                for item in movements_data:
                    formatted_item = [
                        item['fecha'],
                        str(item['codigo']),
                        str(item['nombre_producto'])[:25] + '...' if len(str(item['nombre_producto'])) > 25 else str(item['nombre_producto']),
                        str(item['almacen']),
                        str(item['tipo_documento'] or ''),
                        str(item['documento'] or ''),
                        f"{item['cantidad']:,.2f}",
                        f"${item['costo_unitario']:,.2f}",
                        f"${item['costo_total']:,.2f}",
                        str(item['categoria']),
                    ]
                    formatted_data.append(formatted_item)
                data = [headers] + formatted_data

                # Define column widths to fit A4 page (total ~350 points)
                colWidths = [35, 30, 50, 30, 25, 30, 30, 35, 35, 30]

                # Create table with column widths
                table = Table(data, colWidths=colWidths, repeatRows=1)  # Repeat headers on each page
                style = TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.darkblue),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('ALIGN', (6, 1), (8, -1), 'RIGHT'),  # Right align numeric columns (Cantidad, Costo Unit., Total)
                    ('FONTNAME', (0, 0), (-1, 0), 'Times-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 6),
                    ('TOPPADDING', (0, 0), (-1, 0), 6),
                    ('BACKGROUND', (0, 1), (-1, -1), colors.lightgrey),
                    ('FONTNAME', (0, 1), (-1, -1), 'Times-Roman'),
                    ('FONTSIZE', (0, 1), (-1, -1), 7),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.black),
                    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                    ('LEFTPADDING', (0, 0), (-1, -1), 2),
                    ('RIGHTPADDING', (0, 0), (-1, -1), 2),
                ])
                # Alternate row colors
                for i in range(1, len(data)):
                    if i % 2 == 0:
                        style.add('BACKGROUND', (0, i), (-1, i), colors.whitesmoke)
                    else:
                        style.add('BACKGROUND', (0, i), (-1, i), colors.white)
                table.setStyle(style)
                elements.append(table)

            doc.build(elements)
            buffer.seek(0)

            response = HttpResponse(buffer.getvalue(), content_type='application/pdf')
            response['Content-Disposition'] = f'attachment; filename="movimientos_inventario_{inventory_name_param}.pdf"'
            return response
        else:
            return JsonResponse({'error': 'Formato no soportado'}, status=400)
    except Exception as e:
        logger.error(f"Error exporting movements: {str(e)}", exc_info=True)
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


from django.db.models import Max

@require_http_methods(["GET"])
def get_last_update_time(request):
    """
    Retrieves the timestamp of the last inventory update.
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    try:
        last_batch = ImportBatch.objects.filter(
            inventory_name=inventory_name,
            processed_at__isnull=False
        ).order_by('-processed_at').first()

        if last_batch:
            return JsonResponse({'last_update': last_batch.processed_at.isoformat()})
        else:
            return JsonResponse({'last_update': None})
    except Exception as e:
        logger.error(f"Error retrieving last update time: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


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
    return JsonResponse({'message': 'Bienvenido a el sistema de analisis de inventarios'})