import logging
import io
import re
from decimal import Decimal
from datetime import datetime

import pandas as pd
from django.http import JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.db import transaction
from django.utils import timezone
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
    #Manejo de error en caso de que el usuario no envie el .xlsx
    try:
        inventory_name = str(inventory_name).strip().lower() or 'default'

        # Validate request - base file is required for initial setup, update file for subsequent updates
        base_file = request.FILES.get('base_file')
        base_content = b''
        if base_file:
            base_content = base_file.read()

        update_files = request.FILES.getlist('update_files')
        update_content = b''
        for update_file in update_files:
            update_content += update_file.read()

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

            # Leemos el archivo de actualización con nombres de columnas específicos
            update_df = None
            if update_file is not None:
                update_df = pd.read_excel(
                    io.BytesIO(update_content),
                    header=3,  # Row 4 contains headers (index 3)
                    usecols=[0, 2, 3, 4, 13, 14, 17, 18, 19, 20, 21],  # A, C, D, E, N, O, R, S, T, U, V
                    names=[
                        'item', 'desc_item', 'localizacion', 'categoria',
                        'fecha', 'documento', 'entradas', 'salidas', 'unitario', 'total', 'cantidad'
                    ],
                    dtype={
                        'item': str, 'desc_item': str, 'localizacion': str, 'categoria': str,
                        'fecha': str, 'documento': str, 'entradas': float, 'salidas': float,
                        'unitario': float, 'total': float
                    }
                )

                logger.info(f"Update DF shape: {update_df.shape}")
                logger.info(f"Update DF columns: {list(update_df.columns)}")
                logger.info(f"Update DF head: \n{update_df.head().to_string()}")

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
        if update_files:
            for update_file in update_files:
                update_content = update_file.read()
                update_df = pd.read_excel(
                    io.BytesIO(update_content),
                    header=3,  # Row 4 contains headers (index 3)
                    usecols=[0, 2, 3, 4, 13, 14, 17, 18, 19, 20, 21],  # A, C, D, E, N, O, R, S, T, U, V
                    names=[
                        'item', 'desc_item', 'localizacion', 'categoria',
                        'fecha', 'documento', 'entradas', 'salidas', 'unitario', 'total', 'cantidad'
                    ],
                    dtype={
                        'item': str, 'desc_item': str, 'localizacion': str, 'categoria': str,
                        'fecha': str, 'documento': str, 'entradas': float, 'salidas': float,
                        'unitario': float, 'total': float
                    }
                )

                logger.info(f"Update DF shape: {update_df.shape}")
                logger.info(f"Update DF columns: {list(update_df.columns)}")
                logger.info(f"Update DF head: \n{update_df.head().to_string()}")

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

    # El costo unitario ya es el último del archivo base, no necesitamos calcular promedio
    df_grouped['costo_unitario_promedio'] = df_grouped['costo_unitario']

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
            cantidad_total = float(row.get('cantidad', 0)) or 0
            costo_unitario_promedio = float(row.get('costo_unitario_promedio', 0)) or 0
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
                initial_unit_cost=costo_unitario_promedio
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
                final_quantity = float(row.get('cantidad', 0)) if pd.notna(row.get('cantidad')) else 0

                # Para calcular el movimiento neto, necesitamos el saldo anterior
                # Pero como no tenemos el saldo anterior aquí, calculamos el movimiento basado en entradas y salidas
                entradas = float(row.get('entradas', 0)) if pd.notna(row.get('entradas')) else 0
                salidas = float(row.get('salidas', 0)) if pd.notna(row.get('salidas')) else 0
                quantity = entradas - salidas

                if quantity == 0:
                    logger.info(f"Skipping row {idx}: quantity is 0 (entradas={entradas}, salidas={salidas})")
                    continue  # Saltamos registros sin movimiento

                # Traemos costos y totales
                unit_cost = float(row.get('unitario', 0)) if pd.notna(row.get('unitario')) else 0
                total = float(row.get('total', 0)) if pd.notna(row.get('total')) else (abs(quantity) * unit_cost)

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
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    date_from = request.GET.get('date_from', '')
    date_to = request.GET.get('date_to', '')

    try:
        # Base query with filters
        products_query = Product.objects.filter(inventory_name=inventory_name)

        # Apply category filter if provided
        if category_filter:
            products_query = products_query.filter(group__icontains=category_filter)

        # ANOTAMOS LOS CAMPOS NECESARIOS
        products = products_query.annotate(
            # CALCULAR STOCK ACTUAL: TOMAR EL ÚLTIMO REGISTRO DEL CAMPO CANTIDAD
            # PERO PARA SALIDAS CON MISMO DOCUMENTO Y FECHA, TOMAR LA CANTIDAD MÍNIMA
            current_stock=Coalesce(
                Subquery(
                    # Para salidas (quantity < 0) con mismo documento y fecha, tomar el mínimo
                    InventoryRecord.objects.filter(
                        product=OuterRef('pk'),
                        quantity__lt=0
                    ).exclude(
                        document_type__isnull=True
                    ).exclude(
                        document_number__isnull=True
                    ).values('document_type', 'document_number', 'date').annotate(
                        min_quantity=Min('final_quantity')
                    ).order_by('-date', 'document_type', 'document_number').values('min_quantity')[:1],
                    output_field=DecimalField()
                ),
                # Si no hay salidas agrupadas, tomar el último registro general
                Subquery(
                    InventoryRecord.objects.filter(
                        product=OuterRef('pk')
                    ).order_by('-date', '-id').values('final_quantity')[:1],
                    output_field=DecimalField()
                ),
                F('initial_balance'),
                output_field=DecimalField()
            ),
            # OBTENER EL ÚLTIMO COSTO UNITARIO
            latest_unit_cost=Subquery(
                InventoryRecord.objects.filter(
                    product=OuterRef('pk')
                ).order_by('-date', '-id').values('unit_cost')[:1],
                output_field=DecimalField()
            )
        ).annotate(
            # COSTO PROMEDIO: ÚLTIMO COSTO O COSTO INICIAL
            avg_cost=Case(
                When(latest_unit_cost__isnull=False, then=F('latest_unit_cost')),
                default=F('initial_unit_cost'),
                output_field=DecimalField()
            )
        ).filter(
            # INCLUIMOS TODOS LOS PRODUCTOS DEL INVENTARIO, INDEPENDIENTEMENTE DEL STOCK
            Q(initial_balance__gt=0) | Q(current_stock__isnull=False) | Q(current_stock__gte=0)
        )
    except Exception as e:
        logger.error(f"Error in product analysis query: {str(e)}", exc_info=True)
        # Return empty list if query fails
        return JsonResponse([], safe=False)

    analysis_data = []
    current_year = datetime.now().year

    for p in products:
        try:
            # --- ANALISIS DE ROTACION ---
            # BALANCE DESDE INICIO DE AÑO
            balance_pre_year = p.initial_balance + Coalesce(
                InventoryRecord.objects.filter(product=p, date__year__lt=current_year).aggregate(s=Sum('quantity'))['s'],
                Decimal('0')
            )

            # MOVIMIENTOS MENSUALES DEL AÑO ACTUAL - limit query for performance
            monthly_movements = InventoryRecord.objects.filter(
                product=p, date__year=current_year
            ).annotate(
                month=TruncMonth('date')
            ).values('month').annotate(

                monthly_total=Sum('quantity')
            ).order_by('month')

            movements_by_month = {m['month'].month: m['monthly_total'] for m in monthly_movements}

            # CALCULAR FIN DE MES PARA CADA MES
            monthly_balances = []
            running_balance = balance_pre_year
            for i in range(1, 13):
                running_balance += movements_by_month.get(i, Decimal('0'))
                monthly_balances.append(running_balance)

            # ROTACION Y ESTANCAMIENTO
            all_zero_balance = all(b == Decimal('0') for b in monthly_balances)
            unique_balances_all_year = set(monthly_balances)
            is_stagnant_all_year = len(unique_balances_all_year) == 1 and monthly_balances[0] > 0

            rotation = 'Activo'
            if is_stagnant_all_year:
                rotation = 'Obsoleto'
            elif any(monthly_balances[i] != monthly_balances[i+1] for i in range(len(monthly_balances)-1)) or all_zero_balance:
                rotation = 'Activo'
            elif len(monthly_balances) >= 3:
                last_3_balances = set(monthly_balances[-3:])
                if len(last_3_balances) == 1 and monthly_balances[-1] > 0:
                    rotation = 'Estancado'

            # ALTA ROTACION: "Sí" si ha tenido cambios en al menos 2 meses consecutivos
            consecutive_changes = 0
            for i in range(len(monthly_balances) - 1):
                if monthly_balances[i] != monthly_balances[i+1]:
                    consecutive_changes += 1

            high_rotation = 'Sí' if consecutive_changes >= 2 else 'No'

            analysis_data.append({
                'codigo': p.code,
                'nombre_producto': p.description,
                'grupo': p.group,
                'cantidad_saldo_actual': float(p.current_stock),
                'valor_saldo_actual': float(p.current_stock * p.avg_cost),
                'costo_unitario': float(p.avg_cost),
                'estancado': 'Sí' if is_stagnant_all_year else 'No',
                'rotacion': rotation,
                'alta_rotacion': high_rotation,
                'almacen': '',  # Add empty almacen field for frontend compatibility
            })
        except Exception as e:
            logger.error(f"Error processing product {p.code}: {str(e)}", exc_info=True)
            # Skip this product and continue with others
            continue

    return JsonResponse(analysis_data, safe=False)

@require_http_methods(["GET"])
def get_batches(request):
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

        # Agregar campos adicionales para compatibilidad con el frontend
        for record in records_data:
            record.update({
                'item': record['product_code'],
                'desc_item': record['product_description'],
                'localizacion': record['warehouse'],
                'categoria': record['category'],
                'documento': f"{record['document_type'] or ''}{record['document_number'] or ''}",
                'entradas': record['quantity'] if record['quantity'] > 0 else 0,
                'salidas': abs(record['quantity']) if record['quantity'] < 0 else 0,
                'unitario': record['unit_cost'],
            })

        return JsonResponse(records_data, safe=False)
    except Exception as e:
        logger.error(f"Error in records query: {str(e)}", exc_info=True)
        # Return empty list if query fails
        return JsonResponse([], safe=False)

@require_http_methods(["GET"])
def get_product_history(request, product_code, inventory_name='default'):
    history = InventoryRecord.objects.filter(
        product__code=product_code,
        product__inventory_name=inventory_name
    ).order_by('date')
    
    history_data = [{
        'date': r.date.isoformat(),
        'document_type': r.document_type,
        'document_number': r.document_number,
        'quantity': float(r.quantity),
        'unit_cost': float(r.unit_cost),
        'total': float(r.total),
        'warehouse': r.warehouse,
        'category': r.category,
    } for r in history]
    return JsonResponse(history_data, safe=False)

@require_http_methods(["POST"])
@csrf_exempt
def create_inventory(request):
    # Esta función se utiliza para crear un nuevo inventario.
    # sin embargo, en esta implementación solo usamos un inventario por defecto.
    return JsonResponse({'ok': True, 'message': 'La creación de inventario no está totalmente implementada; se utiliza la configuración predeterminada.'})

@require_http_methods(["GET"])
def get_summary(request):
    inventory_name = request.GET.get('inventory_name', 'default')

    try:
        total_products = Product.objects.filter(inventory_name=inventory_name).count()
        total_records = InventoryRecord.objects.filter(product__inventory_name=inventory_name).count()

        # Usa annotate para obtener estadísticas por categoría y almacén
        category_stats = Product.objects.filter(inventory_name=inventory_name).values('group').annotate(
            count=Sum(1)
        ).order_by('-count').filter(group__isnull=False)

        warehouse_stats = InventoryRecord.objects.filter(product__inventory_name=inventory_name).values('warehouse').annotate(
            count=Sum(1)
        ).order_by('-count').filter(warehouse__isnull=False)

        # Calcula el valor total del inventario usando el último costo unitario por producto
        products_with_value = Product.objects.filter(inventory_name=inventory_name).annotate(
            # OBTENER LA ÚLTIMA CANTIDAD DEL ARCHIVO DE ACTUALIZACIÓN
            final_quantity=Subquery(
                InventoryRecord.objects.filter(
                    product=OuterRef('pk')
                ).order_by('-date', '-id').values('final_quantity')[:1],  # Ordenamos por fecha e id para consistencia
                output_field=DecimalField()
            ),
            # OBTENER EL ÚLTIMO COSTO UNITARIO
            latest_unit_cost=Subquery(
                InventoryRecord.objects.filter(
                    product=OuterRef('pk')
                ).order_by('-date', '-id').values('unit_cost')[:1],
                output_field=DecimalField()
            )
        ).annotate(
            # SE CALCULA EL SALDO FINAL USANDO LA ÚLTIMA CANTIDAD DEL ARCHIVO DE ACTUALIZACIÓN
            final_balance=Case(
                When(final_quantity__isnull=False, then=F('final_quantity')),
                default=F('initial_balance'),
                output_field=DecimalField()
            ),
            # COSTO PROMEDIO: ÚLTIMO COSTO O COSTO INICIAL
            avg_cost=Case(
                When(latest_unit_cost__isnull=False, then=F('latest_unit_cost')),
                default=F('initial_unit_cost'),
                output_field=DecimalField()
            )
        ).filter(
            # INCLUIMOS SOLO PRODUCTOS CON SALDO FINAL > 0 O SALDO INICIAL > 0
            Q(final_quantity__gt=0) | Q(initial_balance__gt=0)
        )
        total_inventory_value = products_with_value.aggregate(
            total_value=Sum(F('final_balance') * F('avg_cost'))
        )['total_value'] or Decimal('0')

        movement_stats = InventoryRecord.objects.filter(product__inventory_name=inventory_name).aggregate(
            total_entradas=Coalesce(Sum('quantity', filter=Q(quantity__gt=0)), Decimal('0')),
            total_salidas=Coalesce(Sum('quantity', filter=Q(quantity__lt=0)), Decimal('0')),
        )

        return JsonResponse({
            'total_productos': total_products,
            'total_registros': total_records,
            'valor_total_inventario': float(total_inventory_value),
            'estadisticas_categoria': list(category_stats),
            'estadisticas_almacen': list(warehouse_stats),
            'estadisticas_movimientos': {
                'entradas': float(movement_stats['total_entradas']),
                'salidas': abs(float(movement_stats['total_salidas'])),
            }
        })
    except Exception as e:
        logger.error(f"Error in summary query: {str(e)}", exc_info=True)
        # Return default values if query fails
        return JsonResponse({
            'total_productos': 0,
            'total_registros': 0,
            'valor_total_inventario': 0.0,
            'estadisticas_categoria': [],
            'estadisticas_almacen': [],
            'estadisticas_movimientos': {
                'entradas': 0.0,
                'salidas': 0.0,
            }
        })


@require_http_methods(["GET"])
def list_inventories(request):
    # simplificado para un solo inventario por defecto
    last_batch = ImportBatch.objects.filter(inventory_name='default').order_by('-started_at').first()
    if not last_batch:
        return JsonResponse([], safe=False)

    inventory_info = {
        'name': 'default',
        'product_count': Product.objects.filter(inventory_name='default').count(),
        'record_count': InventoryRecord.objects.filter(product__inventory_name='default').count(),
        'last_updated': last_batch.processed_at.isoformat() if last_batch.processed_at else last_batch.started_at.isoformat()
    }
    return JsonResponse([inventory_info], safe=False)



@csrf_exempt
@require_http_methods(["POST"])
@transaction.atomic
def upload_base_file(request, inventory_name='default'):

    try:
        if 'base_file' not in request.FILES:
            return JsonResponse(
                {'ok': False, 'error': 'El archivo base es requerido'},
                status=400
            )

        base_file = request.FILES['base_file']
        inventory_name = str(inventory_name).strip().lower() or 'default'

        try:
            base_content = base_file.read()

            # Read the Excel file with specific column mapping
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

            base_df = base_df.dropna(subset=['codigo', 'descripcion'])
            base_df['codigo'] = base_df['codigo'].astype(str).str.strip()
            base_df['descripcion'] = base_df['descripcion'].astype(str).str.strip()

            # Delete existing products and batches for this inventory to allow re-upload
            # First delete inventory records to avoid foreign key constraint
            InventoryRecord.objects.filter(product__inventory_name=inventory_name).delete()
            Product.objects.filter(inventory_name=inventory_name).delete()
            ImportBatch.objects.filter(inventory_name=inventory_name).delete()

            # Create import batch
            batch = ImportBatch.objects.create(
                file_name=base_file.name,
                inventory_name=inventory_name,
                checksum=calculate_file_checksum(base_content)
            )

            # Process the base file
            records_processed = _process_base_file(base_df, inventory_name)

            if records_processed == 0:
                batch.delete()
                return JsonResponse(
                    {'ok': False, 'error': 'No se importaron registros válidos'},
                    status=400
                )

            # Update batch information
            batch.rows_imported = records_processed
            batch.rows_total = len(base_df)
            batch.processed_at = timezone.now()
            batch.save()

            return JsonResponse({
                'ok': True,
                'message': f'Se importaron {records_processed} productos correctamente',
                'batch_id': batch.id
            })

        except Exception as e:
            logger.error(f"Error al procesar el archivo base: {str(e)}", exc_info=True)
            return JsonResponse(
                {'ok': False, 'error': f'Error al procesar el archivo: {str(e)}'},
                status=400
            )

    except Exception as e:
        logger.error(f"Error en upload_base_file: {str(e)}", exc_info=True)
        return JsonResponse(
            {'ok': False, 'error': f'Error en el servidor: {str(e)}'},
            status=500
        )

def export_analysis(request, inventory_name='default', format_type='excel'):
    # Placeholder for export functionality
    return JsonResponse({'ok': False, 'error': f'Export to {format_type} not implemented yet.'}, status=501)
    