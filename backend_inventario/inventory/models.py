from django.db import models


class ImportBatch(models.Model):
    """
    Representa un archivo importado (base o actualización).
    El checksum garantiza que no se suba el mismo archivo 2 veces.
    """
    file_name = models.CharField(max_length=255)
    started_at = models.DateTimeField(auto_now_add=True)
    processed_at = models.DateTimeField(null=True, blank=True)
    rows_total = models.IntegerField(default=0)
    rows_imported = models.IntegerField(default=0)

    # Hash SHA256 para evitar importaciones duplicadas
    checksum = models.CharField(max_length=64, null=True, blank=True)

    # Permite manejar múltiples inventarios independientes
    inventory_name = models.CharField(max_length=128, default='default')

    class Meta:
        # Evita subir el mismo archivo al mismo inventario más de una vez.
        unique_together = ['checksum', 'inventory_name']

    def __str__(self):
        return f"{self.file_name} ({self.inventory_name})"


class Product(models.Model):
    """
    Producto identificado por código y ligado a un inventario particular.
    """
    code = models.CharField(max_length=64)
    description = models.CharField(max_length=512)
    group = models.CharField(max_length=128, blank=True)
    inventory_name = models.CharField(max_length=128, default='default')

    # Saldo inicial del inventario
    initial_balance = models.DecimalField(max_digits=15, decimal_places=3, default=0)
    initial_unit_cost = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    # Stock actual reportado desde archivos de actualización
    current_quantity = models.DecimalField(max_digits=15, decimal_places=3, null=True, blank=True)
    current_unit_cost = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    class Meta:
        # Permite tener productos con el mismo código en diferentes inventarios
        unique_together = ['code', 'inventory_name']

    def __str__(self):
        return f"{self.code} - {self.inventory_name}"


class WarehouseDetail(models.Model):
    """
    Detalles por almacén para productos del archivo base.
    Permite filtrar saldos iniciales por almacén.
    """
    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    warehouse = models.CharField(max_length=128)
    initial_quantity = models.DecimalField(max_digits=15, decimal_places=3, default=0)
    initial_value = models.DecimalField(max_digits=18, decimal_places=2, default=0)

    class Meta:
        unique_together = ['product', 'warehouse']

    def __str__(self):
        return f"{self.product.code} - {self.warehouse}"


class InventoryRecord(models.Model):
    """
    Representa una fila del archivo Excel que contiene un movimiento de inventario.
    """
    MOVEMENT_TYPES = [
        ('EA', 'Entrada'),
        ('SA', 'Salida'),
        ('GF', 'Entrada'),
    ]

    batch = models.ForeignKey(ImportBatch, on_delete=models.CASCADE)
    product = models.ForeignKey(Product, on_delete=models.PROTECT)
    warehouse = models.CharField(max_length=128)

    date = models.DateField()

    # Tipo de documento EA/SA
    document_type = models.CharField(max_length=4, choices=MOVEMENT_TYPES, null=True, blank=True)
    document_number = models.CharField(max_length=64, null=True, blank=True)

    # Cantidad del movimiento (negativa si es salida)
    quantity = models.DecimalField(max_digits=18, decimal_places=3)

    unit_cost = models.DecimalField(max_digits=18, decimal_places=2)
    total = models.DecimalField(max_digits=20, decimal_places=2)

    # Categoría asignada y lote
    category = models.CharField(max_length=128, blank=True)
    lote = models.CharField(max_length=64, blank=True)

    # Valor del saldo después del movimiento
    final_quantity = models.DecimalField(max_digits=18, decimal_places=3, null=True, blank=True)

    # Centro de costo (clave para permitir múltiples salidas del mismo documento)
    cost_center = models.CharField(max_length=64, null=True, blank=True)

    class Meta:
        """
        La unicidad NO debe impedir que un producto aparezca varias veces
        con el mismo documento/fecha.

        Lo que debe ser único es:
        - documento
        - producto
        - centro de costo
        - archivo origen

        Esto permite que:
        - un mismo documento tenga varias filas del mismo producto, mientras cambie cost_center.
        """
        unique_together = ['document_type', 'document_number', 'product', 'batch', 'cost_center']

        indexes = [
            models.Index(fields=['product', 'date']),
            models.Index(fields=['warehouse', 'date']),
            models.Index(fields=['document_type', 'document_number']),
        ]

    def __str__(self):
        return f"{self.product.code} {self.document_type}-{self.document_number} ({self.date})"
