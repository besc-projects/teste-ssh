# Executado pela tarefa agendada 'teste-ssh-app'. Roda o uvicorn em primeiro plano:
# quem mantem o processo vivo e o Agendador de Tarefas, nao a sessao que disparou o deploy.
param(
    [string]$AppDir = 'C:\Users\cloud\project-ssh-py-api\app',
    [int]   $Port   = 9577
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

Set-Location $AppDir

$uvLocal = Join-Path $env:USERPROFILE '.local\bin'
if ((Test-Path (Join-Path $uvLocal 'uv.exe')) -and ($env:Path -notlike "*$uvLocal*")) {
    $env:Path = "$uvLocal;$env:Path"
}

& uv run uvicorn main:app --host 0.0.0.0 --port $Port `
    *> (Join-Path $AppDir 'app.log')
