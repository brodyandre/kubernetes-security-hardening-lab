param(
    [string]$RepoName = "kubernetes-security-hardening-lab",
    [ValidateSet("public", "private")]
    [string]$Visibility = "public",
    [string]$CommitMessage = "chore: publish lab updates",
    [string]$WorkflowName = "Validate Kubernetes YAML",
    [switch]$SkipWorkflowWatch,
    [switch]$OpenRepoPage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $repoRoot

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Comando obrigatorio nao encontrado: $Name"
    }
}

function Run-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )
    Write-Host "[INFO] $Message"
    & $ScriptBlock
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao executar etapa: $Message (exit code $LASTEXITCODE)."
    }
}

function Ensure-Git-Repo {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ".git"))) {
        Run-Command -Message "Inicializando repositorio git local..." -ScriptBlock { git init }
        Run-Command -Message "Configurando branch principal para main..." -ScriptBlock { git branch -M main }
    }
    else {
        Run-Command -Message "Repositorio git local detectado." -ScriptBlock { git rev-parse --is-inside-work-tree | Out-Null }
    }
}

function Ensure-Main-Branch {
    $currentBranch = (& git rev-parse --abbrev-ref HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao consultar branch atual."
    }
    if ($currentBranch -ne "main") {
        Run-Command -Message "Trocando branch para main..." -ScriptBlock { git checkout -B main }
    }
}

function Ensure-Commit {
    $status = & git status --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao consultar status do git."
    }
    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host "[INFO] Sem alteracoes pendentes para commit."
        return
    }

    Run-Command -Message "Adicionando alteracoes ao indice..." -ScriptBlock { git add . }
    Run-Command -Message "Criando commit..." -ScriptBlock { git commit -m $CommitMessage }
}

function Ensure-Gh-Auth {
    & gh auth status --hostname github.com | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI sem autenticacao valida. Execute 'gh auth login -h github.com' e rode este script novamente."
    }

    $owner = (& gh api user --jq .login).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($owner)) {
        throw "Nao foi possivel obter o usuario autenticado no GitHub CLI."
    }

    return $owner
}

function Ensure-Remote-And-Push {
    param([Parameter(Mandatory = $true)][string]$Owner)

    $originUrl = (git remote get-url origin 2>$null)
    if (-not [string]::IsNullOrWhiteSpace($originUrl)) {
        Run-Command -Message "Remote origin detectado ($originUrl). Fazendo push para main..." -ScriptBlock {
            git push -u origin main
        }
        return
    }

    $fullName = "$Owner/$RepoName"

    try {
        gh repo view $fullName | Out-Null
        Run-Command -Message "Repositorio remoto $fullName ja existe. Vinculando origin e fazendo push..." -ScriptBlock {
            git remote add origin "https://github.com/$fullName.git"
            git push -u origin main
        }
    }
    catch {
        Run-Command -Message "Criando repositorio remoto $fullName e fazendo push..." -ScriptBlock {
            gh repo create $RepoName --$Visibility --source . --remote origin --push
        }
    }
}

function Watch-Workflow {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($SkipWorkflowWatch) {
        Write-Host "[INFO] Monitoramento do workflow desabilitado por parametro."
        return
    }

    Write-Host "[INFO] Aguardando disparo do workflow '$Name'..."
    Start-Sleep -Seconds 8

    $runs = gh run list --workflow $Name --limit 1 --json databaseId,status,conclusion | ConvertFrom-Json
    if (-not $runs -or $runs.Count -eq 0) {
        Write-Warning "Nenhum run encontrado ainda para '$Name'."
        return
    }

    $runId = $runs[0].databaseId
    Write-Host "[INFO] Acompanhando run ID $runId..."
    gh run watch $runId --exit-status
}

Require-Command -Name "git"
Require-Command -Name "gh"

Write-Host "[INFO] Publicacao automatizada iniciada."
Write-Host "[INFO] Diretorio: $repoRoot"

Ensure-Git-Repo
Ensure-Main-Branch
Ensure-Commit
$owner = Ensure-Gh-Auth
Ensure-Remote-And-Push -Owner $owner
Watch-Workflow -Name $WorkflowName

if ($OpenRepoPage) {
    Run-Command -Message "Abrindo repositorio no navegador..." -ScriptBlock { gh repo view --web }
}

Write-Host "[OK] Publicacao concluida."
Write-Host "[INFO] Se o workflow estiver verde, gere o print: 11-github-actions-validate-passed.png"
