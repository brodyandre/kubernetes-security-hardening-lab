# 01 - Security Context

## Conceito principal
`securityContext` define como o processo do container roda no kernel Linux. No laboratório, os principais controles são:

- `runAsUser`: força execução com UID específico (neste caso `10001`).
- `runAsGroup`: define GID primário do processo (neste caso `30001`).
- `fsGroup`: define grupo aplicado aos volumes montados, facilitando escrita segura em disco compartilhado.
- `runAsNonRoot`: impede execução como root, mesmo que a imagem tenha usuário padrão privilegiado.
- `readOnlyRootFilesystem`: torna o filesystem raiz do container somente leitura.
- `allowPrivilegeEscalation: false`: bloqueia elevação de privilégio via binários setuid/setgid.
- `capabilities.drop: ["ALL"]`: remove capacidades Linux extras por padrão.
- `seccompProfile.type: RuntimeDefault`: usa perfil de syscall padrão do runtime para reduzir superfície de ataque.

## Por que isso importa em segurança
- Reduz o impacto de exploração de vulnerabilidades na aplicação.
- Evita containers com privilégios desnecessários (ponto crítico em incidentes reais).
- Diminui risco de movimentação lateral dentro do cluster.
- Aplica o princípio do menor privilégio no nível do processo Linux.

## Como foi implementado neste laboratório
- Manifestos principais:
  - `manifests/01-security-context/app-secure-deployment.yaml`
  - `manifests/01-security-context/pod-secure-example.yaml`
  - `manifests/01-security-context/app-secure-service.yaml`
- O `Deployment` `security-lab-app` roda com:
  - UID/GID não-root (`10001:30001`)
  - `fsGroup: 30001`
  - `readOnlyRootFilesystem: true`
  - `allowPrivilegeEscalation: false`
  - `capabilities.drop: ["ALL"]`
  - `seccompProfile: RuntimeDefault`
- Volumes `emptyDir` são montados em `/data` e `/tmp` para escrita controlada, enquanto `/app` permanece bloqueado para escrita.

## Comandos kubectl úteis
```bash
# Aplicar cenário seguro
kubectl apply -f manifests/00-namespaces/
kubectl apply -f manifests/01-security-context/app-secure-deployment.yaml
kubectl apply -f manifests/01-security-context/app-secure-service.yaml

# Inspecionar contexto de segurança
kubectl -n k8s-security-lab get pod -l app=security-lab-app -o yaml
kubectl -n k8s-security-lab exec deploy/security-lab-app -- id

# Validar endpoints de diagnóstico da aplicação
kubectl -n k8s-security-lab port-forward svc/security-lab-app 18080:8080
curl http://127.0.0.1:18080/security
curl http://127.0.0.1:18080/write-test
```

## Resultado esperado
- Processo principal executando sem root.
- Escrita com sucesso em `/data` e `/tmp`.
- Falha de escrita em `/app` por causa de `readOnlyRootFilesystem`.
- Capacidades efetivas reduzidas quando consultadas em `/proc/self/status`.

## Erros comuns
- Definir `runAsNonRoot: true` com imagem que só inicia como root.
- Ativar `readOnlyRootFilesystem` sem montar diretórios de escrita necessários (`/tmp`, `/data`).
- Omitir `fsGroup` e enfrentar erro de permissão em volume.
- Esquecer `capabilities.drop: ["ALL"]`, mantendo privilégios desnecessários.
- Não validar comportamento real com testes de escrita e inspeção de processo.

## Como isso se conecta com ambientes reais de produção
- É padrão de hardening para workloads em clusters corporativos (AKS, EKS, GKE e on-prem).
- Costuma ser exigido em auditorias de segurança e compliance (CIS, ISO 27001, SOC 2).
- Facilita adoção de políticas de admissão (PSA/Kyverno/Gatekeeper) com baseline consistente.
