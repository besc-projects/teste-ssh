#requires -RunAsAdministrator
# Registra as duas tarefas do deploy:
#   teste-ssh-app         -> mantem o uvicorn no ar (na inicializacao do Windows)
#   teste-ssh-poll-deploy -> verifica commits novos periodicamente e redeploya
param(
    [string]$AppDir          = 'C:\Users\cloud\project-ssh-py-api\app',
    [int]   $IntervalMinutes = 5,
    [string]$RunAsUser       = 'supra\cloud'
)

$ErrorActionPreference = 'Stop'

$runAppScript = Join-Path $AppDir 'deploy\run-app.ps1'
$pollScript   = Join-Path $AppDir 'deploy\poll-deploy.ps1'

foreach ($s in @($runAppScript, $pollScript)) {
    if (-not (Test-Path $s)) {
        Write-Output "ERRO: script nao encontrado: $s"
        exit 1
    }
}

# S4U: roda mesmo sem o usuario estar logado e sem armazenar a senha,
# mantendo o contexto de 'cloud', onde o uv e o projeto vivem.
$principal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType S4U -RunLevel Highest

function Register-Task {
    param($Name, $Action, $Trigger, $Settings, $Description)
    if (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue) {
        Write-Output "Tarefa '$Name' ja existe. Recriando..."
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false
    }
    Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Trigger `
        -Settings $Settings -Principal $principal -Description $Description | Out-Null
    Write-Output "Tarefa '$Name' registrada."
}

# --- Tarefa da aplicacao -----------------------------------------------------
# ExecutionTimeLimit 0 = sem limite: e um processo de longa duracao.
Register-Task `
    -Name 'teste-ssh-app' `
    -Action (New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runAppScript`"") `
    -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)) `
    -Description 'Mantem a API FastAPI de teste no ar na porta 9577.'

# --- Tarefa de polling -------------------------------------------------------
Register-Task `
    -Name 'teste-ssh-poll-deploy' `
    -Action (New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$pollScript`"") `
    -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)) `
    -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)) `
    -Description "Verifica a cada $IntervalMinutes min se ha commit novo e redeploya a API."

Write-Output ""
Get-ScheduledTask -TaskName 'teste-ssh-*' | Select-Object TaskName, State |
    Format-Table -AutoSize | Out-String -Width 200
