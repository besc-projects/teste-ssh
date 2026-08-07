# Nao usamos ErrorActionPreference='Stop': uv escreve mensagens normais em stderr,
# o que viraria erro terminante quando este script e chamado com a saida redirecionada.
# O sucesso e avaliado por exit code e pelo estado da porta.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Port     = 9577
$TaskName = 'teste-ssh-app'

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

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Output "ERRO: tarefa '$TaskName' nao existe. Rode deploy\install-scheduled-task.ps1 como Administrador."
    exit 1
}

Write-Output "Reiniciando a tarefa '$TaskName'..."
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

# Encerra qualquer resto que ainda segure a porta antes de subir de novo.
$existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    $existing | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

Start-ScheduledTask -TaskName $TaskName

# A primeira subida pode baixar o interpretador, entao damos ate 60s.
$deadline = (Get-Date).AddSeconds(60)
do {
    Start-Sleep -Seconds 3
    $listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
} while (-not $listening -and (Get-Date) -lt $deadline)

if ($listening) {
    Write-Output "Deploy OK - aplicacao escutando na porta $Port"
} else {
    Write-Output "ATENCAO: porta $Port nao esta escutando. Ultimas linhas de app.log:"
    Get-Content (Join-Path $PWD.Path 'app.log') -Tail 20 -ErrorAction SilentlyContinue
    exit 1
}
