param(
    [string]$AppDir  = 'C:\Users\cloud\project-ssh-py-api\app',
    [string]$RepoUrl = 'https://github.com/besc-projects/teste-ssh.git',
    [string]$Branch  = 'main',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogFile = Join-Path (Split-Path $AppDir -Parent) 'poll-deploy.log'

function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Output $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

# O git instala em Program Files e pode nao estar no PATH do contexto da tarefa agendada.
$gitCmd = 'C:\Program Files\Git\cmd'
if ((Test-Path "$gitCmd\git.exe") -and ($env:Path -notlike "*$gitCmd*")) {
    $env:Path = "$gitCmd;$env:Path"
}

try {
    if (-not (Test-Path (Join-Path $AppDir '.git'))) {
        Write-Log "Repo ausente. Clonando $RepoUrl em $AppDir..."
        New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
        git clone --branch $Branch $RepoUrl $AppDir 2>&1 | ForEach-Object { Write-Log "  $_" }
        if ($LASTEXITCODE -ne 0) { throw "git clone falhou (exit $LASTEXITCODE)" }
        $changed = $true
    } else {
        Set-Location $AppDir
        $before = (git rev-parse HEAD).Trim()

        git fetch origin $Branch 2>&1 | ForEach-Object { Write-Log "  $_" }
        if ($LASTEXITCODE -ne 0) { throw "git fetch falhou (exit $LASTEXITCODE) - rede indisponivel, tentando de novo no proximo ciclo" }

        $after = (git rev-parse "origin/$Branch").Trim()

        if ($before -eq $after -and -not $Force) {
            Write-Log "Sem mudancas (HEAD $($before.Substring(0,7))). Nada a fazer."
            exit 0
        }

        Write-Log "Commit novo detectado: $($before.Substring(0,7)) -> $($after.Substring(0,7)). Atualizando..."
        git reset --hard "origin/$Branch" 2>&1 | ForEach-Object { Write-Log "  $_" }
        if ($LASTEXITCODE -ne 0) { throw "git reset falhou (exit $LASTEXITCODE)" }
        $changed = $true
    }

    if ($changed) {
        Set-Location $AppDir
        Write-Log "Rodando restart-service.ps1..."
        & (Join-Path $AppDir 'deploy\restart-service.ps1') 2>&1 | ForEach-Object { Write-Log "  $_" }
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            throw "restart-service.ps1 falhou (exit $LASTEXITCODE)"
        }
        Write-Log "Deploy concluido com sucesso."
    }
}
catch {
    Write-Log "ERRO: $($_.Exception.Message)"
    exit 1
}
