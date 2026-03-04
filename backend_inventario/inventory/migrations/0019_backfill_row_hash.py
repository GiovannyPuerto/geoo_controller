"""
Backfill row_hash para registros existentes con row_hash = NULL.

row_hash es el SHA-256 (32 hex chars) del contenido del movimiento:
  product_id | date | doc_type | doc_number | source_document |
  quantity | unit_cost | warehouse | cost_center | lote

Este campo fue añadido en migración 0018 como nullable (sin poblar).
Esta migración lo rellena para todos los registros antiguos, activando
la 3ª capa de deduplicación en el servicio de importación.
"""

import hashlib
from decimal import Decimal
from django.db import migrations


def _norm_sig(value):
    """Mismo algoritmo que _normalize_signature_value en import_service.py."""
    if value is None:
        return ''
    if isinstance(value, Decimal):
        if value == 0:
            return '0'
        return format(value.normalize(), 'f')
    raw = str(value).strip()
    if raw.lower() in ('nan', 'none', 'nat'):
        return ''
    return raw


def _norm_case(value):
    """Normaliza y aplica casefold (para strings de documento/almacén)."""
    n = _norm_sig(value)
    return n.casefold()


def _compute_row_hash(rec):
    """
    Mismo algoritmo que _build_row_hash en import_service.py.
    NOTA: no modificar este algoritmo sin actualizar también _build_row_hash.
    """
    parts = [
        str(rec.product_id),
        str(rec.date),
        _norm_case(rec.document_type),
        _norm_case(rec.document_number),
        _norm_case(rec.source_document),
        _norm_sig(rec.quantity),    # Decimal: no casefold
        _norm_sig(rec.unit_cost),   # Decimal: no casefold
        _norm_case(rec.warehouse),
        _norm_case(rec.cost_center),
        _norm_case(rec.lote),
    ]
    return hashlib.sha256('|'.join(parts).encode('utf-8')).hexdigest()[:32]


def forward_backfill_row_hash(apps, schema_editor):
    InventoryRecord = apps.get_model('inventory', 'InventoryRecord')

    batch_size = 2000
    batch = []

    for rec in (
        InventoryRecord.objects
        .filter(row_hash__isnull=True)
        .iterator(chunk_size=batch_size)
    ):
        rec.row_hash = _compute_row_hash(rec)
        batch.append(rec)

        if len(batch) >= batch_size:
            InventoryRecord.objects.bulk_update(batch, ['row_hash'])
            batch = []

    if batch:
        InventoryRecord.objects.bulk_update(batch, ['row_hash'])


def backward_clear_row_hash(apps, schema_editor):
    InventoryRecord = apps.get_model('inventory', 'InventoryRecord')
    InventoryRecord.objects.all().update(row_hash=None)


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0018_inventoryrecord_row_hash'),
    ]

    operations = [
        migrations.RunPython(forward_backfill_row_hash, backward_clear_row_hash),
    ]
