import argparse
import json
import statistics
import threading
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlencode

import requests

try:
    import psutil
except Exception:
    psutil = None

from generate_perf_files import generate_files


@dataclass
class RequestMetric:
    endpoint: str
    method: str
    status_code: int
    duration_ms: float
    response_bytes: int
    ok: bool
    error: str | None = None


@dataclass
class ProcessSample:
    ts: float
    cpu_percent: float
    rss_mb: float
    vms_mb: float


class ProcessMonitor:
    def __init__(self, pid: int | None, interval: float = 0.5):
        self.pid = pid
        self.interval = interval
        self.samples: list[ProcessSample] = []
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if not self.pid or psutil is None:
            return
        process = psutil.Process(self.pid)
        process.cpu_percent(interval=None)

        def _run() -> None:
            while not self._stop.is_set():
                try:
                    mem = process.memory_info()
                    cpu = process.cpu_percent(interval=None)
                    self.samples.append(
                        ProcessSample(
                            ts=time.time(),
                            cpu_percent=cpu,
                            rss_mb=mem.rss / (1024 * 1024),
                            vms_mb=mem.vms / (1024 * 1024),
                        )
                    )
                except Exception:
                    break
                time.sleep(self.interval)

        self._thread = threading.Thread(target=_run, daemon=True)
        self._thread.start()

    def stop(self) -> list[ProcessSample]:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)
        return self.samples


class BenchClient:
    def __init__(self, base_url: str, timeout_seconds: int):
        self.base_url = base_url.rstrip('/')
        self.timeout_seconds = timeout_seconds
        self.session = requests.Session()

    def request(
        self,
        method: str,
        endpoint: str,
        params: dict[str, Any] | None = None,
        files: dict[str, Any] | list[tuple[str, Any]] | None = None,
    ) -> RequestMetric:
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        if params:
            url = f"{url}?{urlencode(params, doseq=True)}"

        started = time.perf_counter()
        try:
            response = self.session.request(
                method=method,
                url=url,
                files=files,
                timeout=self.timeout_seconds,
            )
            duration_ms = (time.perf_counter() - started) * 1000
            return RequestMetric(
                endpoint=endpoint,
                method=method,
                status_code=response.status_code,
                duration_ms=duration_ms,
                response_bytes=len(response.content or b''),
                ok=200 <= response.status_code < 300,
            )
        except Exception as exc:
            duration_ms = (time.perf_counter() - started) * 1000
            return RequestMetric(
                endpoint=endpoint,
                method=method,
                status_code=0,
                duration_ms=duration_ms,
                response_bytes=0,
                ok=False,
                error=str(exc),
            )


def _percentile(sorted_values: list[float], percentile: float) -> float:
    if not sorted_values:
        return 0.0
    if len(sorted_values) == 1:
        return sorted_values[0]
    pos = (len(sorted_values) - 1) * percentile
    low = int(pos)
    high = min(low + 1, len(sorted_values) - 1)
    frac = pos - low
    return sorted_values[low] * (1 - frac) + sorted_values[high] * frac


def summarize(metrics: list[RequestMetric]) -> dict[str, Any]:
    latencies = sorted([m.duration_ms for m in metrics])
    oks = [m for m in metrics if m.ok]
    errors = [m for m in metrics if not m.ok]
    total_bytes = sum(m.response_bytes for m in metrics)

    return {
        'requests': len(metrics),
        'ok_requests': len(oks),
        'error_requests': len(errors),
        'error_rate_pct': round((len(errors) / len(metrics) * 100.0), 3) if metrics else 0.0,
        'avg_ms': round(statistics.mean(latencies), 3) if latencies else 0.0,
        'median_ms': round(statistics.median(latencies), 3) if latencies else 0.0,
        'p95_ms': round(_percentile(latencies, 0.95), 3) if latencies else 0.0,
        'p99_ms': round(_percentile(latencies, 0.99), 3) if latencies else 0.0,
        'min_ms': round(min(latencies), 3) if latencies else 0.0,
        'max_ms': round(max(latencies), 3) if latencies else 0.0,
        'total_response_bytes': total_bytes,
    }


def run_parallel(
    worker_name: str,
    workers: int,
    requests_per_worker: int,
    fn: Callable[[], RequestMetric],
) -> list[RequestMetric]:
    results: list[RequestMetric] = []
    lock = threading.Lock()

    def _worker() -> None:
        local = []
        for _ in range(requests_per_worker):
            local.append(fn())
        with lock:
            results.extend(local)

    threads = [threading.Thread(target=_worker, name=f"{worker_name}-{i}") for i in range(workers)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return results


def benchmark_read_endpoints(client: BenchClient, inventory_name: str, read_workers: int, read_repeats: int) -> dict[str, Any]:
    now_date = datetime.now().date().isoformat()

    scenarios = [
            ('GET', 'resumen/', {'inventory_name': inventory_name}),
            ('GET', 'analisis-producto/', {'inventory_name': inventory_name, 'limit': '5000'}),
            ('GET', 'registros/', {'inventory_name': inventory_name}),
            ('GET', 'movimientos-mensuales/', {'inventory_name': inventory_name}),
            ('GET', 'cortes-mensuales/', {'inventory_name': inventory_name, 'months': '12'}),
            ('GET', 'cortes-mensuales-productos/', {'inventory_name': inventory_name, 'month': datetime.now().strftime('%Y-%m'), 'limit': '5000'}),
            ('GET', 'inventario-a-fecha/', {'inventory_name': inventory_name, 'date': now_date}),
    ]

    output: dict[str, Any] = {}
    for method, endpoint, params in scenarios:
        metrics = run_parallel(
            worker_name=f"read-{endpoint.replace('/', '-')}",
            workers=read_workers,
            requests_per_worker=read_repeats,
            fn=lambda m=method, e=endpoint, p=params: client.request(m, e, p),
        )
        output[endpoint] = {
            'method': method,
            'params': params,
            'summary': summarize(metrics),
        }

    return output


def benchmark_export_endpoints(client: BenchClient, inventory_name: str, export_workers: int, export_repeats: int) -> dict[str, Any]:
    scenarios = [
            ('GET', 'exportar-analisis/', {'inventory_name': inventory_name, 'format': 'excel'}),
            ('GET', 'exportar-analisis/', {'inventory_name': inventory_name, 'format': 'pdf'}),
            ('GET', 'exportar-movimientos/', {'inventory_name': inventory_name, 'format': 'excel'}),
            ('GET', 'exportar-movimientos/', {'inventory_name': inventory_name, 'format': 'pdf'}),
            ('GET', 'exportar-cortes-mensuales/', {'inventory_name': inventory_name, 'format': 'excel'}),
            ('GET', 'exportar-cortes-mensuales/', {'inventory_name': inventory_name, 'format': 'pdf'}),
            ('GET', 'exportar-tops/', {'inventory_name': inventory_name, 'format': 'excel'}),
            ('GET', 'exportar-tops/', {'inventory_name': inventory_name, 'format': 'pdf'}),
    ]

    output: dict[str, Any] = {}
    for method, endpoint, params in scenarios:
        metrics = run_parallel(
            worker_name=f"export-{endpoint.replace('/', '-')}-{params['format']}",
            workers=export_workers,
            requests_per_worker=export_repeats,
            fn=lambda m=method, e=endpoint, p=params: client.request(m, e, p),
        )
        key = f"{endpoint}?format={params['format']}"
        output[key] = {
            'method': method,
            'params': params,
            'summary': summarize(metrics),
        }
    return output


def benchmark_upload_endpoints(
    client: BenchClient,
    inventory_name: str,
    base_file: Path,
    update_files: list[Path],
    upload_workers: int,
    upload_repeats: int,
) -> dict[str, Any]:
    output: dict[str, Any] = {}

    with base_file.open('rb') as bf:
        base_metric = client.request(
            'POST',
                f'actualizar/{inventory_name}/',
            files={'base_file': (base_file.name, bf, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')},
        )

    output['base_upload'] = {
        'single_request': asdict(base_metric),
        'summary': summarize([base_metric]),
    }

    update_target = update_files[:upload_workers] if len(update_files) >= upload_workers else update_files
    if not update_target:
        return output

    def _upload_update_file(file_path: Path) -> RequestMetric:
        with file_path.open('rb') as uf:
            return client.request(
                'POST',
                    f'actualizar/{inventory_name}/',
                files=[('update_files', (file_path.name, uf, 'text/csv'))],
            )

    all_metrics: list[RequestMetric] = []
    for _ in range(upload_repeats):
        batch_metrics = run_parallel(
            worker_name='upload-update',
            workers=len(update_target),
            requests_per_worker=1,
            fn=lambda files=list(update_target): _upload_update_file(files[int(time.time_ns() % len(files))]),
        )
        all_metrics.extend(batch_metrics)

    output['update_uploads'] = {
        'files': [str(p) for p in update_target],
        'summary': summarize(all_metrics),
    }

    return output


def summarize_process(samples: list[ProcessSample]) -> dict[str, Any]:
    if not samples:
        return {'enabled': False}

    cpu = [s.cpu_percent for s in samples]
    rss = [s.rss_mb for s in samples]
    vms = [s.vms_mb for s in samples]

    return {
        'enabled': True,
        'samples': len(samples),
        'cpu_avg_pct': round(statistics.mean(cpu), 3),
        'cpu_peak_pct': round(max(cpu), 3),
        'rss_avg_mb': round(statistics.mean(rss), 3),
        'rss_peak_mb': round(max(rss), 3),
        'vms_avg_mb': round(statistics.mean(vms), 3),
        'vms_peak_mb': round(max(vms), 3),
    }


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = []
    lines.append('# Reporte de Performance API Inventario')
    lines.append('')
    lines.append(f"- Fecha: {report['meta']['generated_at']}")
    lines.append(f"- Base URL: {report['meta']['base_url']}")
    lines.append(f"- Inventario benchmark: {report['meta']['inventory_name']}")
    lines.append('')

    proc = report['process']
    lines.append('## Consumo del proceso backend')
    if proc.get('enabled'):
        lines.append(f"- CPU promedio: {proc['cpu_avg_pct']}%")
        lines.append(f"- CPU pico: {proc['cpu_peak_pct']}%")
        lines.append(f"- RSS promedio: {proc['rss_avg_mb']} MB")
        lines.append(f"- RSS pico: {proc['rss_peak_mb']} MB")
    else:
        lines.append('- Monitoreo desactivado (no se pasó --server-pid o no está psutil).')
    lines.append('')

    def _section(title: str, payload: dict[str, Any]) -> None:
        lines.append(f'## {title}')
        for endpoint, data in payload.items():
            s = data['summary']
            lines.append(f"- {endpoint}: req={s['requests']}, err%={s['error_rate_pct']}, avg={s['avg_ms']}ms, p95={s['p95_ms']}ms, p99={s['p99_ms']}ms")
        lines.append('')

    _section('Lectura', report['read'])
    _section('Exportaciones', report['export'])

    lines.append('## Subidas')
    base_s = report['upload']['base_upload']['summary']
    upd_s = report['upload'].get('update_uploads', {}).get('summary', {})
    lines.append(f"- Base upload: req={base_s.get('requests', 0)}, err%={base_s.get('error_rate_pct', 0)}, avg={base_s.get('avg_ms', 0)}ms")
    if upd_s:
        lines.append(f"- Updates upload: req={upd_s.get('requests', 0)}, err%={upd_s.get('error_rate_pct', 0)}, avg={upd_s.get('avg_ms', 0)}ms, p95={upd_s.get('p95_ms', 0)}ms")
    lines.append('')

    path.write_text('\n'.join(lines), encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser(description='Benchmark de endpoints pesados para Geo Inventario.')
    parser.add_argument('--base-url', default='http://127.0.0.1:8000/api/inventory', help='URL base de la API.')
    parser.add_argument('--timeout', type=int, default=180, help='Timeout por request en segundos.')
    parser.add_argument('--server-pid', type=int, default=0, help='PID del proceso Django/Gunicorn para medir CPU/RAM.')
    parser.add_argument('--output-dir', default='perf/results', help='Carpeta donde guardar reportes.')
    parser.add_argument('--data-dir', default='perf/data', help='Carpeta para archivos de carga.')
    parser.add_argument('--base-rows', type=int, default=20000)
    parser.add_argument('--update-rows', type=int, default=35000)
    parser.add_argument('--update-files', type=int, default=3)
    parser.add_argument('--read-workers', type=int, default=8)
    parser.add_argument('--read-repeats', type=int, default=10)
    parser.add_argument('--export-workers', type=int, default=3)
    parser.add_argument('--export-repeats', type=int, default=2)
    parser.add_argument('--upload-workers', type=int, default=2)
    parser.add_argument('--upload-repeats', type=int, default=2)
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    generated = generate_files(
        output_dir=Path(args.data_dir),
        base_rows=args.base_rows,
        update_rows=args.update_rows,
        update_files=args.update_files,
    )

    run_suffix = datetime.now().strftime('%Y%m%d_%H%M%S')
    inventory_name = f'perf_{run_suffix.lower()}'

    client = BenchClient(base_url=args.base_url, timeout_seconds=args.timeout)
    monitor = ProcessMonitor(pid=args.server_pid if args.server_pid > 0 else None)

    monitor.start()
    try:
        upload_report = benchmark_upload_endpoints(
            client=client,
            inventory_name=inventory_name,
            base_file=Path(generated['base_file']),
            update_files=[Path(item['csv']) for item in generated['update_files']],
            upload_workers=max(1, args.upload_workers),
            upload_repeats=max(1, args.upload_repeats),
        )

        read_report = benchmark_read_endpoints(
            client=client,
            inventory_name=inventory_name,
            read_workers=max(1, args.read_workers),
            read_repeats=max(1, args.read_repeats),
        )

        export_report = benchmark_export_endpoints(
            client=client,
            inventory_name=inventory_name,
            export_workers=max(1, args.export_workers),
            export_repeats=max(1, args.export_repeats),
        )
    finally:
        process_samples = monitor.stop()

    report = {
        'meta': {
            'generated_at': datetime.now().isoformat(),
            'base_url': args.base_url,
            'inventory_name': inventory_name,
            'base_file': generated['base_file'],
            'update_files': generated['update_files'],
            'configuration': {
                'read_workers': args.read_workers,
                'read_repeats': args.read_repeats,
                'export_workers': args.export_workers,
                'export_repeats': args.export_repeats,
                'upload_workers': args.upload_workers,
                'upload_repeats': args.upload_repeats,
            },
        },
        'process': summarize_process(process_samples),
        'upload': upload_report,
        'read': read_report,
        'export': export_report,
    }

    json_path = output_dir / f'perf_report_{run_suffix}.json'
    md_path = output_dir / f'perf_report_{run_suffix}.md'

    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    write_markdown(report, md_path)

    print(f'JSON report: {json_path}')
    print(f'Markdown report: {md_path}')


if __name__ == '__main__':
    main()
