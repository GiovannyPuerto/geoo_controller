"""
Comando de administración: backfill_row_hash
============================================
Calcula y guarda row_hash para todos los InventoryRecord que aún no lo tienen.

Este comando debe ejecutarse una sola vez después de desplegar la versión que
agrega `total` y `lote` al algoritmo de _build_row_hash, para que los registros
históricos queden protegidos por la capa 3 de deduplicación.

Uso:
    python manage.py backfill_row_hash
    python manage.py backfill_row_hash --force   # rehashea TODOS (incluso los que ya tienen hash)
    python manage.py backfill_row_hash --batch-size 2000

El comando puede interrumpirse y reanudarse: sólo procesa las filas sin hash
(a menos que se use --force).
"""

import logging

from django.core.management.base import BaseCommand
from django.db.models import Q

from inventory.models import InventoryRecord
from inventory.services.import_service import _build_row_hash

logger = logging.getLogger(__name__)

DEFAULT_BATCH_SIZE = 1000


class Command(BaseCommand):
    help = 'Backfill row_hash para registros de inventario sin hash calculado'

    def add_arguments(self, parser):
        parser.add_argument(
            '--force',
            action='store_true',
            default=False,
            help='Rehashea TODOS los registros, incluso los que ya tienen row_hash.',
        )
        parser.add_argument(
            '--batch-size',
            type=int,
            default=DEFAULT_BATCH_SIZE,
            dest='batch_size',
            help=f'Registros por lote de actualización (default: {DEFAULT_BATCH_SIZE}).',
        )

    def handle(self, *args, **options):
        force = options['force']
        batch_size = options['batch_size']

        if force:
            qs = InventoryRecord.objects.all()
            self.stdout.write('Modo --force activo: se rehashearán TODOS los registros.')
        else:
            qs = InventoryRecord.objects.filter(
                Q(row_hash__isnull=True) | Q(row_hash='')
            )

        total = qs.count()
        if total == 0:
            self.stdout.write(self.style.SUCCESS('No hay registros que necesiten backfill.'))
            return

        self.stdout.write(f'Registros a procesar: {total:,}')

        updated = 0
        errors = 0
        buffer = []

        fields_needed = (
            'id', 'product_id', 'date', 'document_type', 'document_number',
            'source_document', 'quantity', 'unit_cost',
            'warehouse', 'cost_center', 'lote',
        )

        for rec in qs.only(*fields_needed).iterator(chunk_size=batch_size):
            try:
                new_hash = _build_row_hash(
                    rec.product_id,
                    rec.date,
                    rec.document_type,
                    rec.document_number,
                    rec.source_document,
                    rec.quantity,
                    rec.unit_cost,
                    rec.warehouse,
                    rec.cost_center,
                    lote=rec.lote or '',
                )
                rec.row_hash = new_hash
                buffer.append(rec)
            except Exception as exc:
                errors += 1
                logger.warning(f'Error calculando hash para InventoryRecord id={rec.pk}: {exc}')
                continue

            if len(buffer) >= batch_size:
                InventoryRecord.objects.bulk_update(buffer, ['row_hash'], batch_size=batch_size)
                updated += len(buffer)
                buffer = []
                self.stdout.write(f'  {updated:,} / {total:,} actualizados...')

        # Lote final
        if buffer:
            InventoryRecord.objects.bulk_update(buffer, ['row_hash'], batch_size=batch_size)
            updated += len(buffer)

        msg = f'Backfill completado: {updated:,} registros actualizados.'
        if errors:
            msg += f' Errores omitidos: {errors}.'
            self.stdout.write(self.style.WARNING(msg))
        else:
            self.stdout.write(self.style.SUCCESS(msg))
        logger.info(msg)
