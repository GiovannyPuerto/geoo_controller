import argparse
from pathlib import Path
from datetime import date, datetime, timedelta
import random

import pandas as pd


def _build_base_df(rows: int) -> pd.DataFrame:
    start = date.today().replace(day=1)
    records = []
    for idx in range(rows):
        quantity = round(random.uniform(1, 350), 3)
        unit_cost = round(random.uniform(1500, 15000), 2)
        records.append(
            {
                'fecha_corte': start.isoformat(),
                'mes': start.strftime('%Y-%m'),
                'almacen': f'ALM-{(idx % 5) + 1}',
                'grupo': f'GRUPO-{(idx % 8) + 1}',
                'codigo': f'P{idx + 1:06d}',
                'descripcion': f'Producto Performance {idx + 1}',
                'cantidad': quantity,
                'unidad_medida': 'UND',
                'costo_unitario': unit_cost,
                'valor_total': round(quantity * unit_cost, 2),
            }
        )
    return pd.DataFrame(records)


def _build_update_df(
    base_rows: int,
    rows: int,
    day_offset: int,
    *,
    base_cut_date: date,
) -> pd.DataFrame:
    # Mantener actualizaciones en rango válido respecto a la base:
    # base_cut_date + 1 día en adelante.
    start = base_cut_date + timedelta(days=1)
    records = []
    for idx in range(rows):
        product_idx = (idx % base_rows) + 1
        is_entry = (idx % 3) != 0
        entry = round(random.uniform(0.1, 60), 3) if is_entry else 0.0
        exit_qty = round(random.uniform(0.1, 60), 3) if not is_entry else 0.0
        quantity = round(entry - exit_qty, 3)
        unit_cost = round(random.uniform(1500, 15000), 2)
        movement_date = (start + timedelta(days=(idx % 28) + day_offset)).isoformat()
        doc_num = f"DOC{day_offset:02d}{idx + 1:07d}"

        records.append(
            {
                'item': f'P{product_idx:06d}',
                'desc_item': f'Producto Performance {product_idx}',
                'localizacion': f'ALM-{(idx % 5) + 1}',
                'categoria': f'GRUPO-{(idx % 8) + 1}',
                'fecha': movement_date,
                'documento': f'EA-{doc_num}' if is_entry else f'SA-{doc_num}',
                'registro': str(idx + 1),
                'cp': 'CP',
                'entradas': entry,
                'salidas': exit_qty,
                'unitario': unit_cost,
                'total': round(quantity * unit_cost, 2),
                'cantidad': quantity,
                'cost_center': f'CC-{(idx % 4) + 1}',
                'lote': f'LOT-{(idx % 20) + 1:03d}',
            }
        )
    return pd.DataFrame(records)


def generate_files(output_dir: Path, base_rows: int, update_rows: int, update_files: int) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)

    base_path = output_dir / 'base_perf.xlsx'
    base_df = _build_base_df(base_rows)
    base_df.to_excel(base_path, index=False)
    base_cut_date = datetime.strptime(
        str(base_df.iloc[0]['fecha_corte']),
        "%Y-%m-%d",
    ).date()

    update_paths = []
    for idx in range(update_files):
        update_df = _build_update_df(
            base_rows,
            update_rows,
            idx,
            base_cut_date=base_cut_date,
        )
        csv_path = output_dir / f'update_perf_{idx + 1:02d}.csv'
        xlsx_path = output_dir / f'update_perf_{idx + 1:02d}.xlsx'
        update_df.to_csv(csv_path, index=False)
        update_df.to_excel(xlsx_path, index=False)
        update_paths.append({'csv': str(csv_path), 'xlsx': str(xlsx_path)})

    return {
        'base_file': str(base_path),
        'update_files': update_paths,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description='Genera archivos sintéticos para pruebas de performance del inventario.')
    parser.add_argument('--output-dir', default='perf/data', help='Carpeta destino de archivos de prueba.')
    parser.add_argument('--base-rows', type=int, default=20000, help='Filas del archivo base (xlsx).')
    parser.add_argument('--update-rows', type=int, default=35000, help='Filas por archivo de actualización.')
    parser.add_argument('--update-files', type=int, default=2, help='Cantidad de archivos de actualización.')
    args = parser.parse_args()

    result = generate_files(Path(args.output_dir), args.base_rows, args.update_rows, args.update_files)
    print(result)


if __name__ == '__main__':
    main()
