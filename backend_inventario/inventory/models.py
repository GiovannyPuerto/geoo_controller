from django.db import models


class ImportBatch(models.Model):
    """
    Representa un archivo importado (base o actualización).
    El checksum garantiza que no se suba el mismo archivo 2 veces.
    """
    archivo = models.CharField(max_length=255, db_column='archivo')
    iniciado_en = models.DateTimeField(auto_now_add=True, db_column='iniciado_en')
    procesado_en = models.DateTimeField(null=True, blank=True, db_column='procesado_en')
    filas_totales = models.IntegerField(default=0, db_column='filas_totales')
    filas_importadas = models.IntegerField(default=0, db_column='filas_importadas')

    # Hash SHA256 para evitar importaciones duplicadas
    suma_verificacion = models.CharField(max_length=64, null=True, blank=True, db_column='suma_verificacion')

    # Permite manejar múltiples inventarios independientes
    nombre_inventario = models.CharField(
        max_length=128,
        default='Por defecto',
        db_index=True,
        db_column='nombre_inventario',
    )

    class Meta:
        db_table = 'inventario_lotes_importacion'
        # Evita subir el mismo archivo al mismo inventario más de una vez.
        unique_together = ['suma_verificacion', 'nombre_inventario']

    def __str__(self):
        return f"{self.archivo} ({self.nombre_inventario})"


class Product(models.Model):
    """
    Producto identificado por código y ligado a un inventario particular.
    """
    codigo = models.CharField(max_length=64, db_column='codigo')
    descripcion = models.CharField(max_length=512, db_column='descripcion')
    grupo = models.CharField(max_length=128, blank=True, db_column='grupo')
    nombre_inventario = models.CharField(
        max_length=128,
        default='Por defecto',
        db_index=True,
        db_column='nombre_inventario',
    )

    # Saldo inicial del inventario
    saldo_inicial = models.DecimalField(
        max_digits=15,
        decimal_places=3,
        default=0,
        db_column='saldo_inicial',
    )
    costo_unitario_inicial = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=0,
        db_column='costo_unitario_inicial',
    )

    # Stock actual reportado desde archivos de actualización
    cantidad_actual = models.DecimalField(
        max_digits=15,
        decimal_places=3,
        null=True,
        blank=True,
        db_column='cantidad_actual',
    )
    costo_unitario_actual = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        null=True,
        blank=True,
        db_column='costo_unitario_actual',
    )

    class Meta:
        db_table = 'inventario_productos'
        # Permite tener productos con el mismo código en diferentes inventarios
        unique_together = ['codigo', 'nombre_inventario']

    def __str__(self):
        return f"{self.codigo} - {self.nombre_inventario}"


class WarehouseDetail(models.Model):
    """
    Detalles por almacén para productos del archivo base.
    Permite filtrar saldos iniciales por almacén.
    """
    producto = models.ForeignKey(Product, on_delete=models.CASCADE, db_column='producto_id')
    almacen = models.CharField(max_length=128, db_column='almacen')
    cantidad_inicial = models.DecimalField(
        max_digits=15,
        decimal_places=3,
        default=0,
        db_column='cantidad_inicial',
    )
    valor_inicial = models.DecimalField(
        max_digits=18,
        decimal_places=2,
        default=0,
        db_column='valor_inicial',
    )

    class Meta:
        db_table = 'inventario_detalle_almacen'
        unique_together = ['producto', 'almacen']

    def __str__(self):
        return f"{self.producto.codigo} - {self.almacen}"


class InventoryRecord(models.Model):
    """
    Representa una fila del archivo Excel que contiene un movimiento de inventario.
    """
    MOVEMENT_TYPES = [
        ('EA', 'Entrada'),
        ('SA', 'Salida'),
        ('ND', 'Nota Débito'),
        ('RF', 'Referencia'),
        ('DV', 'Devolución'),
        ('GF', 'Documento Siesa'),
        ('AC', 'Ajuste de compra')
    ]

    lote_importacion = models.ForeignKey(ImportBatch, on_delete=models.CASCADE, db_column='lote_id')
    producto = models.ForeignKey(Product, on_delete=models.PROTECT, db_column='producto_id')
    almacen = models.CharField(max_length=128, db_column='almacen')

    fecha = models.DateField(db_column='fecha')

    # Tipo de documento detectado desde Siesa (EA/SA/ND/RF/DV/AC/...).
    tipo_documento = models.CharField(max_length=8, null=True, blank=True, db_column='tipo_documento')
    numero_documento = models.CharField(max_length=64, null=True, blank=True, db_column='numero_documento')
    documento_origen = models.CharField(max_length=128, blank=True, default='', db_column='documento_origen')
    registro_origen = models.CharField(max_length=64, blank=True, default='', db_column='registro_origen')

    # Cantidad del movimiento (negativa si es salida)
    cantidad = models.DecimalField(max_digits=18, decimal_places=3, db_column='cantidad')

    costo_unitario = models.DecimalField(max_digits=18, decimal_places=2, db_column='costo_unitario')
    valor_total = models.DecimalField(max_digits=20, decimal_places=2, db_column='valor_total')

    # Categoría asignada y lote
    categoria = models.CharField(max_length=128, blank=True, db_column='categoria')
    lote = models.CharField(max_length=64, blank=True, db_column='lote')

    # Valor del saldo después del movimiento
    cantidad_final = models.DecimalField(
        max_digits=18,
        decimal_places=3,
        null=True,
        blank=True,
        db_column='cantidad_final',
    )

    # Centro de costo (clave para permitir múltiples salidas del mismo documento)
    centro_costo = models.CharField(max_length=64, null=True, blank=True, db_column='centro_costo')

    # Huella SHA-256 del contenido del movimiento (32 hex chars).
    # Permite detectar duplicados cuando source_record no es fiable.
    hash_fila = models.CharField(max_length=64, null=True, blank=True, unique=True, db_column='hash_fila')

    class Meta:
        db_table = 'inventario_movimientos'
        """
        Un registro se identifica por su línea de origen (`source_document` + `source_record`)
        más el contexto de producto/fecha/almacén/centro de costo/lote.

        Esta estrategia permite:
        - re-subidas idempotentes sin duplicar líneas;
        - múltiples líneas legítimas del mismo documento y producto.
        """
        unique_together = [
            'documento_origen',
            'registro_origen',
            'producto',
            'centro_costo',
            'fecha',
            'almacen',
            'lote',
        ]

        indexes = [
            models.Index(fields=['producto', 'fecha'], name='inventario__product_00b285_idx'),
            models.Index(fields=['producto', 'almacen'], name='inventario__product_75623a_idx'),
            models.Index(fields=['producto', 'almacen', 'fecha'], name='inventario__product_1a8882_idx'),
            models.Index(fields=['almacen', 'fecha'], name='inventario__almacen_065fc3_idx'),
            models.Index(fields=['tipo_documento', 'numero_documento'], name='inventario__tipo_do_f42158_idx'),
            models.Index(fields=['documento_origen', 'registro_origen'], name='inventory_i_source_doc_rec_idx'),
            models.Index(fields=['fecha'], name='inventario__fecha_56f2eb_idx'),
        ]

    def __str__(self):
        return f"{self.producto.codigo} {self.tipo_documento}-{self.numero_documento} ({self.fecha})"


def _register_legacy_field_aliases(model, alias_map):
    """
    Registra alias legacy (en inglés) para mantener compatibilidad en ORM y atributos.
    """
    for legacy_name, current_name in alias_map.items():
        field = model._meta.get_field(current_name)

        # Permite lookups ORM: filter(legacy_name=...), values('legacy_name'), order_by('legacy_name')
        model._meta._forward_fields_map[legacy_name] = field

        # Alias en atributos de instancia: obj.legacy_name <-> obj.current_name
        if not hasattr(model, legacy_name):
            setattr(
                model,
                legacy_name,
                property(
                    lambda self, target=current_name: getattr(self, target),
                    lambda self, value, target=current_name: setattr(self, target, value),
                ),
            )

        # Alias para attname de FK (ej: product_id -> producto_id)
        current_attname = field.attname
        legacy_attname = f"{legacy_name}_id" if current_attname.endswith('_id') else None
        if legacy_attname and legacy_attname != current_attname:
            model._meta._forward_fields_map[legacy_attname] = field
            if not hasattr(model, legacy_attname):
                setattr(
                    model,
                    legacy_attname,
                    property(
                        lambda self, target=current_attname: getattr(self, target),
                        lambda self, value, target=current_attname: setattr(self, target, value),
                    ),
                )

    # Recalcular cache de propiedades para que Model(**kwargs) admita alias legacy.
    model._meta.__dict__.pop('_property_names', None)


_register_legacy_field_aliases(
    ImportBatch,
    {
        'file_name': 'archivo',
        'started_at': 'iniciado_en',
        'processed_at': 'procesado_en',
        'rows_total': 'filas_totales',
        'rows_imported': 'filas_importadas',
        'checksum': 'suma_verificacion',
        'inventory_name': 'nombre_inventario',
    },
)

_register_legacy_field_aliases(
    Product,
    {
        'code': 'codigo',
        'description': 'descripcion',
        'group': 'grupo',
        'inventory_name': 'nombre_inventario',
        'initial_balance': 'saldo_inicial',
        'initial_unit_cost': 'costo_unitario_inicial',
        'current_quantity': 'cantidad_actual',
        'current_unit_cost': 'costo_unitario_actual',
    },
)

_register_legacy_field_aliases(
    WarehouseDetail,
    {
        'product': 'producto',
        'warehouse': 'almacen',
        'initial_quantity': 'cantidad_inicial',
        'initial_value': 'valor_inicial',
    },
)

_register_legacy_field_aliases(
    InventoryRecord,
    {
        'batch': 'lote_importacion',
        'product': 'producto',
        'warehouse': 'almacen',
        'date': 'fecha',
        'document_type': 'tipo_documento',
        'document_number': 'numero_documento',
        'source_document': 'documento_origen',
        'source_record': 'registro_origen',
        'quantity': 'cantidad',
        'unit_cost': 'costo_unitario',
        'total': 'valor_total',
        'category': 'categoria',
        'final_quantity': 'cantidad_final',
        'cost_center': 'centro_costo',
        'row_hash': 'hash_fila',
    },
)
