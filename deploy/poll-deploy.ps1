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

# Write-Host, nao Write-Output: se escrevesse no stream de saida, as linhas de log
# emitidas dentro de uma funcao entrariam no valor de retorno dela.
function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

# O git escreve mensagens normais em stderr ("Cloning into...", progresso do fetch).
# Com ErrorActionPreference=Stop isso viraria erro terminante, entao isolamos as
# chamadas nativas aqui e decidimos o sucesso apenas pelo exit code.
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & git @Arguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($line in $output) { Write-Log "  $line" }
    return $code
}

# O git instala em Program Files e pode nao estar no PATH do contexto da tarefa agendada.
$gitCmd = 'C:\Program Files\Git\cmd'
if ((Test-Path "$gitCmd\git.exe") -and ($env:Path -notlike "*$gitCmd*")) {
    $env:Path = "$gitCmd;$env:Path"
}

try {
    $changed = $false

    if (-not (Test-Path (Join-Path $AppDir '.git'))) {
        Write-Log "Repo ausente. Clonando $RepoUrl em $AppDir..."
        if (Test-Path $AppDir) { Remove-Item $AppDir -Recurse -Force }
        if ((Invoke-Git clone --branch $Branch $RepoUrl $AppDir) -ne 0) {
            throw "git clone falhou"
        }
        $changed = $true
    } else {
        Set-Location $AppDir
        $before = (& git rev-parse HEAD).Trim()

        if ((Invoke-Git fetch origin $Branch) -ne 0) {
            throw "git fetch falhou (rede indisponivel?) - nova tentativa no proximo ciclo"
        }

        $after = (& git rev-parse "origin/$Branch").Trim()

        if ($before -eq $after -and -not $Force) {
            Write-Log "Sem mudancas (HEAD $($before.Substring(0,7))). Nada a fazer."
            exit 0
        }

        Write-Log "Commit novo: $($before.Substring(0,7)) -> $($after.Substring(0,7)). Atualizando..."
        if ((Invoke-Git reset --hard "origin/$Branch") -ne 0) {
            throw "git reset falhou"
        }
        $changed = $true
    }

    if ($changed) {
        Set-Location $AppDir
        Write-Log "Rodando restart-service.ps1..."
        & (Join-Path $AppDir 'deploy\restart-service.ps1') 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log "Deploy concluido."
    }
}
catch {
    Write-Log "ERRO: $($_.Exception.Message)"
    exit 1
}
