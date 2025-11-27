from datetime import datetime
import re
import hashlib
from decimal import Decimal, InvalidOperation
import pandas as pd

LOCALIZACION_MAP = {
    '102-05': 'FINCA SALITRE',
    '102-10': 'CONSTRUCCIONES Y EDIFICIOS',
    '103-05': 'FINCA SAN NICOLAS'
}

CATEGORIA_MAP = {
    '1': 'AGROQUIMICOS-FERTILIZANTES Y ABONOS',
    '2': 'MATERIAL DE EMPAQUE',
    '3': 'MANTENIMIENTO',
    '4': 'PAPELERIA Y ASEO',
    '5': 'DOTACION Y SEGURIDAD'
}

def clean_number(s):
    """
    limpiamos y convertimos a Decimal una cadena que puede tener diferentes formatos
    incluyendo notacion cientifica, simbolos de moneda, comas y puntos como separadores
    """
    if not s or str(s).strip() in ('', 'nan', 'NaN', 'None'):
        return Decimal('0.0')

    s = str(s).strip()

    # Notacion cientifica
    if 'E' in s or 'e' in s:
        try:
            return Decimal(str(float(s)))
        except (ValueError, InvalidOperation):
            return Decimal('0.0')

    # removemos simbolos de moneda y espacios
    s = re.sub(r'[^\d.,\-]', '', s)

    #casos con comas y puntos
    if s.count(',') == 1 and s.count('.') > 1:
        # Removemos puntos y reemplazamos la coma por punto
        s = s.replace('.', '').replace(',', '.')
    elif s.count(',') > 1:
        # Multiples comas, asumimos que la ultima es el separador decimal
        parts = s.split(',')
        if len(parts) > 1:
            s = ''.join(parts[:-1]) + '.' + parts[-1]
    else:
        # en otro caso, simplemente reemplazamos comas por puntos
        s = s.replace(',', '.')

    try:
        return Decimal(s)
    except (ValueError, InvalidOperation):
        return Decimal('0.0')

def parse_date(value):
    """
    fecha en varios formatos a objeto date
    20230131, 31/01/2023, 01/31/2023, etc.
    """
    if not value or str(value).strip() in ('', 'nan', 'NaN', 'None'):
        return None

    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, pd.Timestamp):
        return value.date()

    s = str(value).strip()

    # Handle scientific notation
    if 'E' in s or 'e' in s:
        try:
            num = int(float(s))
            s = str(num)
        except (ValueError, TypeError):
            return None

    # Handle YYYYMMDD format
    if re.match(r'^\d{8}$', s):
        try:
            return datetime.strptime(s, '%Y%m%d').date()
        except ValueError:
            return None

    # Handle other formats if needed (DD/MM/YYYY, MM/DD/YYYY, etc.)
    try:
        return pd.to_datetime(s).date()
    except (ValueError, TypeError):
        return None

def parse_document(value):
    """
    Extraemos el tipo y numero de documento de una cadena
    Ejemplos:   
    SA12345
    EA67890
    """
    if not value:
        return None, None

    s = str(value).upper().strip()

    # Observe el patron: SA 12345 o EA 67890
    m = re.search(r'\b(SA|EA)\b\D*?(\d+)', s)
    if m:
        return m.group(1), m.group(2)

    # Alternativa de solo SA12345 o EA67890
    m = re.search(r'(SA|EA)(\d+)', s)
    if m:
        return m.group(1), m.group(2)

    return None, None

def map_localizacion(code):
    """
    mapa de codigos de localizacion a nombres legibles.
    """
    if not code:
        return ''
    return LOCALIZACION_MAP.get(str(code).strip(), str(code).strip())

def map_categoria(code):
    """
    Map category codes to readable names.
    """
    if not code:
        return ''
    code_str = str(code).strip().upper()

    # First check if it's already a standard name
    for k, v in CATEGORIA_MAP.items():
        if code_str == v:
            return v

    # Then check if it's a code
    if code_str in CATEGORIA_MAP:
        return CATEGORIA_MAP[code_str]

    # Then check if it contains keywords
    if 'AGROQUIMICOS' in code_str or 'FERTILIZANTES' in code_str or 'ABONOS' in code_str:
        return 'AGROQUIMICOS-FERTILIZANTES Y ABONOS'
    if 'DOTACION' in code_str or 'SEGURIDAD' in code_str:
        return 'DOTACION Y SEGURIDAD'
    if 'MANTENIMIENTO' in code_str:
        return 'MANTENIMIENTO'
    if 'EMPAQUE' in code_str or 'MATERIAL' in code_str:
        return 'MATERIAL DE EMPAQUE'
    if 'PAPELERIA' in code_str or 'ASEO' in code_str:
        return 'PAPELERIA Y ASEO'

    # Otherwise return the original
    return str(code).strip()

def calculate_file_checksum(file_content):
    """
    Calculate SHA256 checksum of file content.
    """
    return hashlib.sha256(file_content).hexdigest()

def validate_row_data(row_data, format_type='movements'):
    """
    Validate row data based on format type.
    Returns (is_valid, error_message)
    """
    if format_type == 'base':
        required_fields = ['CODIGO', 'DESCRIPCION CODIGO', 'SALDO_INICIAL', 'COSTO_UNITARIO']
    elif format_type == 'movements':
        required_fields = ['CODIGO', 'MOVIMIENTO', 'FECHA']
        if not row_data.get('SALIDA') and not row_data.get('ENTRADA'):
            return False, "Falta SALIDA o ENTRADA"
        if not row_data.get('UNITARIO') and not row_data.get('TOTAL'):
            return False, "Falta UNITARIO o TOTAL"
    else: # detailed
        required_fields = ['ITEM', 'FECHA', 'LOCALIZACION']
        if not row_data.get('CANTIDAD') and not (row_data.get('ENTRADA') or row_data.get('SALIDA')):
            return False, "Falta CANTIDAD, ENTRADA o SALIDA"
        if not row_data.get('UNITARIO') and not row_data.get('UNITARI') and not row_data.get('TOTAL'):
            return False, "Falta UNITARIO o TOTAL"

    for field in required_fields:
        if field not in row_data or not row_data[field]:
            return False, f"Falta {field}"

    # Validate amounts
    salida = clean_number(row_data.get('SALIDA', '0'))
    entrada = clean_number(row_data.get('ENTRADA', '0'))
    cantidad = clean_number(row_data.get('CANTIDAD', '0'))
    saldo_inicial = clean_number(row_data.get('SALDO_INICIAL', '0'))
    unitario = clean_number(row_data.get('UNITARIO', '0') or row_data.get('UNITARI', '0') or row_data.get('COSTO_UNITARIO', '0'))
    total = clean_number(row_data.get('TOTAL', '0') or row_data.get('VALOR_TOTAL', '0'))

    if format_type == 'base':
        quantity = saldo_inicial
    else:
        quantity = cantidad if cantidad != 0 else entrada - salida

    if quantity == 0:
        return False, "La cantidad no puede ser cero"

    if unitario < 0:
        return False, "Costo unitario no puede ser negativo"

    # Validate total
    if total != 0 and unitario != 0 and abs(total - (abs(quantity) * unitario)) > 0.1:
        return False, f"El total no coincide con la cantidad y el costo unitario (Total: {total}, Calculado: {abs(quantity) * unitario})"

    return True, ""

def clean_text(value):
    """
    Clean and normalize text fields.
    """
    if not value:
        return ''
    return ' '.join(str(value).split()).upper()

def detect_excel_format(df):
    """
    Detectar el formato del archivo excel basado en las columnas presentes.
    """
    if 'SALDO_INICIAL' in df.columns:
        return 'base'
    elif any(col in df.columns for col in ['MOVIMIENTO', 'SALIDA', 'ENTRADA']):
        return 'movements'
    else:
        return 'detailed'