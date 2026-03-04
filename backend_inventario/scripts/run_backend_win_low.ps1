Param(
    [string]$EnvFile = ".env.win_low.example"
)

$ErrorActionPreference = "Stop"

function Set-EnvFromFile {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) {
        Write-Host "Archivo de entorno no encontrado: $FilePath"
        return
    }

    Get-Content $FilePath | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        $parts = $line.Split("=", 2)
        if ($parts.Length -ne 2) { return }
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($key) {
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

Set-EnvFromFile -FilePath $EnvFile

if (-not $env:DJANGO_DEBUG) {
    $env:DJANGO_DEBUG = "0"
}

Write-Host "DJANGO_DEBUG=$env:DJANGO_DEBUG"
Write-Host "Iniciando backend con Waitress..."
python run_waitress.py
