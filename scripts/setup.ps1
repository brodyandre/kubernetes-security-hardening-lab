Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$clusterName = "k8s-security-lab"
$calicoVersion = if ($env:CALICO_VERSION) { $env:CALICO_VERSION } else { "v3.32.0" }
$calicoManifestUrl = "https://raw.githubusercontent.com/projectcalico/calico/$calicoVersion/manifests/calico.yaml"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$kindConfig = Join-Path $repoRoot "kind/cluster-calico.yaml"
$kubeContext = "kind-$clusterName"

function Require-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Comando obrigatorio nao encontrado: $Name"
    }
}

function Wait-KubeSystemRunning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Context,
        [int]$TimeoutSeconds = 600,
        [int]$SleepSeconds = 5
    )

    Write-Host "[INFO] Aguardando pods do kube-system ficarem Running..."
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ($true) {
        $pods = kubectl --context $Context get pods -n kube-system -o json | ConvertFrom-Json
        $notRunning = @($pods.items | Where-Object { $_.status.phase -ne "Running" })

        if ($notRunning.Count -eq 0) {
            Write-Host "[OK] Todos os pods do kube-system estao Running."
            return
        }

        if ((Get-Date) -ge $deadline) {
            Write-Host "[ERRO] Timeout aguardando pods do kube-system Running." -ForegroundColor Red
            $notRunning | ForEach-Object { Write-Host (" - " + $_.metadata.name + " (" + $_.status.phase + ")") }
            throw "Timeout durante inicializacao do kube-system."
        }

        Write-Host "[INFO] Ainda nao Running:"
        $notRunning | ForEach-Object { Write-Host (" - " + $_.metadata.name + " (" + $_.status.phase + ")") }
        Start-Sleep -Seconds $SleepSeconds
    }
}

Write-Host "[INFO] Verificando pre-requisitos..."
Require-Command -Name "kind"
Require-Command -Name "kubectl"
Require-Command -Name "docker"

try {
    docker info *> $null
}
catch {
    throw "Docker nao esta acessivel. Inicie o Docker Desktop e tente novamente."
}

if (-not (Test-Path -LiteralPath $kindConfig)) {
    throw "Arquivo de configuracao nao encontrado: $kindConfig"
}

$existingClusters = @(kind get clusters)
if ($existingClusters -contains $clusterName) {
    Write-Host "[INFO] Cluster $clusterName ja existe. Nenhum cluster sera removido."
}
else {
    Write-Host "[INFO] Criando cluster $clusterName com $kindConfig..."
    kind create cluster --name $clusterName --config $kindConfig --wait 180s
}

Write-Host "[INFO] Definindo contexto kubectl: $kubeContext"
kubectl config use-context $kubeContext | Out-Null

Write-Host "[INFO] Instalando Calico ($calicoVersion) com manifesto oficial..."
kubectl --context $kubeContext apply -f $calicoManifestUrl

Write-Host "[INFO] Aguardando recursos principais do Calico..."
kubectl --context $kubeContext -n kube-system rollout status daemonset/calico-node --timeout=300s
kubectl --context $kubeContext -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s
kubectl --context $kubeContext -n kube-system rollout status deployment/coredns --timeout=300s
kubectl --context $kubeContext -n kube-system rollout status daemonset/kube-proxy --timeout=300s

Wait-KubeSystemRunning -Context $kubeContext

Write-Host "[INFO] Estado final do cluster:"
kubectl --context $kubeContext get nodes
kubectl --context $kubeContext get pods -A

Write-Host ""
Write-Host "[OK] Ambiente pronto para testes de NetworkPolicy com Calico."
Write-Host "[INFO] Comandos uteis:"
Write-Host "  kubectl config use-context $kubeContext"
Write-Host "  kubectl get nodes -o wide"
Write-Host "  kubectl -n kube-system get pods -o wide"
Write-Host "  kubectl get networkpolicy -A"
