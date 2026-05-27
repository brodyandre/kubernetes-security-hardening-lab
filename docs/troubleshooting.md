# Troubleshooting

## Conceito principal
Troubleshooting em Kubernetes é o processo de identificar rapidamente a causa raiz de falhas de segurança, rede, identidade e deploy, com comandos reprodutíveis e evidência objetiva.

## Por que isso importa em segurança
- Erros de configuração podem desativar controles críticos sem percepção imediata.
- Diagnóstico rápido reduz janela de exposição em incidentes.
- Operação segura depende de validação contínua, não apenas de configuração inicial.

## Como foi implementado neste laboratório
- Scripts padronizados:
  - `scripts/setup.*` para bootstrap de cluster com Calico.
  - `scripts/apply-all.*` para aplicação segura e idempotente.
  - `scripts/check.*` para validações técnicas automatizadas.
  - `scripts/cleanup.*` para limpeza controlada.
- Este documento cobre os problemas mais prováveis do fluxo local (Windows 11, WSL2/Linux, kind, kubectl).

## Comandos kubectl úteis
```bash
kubectl get nodes
kubectl get ns
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
kubectl describe pod <POD_NAME> -n <NAMESPACE>
kubectl auth can-i <VERB> <RESOURCE> --as=<IDENTIDADE> -n <NAMESPACE>
```

## Resultado esperado
- Resolver falhas de bootstrap, segurança e conectividade sem alterar escopo do laboratório.
- Restabelecer o comportamento esperado dos controles de SecurityContext, RBAC, NetworkPolicy e Admissão.

## Erros comuns
- Diagnosticar sintoma sem coletar eventos.
- Testar policy de rede sem validar labels de namespace/pod.
- Misturar manifests didáticos inseguros no fluxo padrão.
- Assumir problema de aplicação quando a causa é CNI, RBAC ou admissão.

## Como isso se conecta com ambientes reais de produção
- O mesmo método de investigação (evento -> hipótese -> validação) é usado em SRE/DevSecOps.
- Playbooks de troubleshooting são base para operação confiável em clusters críticos.

## Problemas frequentes e resolução

## 1) Pods ficam em `Pending`

### Sintomas
- Pods sem agendamento, normalmente com mensagem de recursos insuficientes ou constraints não atendidas.

### Verificações
```bash
kubectl get pods -A
kubectl describe pod <POD_NAME> -n <NAMESPACE>
kubectl get nodes -o wide
```

### Ação
- Validar se os nós do kind estão `Ready`.
- Confirmar se não há restrições extras de scheduling (`nodeSelector`, `tolerations`, `affinity`).
- Em ambiente local, reduzir requests/limits ou aumentar recursos do Docker Desktop.

## 2) Calico não sobe

### Sintomas
- Pods `calico-node` ou `calico-kube-controllers` em `CrashLoopBackOff`/`Pending`.
- NetworkPolicy não tem efeito.

### Verificações
```bash
kubectl -n kube-system get pods -o wide
kubectl -n kube-system logs ds/calico-node --tail=150
kubectl -n kube-system logs deploy/calico-kube-controllers --tail=150
```

### Ação
- Garantir que o cluster foi criado com `kind/cluster-calico.yaml` (`disableDefaultCNI: true` e `podSubnet` compatível).
- Reexecutar `scripts/setup.sh` ou `scripts/setup.ps1` para reinstalar Calico de forma padronizada.

## 3) NetworkPolicy não bloqueia

### Sintomas
- `frontend-client-denied` consegue acessar `backend-api` quando deveria falhar.

### Verificações
```bash
kubectl -n security-backend get networkpolicy
kubectl -n security-backend describe networkpolicy default-deny-backend
kubectl get ns --show-labels
kubectl -n security-frontend get pod --show-labels
```

### Ação
- Confirmar labels esperados:
  - namespace `security-frontend` com `name=security-frontend`
  - namespace `security-observability` com `name=security-observability`
  - pod permitido com `access=allowed`
  - pod negado com `access=denied`
- Confirmar que o CNI suporta NetworkPolicy (Calico ativo).
- Executar `scripts/check.sh` ou `scripts/check.ps1` para validação completa.

## 4) Imagem local não encontrada no kind

### Sintomas
- Pods em `ImagePullBackOff` ou `ErrImagePull` para imagens locais.

### Verificações
```bash
kubectl describe pod <POD_NAME> -n <NAMESPACE>
docker images | grep kubernetes-security-hardening-lab
```

### Ação
- Construir imagem local:
```bash
docker build -t brodyandre/kubernetes-security-hardening-lab:latest ./app
```
- Carregar imagem no cluster kind:
```bash
kind load docker-image brodyandre/kubernetes-security-hardening-lab:latest --name k8s-security-lab
```
- Em ambientes com registry privado, configurar `imagePullSecret` real antes de escalar deployment.

## 5) Erro de permissão no volume

### Sintomas
- Falha de escrita em `/data` ou `/tmp`.
- Endpoint `/write-test` retorna erro inesperado para diretórios que deveriam ser graváveis.

### Verificações
```bash
kubectl -n k8s-security-lab exec deploy/security-lab-app -- id
kubectl -n k8s-security-lab get pod -l app=security-lab-app -o yaml
```

### Ação
- Validar `runAsUser`, `runAsGroup` e `fsGroup` no pod.
- Confirmar `emptyDir` montado em `/data` e `/tmp`.
- Garantir que `readOnlyRootFilesystem` está ativo para bloquear apenas `/app`, não os volumes dedicados.

## 6) ServiceAccount sem permissão

### Sintomas
- `kubectl auth can-i` retorna `no` para operação esperada.
- Aplicação autenticada com SA não consegue ler recursos permitidos.

### Verificações
```bash
kubectl -n k8s-security-lab get sa
kubectl -n k8s-security-lab get role,rolebinding
kubectl auth can-i list pods \
  --as=system:serviceaccount:k8s-security-lab:pod-reader-sa \
  -n k8s-security-lab
```

### Ação
- Confirmar se `RoleBinding` referencia o `Role` e a SA corretos no mesmo namespace.
- Evitar usar `ClusterRoleBinding` para casos namespace-scoped.
- Reaplicar manifests RBAC seguros:
```bash
kubectl apply -f manifests/03-rbac/readonly-role.yaml
kubectl apply -f manifests/03-rbac/readonly-rolebinding.yaml
```

## 7) GitHub Actions falhando em YAML

### Sintomas
- Workflow `Validate Kubernetes YAML` falha em `yamllint`, `kubeconform` ou `trivy config`.

### Verificações
```bash
# Lint local
yamllint manifests kind app .github/workflows

# Schema validation local (se kubeconform instalado)
kubeconform -summary -strict -ignore-missing-schemas $(find manifests app -name "*.yaml" -o -name "*.yml")
```

### Ação
- Corrigir indentação/chaves/tipos YAML reportados no job de lint.
- Ajustar campos inválidos de recursos Kubernetes reportados pelo kubeconform.
- Se o arquivo é didático e intencionalmente inseguro, documentar e manter em exceção explícita no workflow (como já feito para exemplos de risco).
