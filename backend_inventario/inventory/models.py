from django.db import models

class ImportBatch(models.Model):
    file_name = models.CharField(max_length=255)
    started_at = models.DateTimeField(auto_now_add=True)
    processed_at = models.DateTimeField(null=True, blank=True)
    rows_total = models.IntegerField(default=0)
    rows_imported = models.IntegerField(default=0)
    checksum = models.CharField(max_length=64, null=True, blank=True)  # SHA256 hash of file
    inventory_name = models.CharField(max_length=128, default='default')  # Support multiple inventories

    class Meta:
        unique_together = ['checksum', 'inventory_name']  # Prevent duplicate file imports per inventory

class Product(models.Model):
    code = models.CharField(max_length=64)
    description = models.CharField(max_length=512)
    group = models.CharField(max_length=128, blank=True)
    inventory_name = models.CharField(max_length=128, default='default')
    initial_balance = models.DecimalField(max_digits=15, decimal_places=3, default=0)
    initial_unit_cost = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    class Meta:
        unique_together = ['code', 'inventory_name']  # Same product code can exist in different inventories

class InventoryRecord(models.Model):
    MOVEMENT_TYPES = [
        ('EA', 'Entrada'),
        ('SA', 'Salida'),
        ('GF', 'Entrada'),
    ]

    batch = models.ForeignKey(ImportBatch, on_delete=models.CASCADE)
    product = models.ForeignKey(Product, on_delete=models.PROTECT)
    warehouse = models.CharField(max_length=128)
    date = models.DateField()
    document_type = models.CharField(max_length=4, choices=MOVEMENT_TYPES, null=True, blank=True)
    document_number = models.CharField(max_length=64, null=True, blank=True)
    quantity = models.DecimalField(max_digits=18, decimal_places=3)  # Positive for entries, negative for exits
    unit_cost = models.DecimalField(max_digits=18, decimal_places=2)
    total = models.DecimalField(max_digits=20, decimal_places=2)
    category = models.CharField(max_length=128, blank=True)  # Mapped category
    lote = models.CharField(max_length=64, blank=True)  # Batch/lot tracking
    final_quantity = models.DecimalField(max_digits=18, decimal_places=3, null=True, blank=True)  # Cantidad final después del movimiento
    cost_center = models.CharField(max_length=64, null=True, blank=True)  # Centro de costo

    class Meta:
        unique_together = ['document_type', 'document_number', 'product', 'batch']  # Prevent duplicate documents
        indexes = [
            models.Index(fields=['product', 'date']),
            models.Index(fields=['warehouse', 'date']),
            models.Index(fields=['document_type', 'document_number']),
        ]
