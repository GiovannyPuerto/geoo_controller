param(
    [string]$BaseUrl = "http://127.0.0.1:8000/api/inventory",
    [int]$ServerPid = 0
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Python = Join-Path (Split-Path -Parent $Root) ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    throw "No se encontró Python en $Python"
}

Set-Location $Root

for ($i = 1; $i -le 3; $i++) {
    Write-Host "=== Ronda $i/3 ===" -ForegroundColor Cyan

    & $Python perf\perf_runner.py `
        --base-url $BaseUrl `
        --server-pid $ServerPid `
        --base-rows 30000 `
        --update-rows 50000 `
        --update-files 4 `
        --read-workers 10 `
        --read-repeats 12 `
        --export-workers 4 `
        --export-repeats 3 `
        --upload-workers 3 `
        --upload-repeats 3

    if ($LASTEXITCODE -ne 0) {
        throw "Falló la ronda $i"
    }

    Start-Sleep -Seconds 20
}

Write-Host "Prueba soak finalizada. Revisa perf/results/*.md y *.json" -ForegroundColor Green
