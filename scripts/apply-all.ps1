Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $repoRoot
$labContext = "kind-k8s-security-lab"

function Require-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Comando obrigatorio nao encontrado: $Name"
    }
}

function Apply-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Manifesto nao encontrado: $RelativePath"
    }

    & kubectl apply -f $fullPath
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao aplicar manifesto: $RelativePath"
    }
}

function Require-LabContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpectedContext
    )

    $currentContext = (& kubectl config current-context 2>$null).Trim()
    if ($currentContext -ne $ExpectedContext) {
        if ($env:ALLOW_NON_LAB_CONTEXT -eq "true") {
            Write-Warning "Contexto atual '$currentContext' diferente de '$ExpectedContext', seguindo por override ALLOW_NON_LAB_CONTEXT=true."
            return
        }

        throw @(
            "Contexto atual do kubectl: '$currentContext'.",
            "Para evitar aplicar manifests no cluster errado, use o contexto '$ExpectedContext'.",
            "Comando sugerido: kubectl config use-context $ExpectedContext",
            "Se voce realmente quiser ignorar essa protecao, use ALLOW_NON_LAB_CONTEXT=true."
        ) -join " "
    }
}

function Apply-Stage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string[]]$Files
    )

    Write-Host "[INFO] $Title"
    foreach ($file in $Files) {
        Write-Host "  - Aplicando $file"
        Apply-File -RelativePath $file
    }
}

Write-Host "[INFO] Iniciando aplicacao do laboratorio (modo seguro)."
Require-Command -Name "kubectl"
Require-LabContext -ExpectedContext $labContext

Apply-Stage -Title "1/7 - Namespaces" -Files @(
    "manifests/00-namespaces/namespace-security-lab.yaml",
    "manifests/00-namespaces/namespace-frontend.yaml",
    "manifests/00-namespaces/namespace-backend.yaml",
    "manifests/00-namespaces/namespace-observability.yaml",
    "manifests/00-namespaces/namespace-insecure-demo.yaml"
)

Apply-Stage -Title "2/7 - ServiceAccounts" -Files @(
    "manifests/02-service-account/app-serviceaccount.yaml",
    "manifests/02-service-account/pod-reader-serviceaccount.yaml",
    "manifests/02-service-account/serviceaccount-token-secret-demo.yaml"
)

Apply-Stage -Title "3/7 - RBAC seguro (menor privilegio)" -Files @(
    "manifests/03-rbac/readonly-role.yaml",
    "manifests/03-rbac/readonly-rolebinding.yaml",
    "manifests/03-rbac/restricted-role.yaml",
    "manifests/03-rbac/restricted-rolebinding.yaml",
    "manifests/03-rbac/kube-board-readonly-demo.yaml"
)

Apply-Stage -Title "4/7 - SecurityContext seguro" -Files @(
    "manifests/01-security-context/app-secure-deployment.yaml",
    "manifests/01-security-context/app-secure-service.yaml",
    "manifests/01-security-context/pod-secure-example.yaml"
)

Apply-Stage -Title "5/7 - Workloads para testes de NetworkPolicy" -Files @(
    "manifests/05-network-policy/backend-api-deployment.yaml",
    "manifests/05-network-policy/backend-api-service.yaml",
    "manifests/05-network-policy/frontend-client-allowed.yaml",
    "manifests/05-network-policy/frontend-client-denied.yaml",
    "manifests/05-network-policy/observability-client.yaml"
)

Apply-Stage -Title "6/7 - NetworkPolicies" -Files @(
    "manifests/05-network-policy/default-deny-backend.yaml",
    "manifests/05-network-policy/allow-frontend-to-backend-api.yaml",
    "manifests/05-network-policy/allow-observability-to-backend-api.yaml",
    "manifests/05-network-policy/allow-dns-egress.yaml"
)

Apply-Stage -Title "7/7 - Admissao (somente manifestos seguros)" -Files @(
    "manifests/06-admission/restricted-namespace-example.yaml",
    "manifests/06-admission/pod-compliant-restricted.yaml"
)

Write-Host "[INFO] Aguardando disponibilidade dos deployments principais..."
& kubectl -n k8s-security-lab rollout status deployment/security-lab-app --timeout=240s
if ($LASTEXITCODE -ne 0) { throw "Falha ao aguardar deployment/security-lab-app." }

& kubectl -n security-backend rollout status deployment/backend-api --timeout=240s
if ($LASTEXITCODE -ne 0) { throw "Falha ao aguardar deployment/backend-api." }

Write-Host "[OK] Aplicacao concluida."
Write-Host "[INFO] Manifestos propositalmente NAO aplicados neste fluxo:"
Write-Host "  - manifests/01-security-context/pod-insecure-example.yaml"
Write-Host "  - manifests/03-rbac/admin-clusterrolebinding-demo.yaml"
Write-Host "  - manifests/04-registry-auth/deployment-with-imagepullsecret-example.yaml"
Write-Host "  - manifests/06-admission/pod-violates-restricted.yaml"
