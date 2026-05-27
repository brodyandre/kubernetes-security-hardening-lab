Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
    [switch]$ManifestsOnly,
    [switch]$DeleteCluster
)

$clusterName = "k8s-security-lab"
$labContext = "kind-k8s-security-lab"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $repoRoot

function Require-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Comando obrigatorio nao encontrado: $Name"
    }
}

function Remove-ManifestIfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Join-Path $repoRoot $RelativePath
    if (Test-Path -LiteralPath $fullPath) {
        Write-Host "  - Removendo $RelativePath"
        & kubectl delete --ignore-not-found -f $fullPath *> $null
    }
}

function Remove-LabManifests {
    Write-Host "[INFO] Limpando recursos do laboratorio via manifests..."

    # Ordem reversa para minimizar dependencias entre objetos.
    $files = @(
        "manifests/06-admission/pod-violates-restricted.yaml",
        "manifests/06-admission/pod-compliant-restricted.yaml",
        "manifests/05-network-policy/allow-dns-egress.yaml",
        "manifests/05-network-policy/allow-observability-to-backend-api.yaml",
        "manifests/05-network-policy/allow-frontend-to-backend-api.yaml",
        "manifests/05-network-policy/default-deny-backend.yaml",
        "manifests/05-network-policy/observability-client.yaml",
        "manifests/05-network-policy/frontend-client-denied.yaml",
        "manifests/05-network-policy/frontend-client-allowed.yaml",
        "manifests/05-network-policy/backend-api-service.yaml",
        "manifests/05-network-policy/backend-api-deployment.yaml",
        "manifests/04-registry-auth/deployment-with-imagepullsecret-example.yaml",
        "manifests/04-registry-auth/registry-secret-example.yaml",
        "manifests/03-rbac/admin-clusterrolebinding-demo.yaml",
        "manifests/03-rbac/kube-board-readonly-demo.yaml",
        "manifests/03-rbac/restricted-rolebinding.yaml",
        "manifests/03-rbac/restricted-role.yaml",
        "manifests/03-rbac/readonly-rolebinding.yaml",
        "manifests/03-rbac/readonly-role.yaml",
        "manifests/02-service-account/serviceaccount-token-secret-demo.yaml",
        "manifests/02-service-account/pod-reader-serviceaccount.yaml",
        "manifests/02-service-account/app-serviceaccount.yaml",
        "manifests/01-security-context/pod-insecure-example.yaml",
        "manifests/01-security-context/pod-secure-example.yaml",
        "manifests/01-security-context/app-secure-service.yaml",
        "manifests/01-security-context/app-secure-deployment.yaml",
        "manifests/06-admission/restricted-namespace-example.yaml",
        "manifests/00-namespaces/namespace-insecure-demo.yaml",
        "manifests/00-namespaces/namespace-observability.yaml",
        "manifests/00-namespaces/namespace-backend.yaml",
        "manifests/00-namespaces/namespace-frontend.yaml",
        "manifests/00-namespaces/namespace-security-lab.yaml"
    )

    foreach ($file in $files) {
        Remove-ManifestIfExists -RelativePath $file
    }

    Write-Host "[OK] Recursos do laboratorio removidos (quando existentes)."
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
            "Para evitar remocoes no cluster errado, use o contexto '$ExpectedContext'.",
            "Comando sugerido: kubectl config use-context $ExpectedContext",
            "Se voce realmente quiser ignorar essa protecao, use ALLOW_NON_LAB_CONTEXT=true."
        ) -join " "
    }
}

if ($ManifestsOnly -and $DeleteCluster) {
    throw "Use apenas uma opcao: -ManifestsOnly ou -DeleteCluster."
}

if (-not $ManifestsOnly -and -not $DeleteCluster) {
    $choice = Read-Host "Limpar tambem o cluster '$clusterName'? (y/N)"
    if ($choice -match '^(y|yes)$') {
        $DeleteCluster = $true
    }
    else {
        $ManifestsOnly = $true
    }
}

Require-Command -Name "kubectl"
Require-LabContext -ExpectedContext $labContext
Remove-LabManifests

if ($DeleteCluster) {
    Require-Command -Name "kind"
    $clusters = @(kind get clusters)
    if ($clusters -contains $clusterName) {
        $confirm = Read-Host "Confirmar remocao do cluster '$clusterName'? Digite DELETE_CLUSTER para confirmar"
        if ($confirm -eq "DELETE_CLUSTER") {
            Write-Host "[INFO] Removendo cluster $clusterName..."
            & kind delete cluster --name $clusterName
            if ($LASTEXITCODE -ne 0) {
                throw "Falha ao remover cluster $clusterName."
            }
            Write-Host "[OK] Cluster $clusterName removido."
        }
        else {
            Write-Host "[INFO] Confirmacao nao fornecida. Cluster mantido."
        }
    }
    else {
        Write-Host "[INFO] Cluster $clusterName nao existe. Nada a remover no kind."
    }
}
else {
    Write-Host "[INFO] Modo manifests-only: cluster nao foi removido."
    Write-Host "[INFO] Para remover tambem o cluster, execute:"
    Write-Host "  .\\scripts\\cleanup.ps1 -DeleteCluster"
}
