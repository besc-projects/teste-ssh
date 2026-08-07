# Nao usamos ErrorActionPreference='Stop' aqui: uv e uvicorn escrevem mensagens
# normais em stderr, o que viraria erro terminante quando este script e chamado
# com a saida redirecionada. Verificamos exit codes explicitamente.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Port = 9577
$ProjectDir = $PWD.Path

$uvLocal = Join-Path $env:USERPROFILE '.local\bin'
if ((Test-Path (Join-Path $uvLocal 'uv.exe')) -and ($env:Path -notlike "*$uvLocal*")) {
    $env:Path = "$uvLocal;$env:Path"
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Output "uv nao encontrado, instalando..."
    powershell -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
    $env:Path = "$uvLocal;$env:Path"
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Output "ERRO: uv indisponivel apos tentativa de instalacao."
    exit 1
}

Write-Output "Sincronizando dependencias..."
& uv sync
if ($LASTEXITCODE -ne 0) {
    Write-Output "ERRO: uv sync retornou $LASTEXITCODE"
    exit 1
}

Write-Output "Derrubando processo anterior na porta $Port (se existir)..."
$existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    $existing | ForEach-Object {
        Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

Write-Output "Subindo aplicacao na porta $Port..."
$uvExe = (Get-Command uv).Source
Start-Process -FilePath $uvExe `
    -ArgumentList 'run', 'uvicorn', 'main:app', '--host', '0.0.0.0', '--port', "$Port" `
    -WorkingDirectory $ProjectDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$ProjectDir\app.out.log" `
    -RedirectStandardError "$ProjectDir\app.err.log"

Start-Sleep -Seconds 5
$check = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($check) {
    Write-Output "Deploy OK - aplicacao escutando na porta $Port"
} else {
    Write-Output "ATENCAO: porta $Port nao esta escutando. Conteudo de app.err.log:"
    Get-Content "$ProjectDir\app.err.log" -ErrorAction SilentlyContinue | Select-Object -Last 20
    exit 1
}
