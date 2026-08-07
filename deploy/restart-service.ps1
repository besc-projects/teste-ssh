$ErrorActionPreference = "Stop"

$Port = 9577
$ProjectDir = $PWD.Path

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "uv nao encontrado, instalando..."
    powershell -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
}

Write-Host "Sincronizando dependencias..."
uv sync

Write-Host "Derrubando processo anterior na porta $Port (se existir)..."
$existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    $existing | ForEach-Object {
        Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

Write-Host "Subindo aplicacao na porta $Port..."
$uvExe = (Get-Command uv).Source
Start-Process -FilePath $uvExe `
    -ArgumentList "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "$Port" `
    -WorkingDirectory $ProjectDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$ProjectDir\app.out.log" `
    -RedirectStandardError "$ProjectDir\app.err.log"

Start-Sleep -Seconds 3
$check = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($check) {
    Write-Host "Deploy OK - aplicacao respondendo na porta $Port"
} else {
    Write-Host "ATENCAO: nao foi possivel confirmar que a porta $Port esta escutando. Veja app.err.log"
    Get-Content "$ProjectDir\app.err.log" -ErrorAction SilentlyContinue
    exit 1
}
