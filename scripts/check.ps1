Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $repoRoot

$labNamespace = "k8s-security-lab"
$backendNamespace = "security-backend"
$frontendNamespace = "security-frontend"
$observabilityNamespace = "security-observability"
$appBaseUrl = "http://127.0.0.1:18080"
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

function Run-Step {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Number,
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    Write-Host ""
    Write-Host "[$Number/10] $Title"
}

function Assert-CanI {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [ValidateSet("yes", "no")]
        [string]$Expected,
        [Parameter(Mandatory = $true)]
        [string[]]$CanIArgs
    )

    $result = (& kubectl auth can-i @CanIArgs).Trim().ToLowerInvariant()
    Write-Host "  $Description : $result (esperado: $Expected)"
    if ($result -ne $Expected) {
        throw "Resultado inesperado para: $Description"
    }
}

function Test-NetworkPolicyAccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [Parameter(Mandatory = $true)]
        [string]$PodName,
        [Parameter(Mandatory = $true)]
        [ValidateSet("allow", "deny")]
        [string]$Expected
    )

    $url = "http://backend-api.security-backend.svc.cluster.local:8080/health"
    & kubectl -n $Namespace exec "pod/$PodName" -- sh -c "curl -fsS --max-time 5 $url >/dev/null"
    $actual = if ($LASTEXITCODE -eq 0) { "allow" } else { "deny" }

    Write-Host "  $Namespace/$PodName : $actual (esperado: $Expected)"
    if ($actual -ne $Expected) {
        throw "Validacao de NetworkPolicy falhou para $Namespace/$PodName."
    }
}

function Start-PortForward {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [Parameter(Mandatory = $true)]
        [string]$PortMap
    )

    $stdoutFile = Join-Path $env:TEMP "k8s-security-lab-portforward.out.log"
    $stderrFile = Join-Path $env:TEMP "k8s-security-lab-portforward.err.log"

    if (Test-Path $stdoutFile) { Remove-Item -Force $stdoutFile }
    if (Test-Path $stderrFile) { Remove-Item -Force $stderrFile }

    $argList = @("-n", $Namespace, "port-forward", $Target, $PortMap, "--address", "127.0.0.1")
    $process = Start-Process `
        -FilePath "kubectl" `
        -ArgumentList $argList `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -PassThru

    return @{
        Process = $process
        StdOut = $stdoutFile
        StdErr = $stderrFile
    }
}

function Wait-HttpReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 2 | Out-Null
            return
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "Timeout aguardando endpoint local: $Url"
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
            "Para evitar testes no cluster errado, use o contexto '$ExpectedContext'.",
            "Comando sugerido: kubectl config use-context $ExpectedContext",
            "Se voce realmente quiser ignorar essa protecao, use ALLOW_NON_LAB_CONTEXT=true."
        ) -join " "
    }
}

Require-Command -Name "kubectl"
Require-LabContext -ExpectedContext $labContext

Run-Step -Number 1 -Title "kubectl get nodes"
& kubectl get nodes

Run-Step -Number 2 -Title "kubectl get ns"
& kubectl get ns

Run-Step -Number 3 -Title "kubectl get pods -A"
& kubectl get pods -A

Run-Step -Number 4 -Title "kubectl get deploy,svc -n k8s-security-lab"
& kubectl get deploy,svc -n $labNamespace

Run-Step -Number 5 -Title "RBAC: pod-reader-sa pode listar pods"
Assert-CanI -Description "pod-reader-sa list pods" -Expected "yes" -CanIArgs @(
    "list", "pods",
    "--as=system:serviceaccount:k8s-security-lab:pod-reader-sa",
    "-n", "k8s-security-lab"
)

Run-Step -Number 6 -Title "RBAC: pod-reader-sa NAO pode deletar pods"
Assert-CanI -Description "pod-reader-sa delete pods" -Expected "no" -CanIArgs @(
    "delete", "pods",
    "--as=system:serviceaccount:k8s-security-lab:pod-reader-sa",
    "-n", "k8s-security-lab"
)

Run-Step -Number 7 -Title "Endpoint /security via port-forward"
& kubectl -n $labNamespace rollout status deployment/security-lab-app --timeout=240s
if ($LASTEXITCODE -ne 0) { throw "Falha ao aguardar deployment/security-lab-app." }

$pf = Start-PortForward -Namespace $labNamespace -Target "svc/security-lab-app" -PortMap "18080:8080"
try {
    Wait-HttpReady -Url "$appBaseUrl/health" -TimeoutSeconds 30
    $security = Invoke-RestMethod -Uri "$appBaseUrl/security" -Method Get -TimeoutSec 10
    $security | ConvertTo-Json -Depth 8

    Run-Step -Number 8 -Title "Endpoint /write-test"
    $writeTest = Invoke-RestMethod -Uri "$appBaseUrl/write-test" -Method Get -TimeoutSec 10
    $writeTest | ConvertTo-Json -Depth 8

    $resultsByPath = @{}
    foreach ($item in $writeTest.results) {
        $resultsByPath[$item.path] = [bool]$item.success
    }

    if (-not $resultsByPath.ContainsKey("/data/write-test.txt") -or -not $resultsByPath["/data/write-test.txt"]) {
        throw "/data/write-test.txt deveria ter sucesso."
    }
    if (-not $resultsByPath.ContainsKey("/tmp/tmp-test.txt") -or -not $resultsByPath["/tmp/tmp-test.txt"]) {
        throw "/tmp/tmp-test.txt deveria ter sucesso."
    }
    if (-not $resultsByPath.ContainsKey("/app/blocked-test.txt") -or $resultsByPath["/app/blocked-test.txt"]) {
        throw "/app/blocked-test.txt deveria falhar com readOnlyRootFilesystem."
    }
}
finally {
    if ($pf.Process -and -not $pf.Process.HasExited) {
        Stop-Process -Id $pf.Process.Id -Force
    }
}

Run-Step -Number 9 -Title "NetworkPolicy: acessos permitidos e negados"
& kubectl -n $backendNamespace rollout status deployment/backend-api --timeout=240s
if ($LASTEXITCODE -ne 0) { throw "Falha ao aguardar deployment/backend-api." }

& kubectl -n $frontendNamespace wait --for=condition=Ready pod/frontend-client-allowed --timeout=180s
& kubectl -n $frontendNamespace wait --for=condition=Ready pod/frontend-client-denied --timeout=180s
& kubectl -n $observabilityNamespace wait --for=condition=Ready pod/observability-client --timeout=180s

Test-NetworkPolicyAccess -Namespace $frontendNamespace -PodName "frontend-client-allowed" -Expected "allow"
Test-NetworkPolicyAccess -Namespace $frontendNamespace -PodName "frontend-client-denied" -Expected "deny"
Test-NetworkPolicyAccess -Namespace $observabilityNamespace -PodName "observability-client" -Expected "allow"

Run-Step -Number 10 -Title "Dry-run server do pod-violates-restricted (falha esperada)"
$dryRunOutput = & kubectl apply --dry-run=server -f "manifests/06-admission/pod-violates-restricted.yaml" 2>&1
if ($LASTEXITCODE -eq 0) {
    throw "O dry-run server deveria falhar no namespace restricted."
}

Write-Host "[OK] Falha esperada confirmada."
$dryRunOutput

Write-Host ""
Write-Host "[OK] Validacoes concluidas com sucesso."
