#requires -RunAsAdministrator
param(
    [string]$TaskName        = 'teste-ssh-poll-deploy',
    [int]   $IntervalMinutes = 5,
    [string]$ScriptPath      = 'C:\Users\cloud\project-ssh-py-api\deploy\poll-deploy.ps1',
    [string]$RunAsUser       = 'supra\cloud'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ScriptPath)) {
    Write-Output "ERRO: script nao encontrado em $ScriptPath"
    exit 1
}

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

# S4U: roda mesmo sem o usuario estar logado, sem precisar armazenar a senha.
# Mantem o contexto do usuario 'cloud', onde o uv e o projeto vivem.
$principal = New-ScheduledTaskPrincipal `
    -UserId $RunAsUser `
    -LogonType S4U `
    -RunLevel Highest

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Output "Tarefa '$TaskName' ja existe. Removendo para recriar..."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Verifica a cada $IntervalMinutes min se ha commit novo em besc-projects/teste-ssh e redeploya na porta 9577." | Out-Null

Write-Output "Tarefa '$TaskName' registrada (a cada $IntervalMinutes minutos)."
Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName, State | Format-Table -AutoSize | Out-String -Width 200
