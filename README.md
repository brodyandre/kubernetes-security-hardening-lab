# Kubernetes Security Hardening Lab
[![Validate Kubernetes YAML](https://github.com/brodyandre/kubernetes-security-hardening-lab/actions/workflows/validate-kubernetes-yaml.yml/badge.svg)](https://github.com/brodyandre/kubernetes-security-hardening-lab/actions/workflows/validate-kubernetes-yaml.yml)

## 1. Visão geral
Este projeto demonstra práticas reais de segurança em Kubernetes com foco em empregabilidade para posições de DevOps, Engenharia de Dados e Cloud Native. O laboratório foi desenhado para execução local, com cenários práticos de hardening, controle de acesso, isolamento de rede e validação automatizada de manifests.

## 2. Objetivos do projeto
- Executar containers com usuário não-root.
- Aplicar SecurityContext.
- Controlar filesystem com readOnlyRootFilesystem, emptyDir e fsGroup.
- Reduzir Linux Capabilities.
- Usar ServiceAccount de forma segura.
- Demonstrar autenticação, autorização e admissão.
- Aplicar RBAC com menor privilégio.
- Demonstrar risco de permissões amplas.
- Usar imagePullSecrets para registry privado.
- Aplicar NetworkPolicy com restrição por Pod e namespace.
- Validar manifests com GitHub Actions.

## 3. Arquitetura do laboratório
- Mini aplicação FastAPI com endpoints para validar contexto de segurança e comportamento de escrita em filesystem.
- Namespace seguro com Pod Security Admission e segmentação por domínio de segurança.
- ServiceAccounts dedicadas para app e cenários de leitura controlada.
- RBAC com perfis de leitura mínima e exemplos didáticos de risco.
- NetworkPolicies para default deny, liberação por Pod e liberação por namespace.
- Cluster Kind com Calico para suporte completo a NetworkPolicy.
- Scripts de automação para setup, apply, validação e cleanup em PowerShell e Bash.

## 4. Tecnologias utilizadas
- Kubernetes
- kubectl
- kind
- Calico
- Docker
- Python
- FastAPI
- RBAC
- NetworkPolicy
- GitHub Actions
- yamllint
- kubeconform
- Trivy

## 5. Estrutura do repositório
```text
kubernetes-security-hardening-lab/
├─ .github/
│  └─ workflows/
│     └─ validate-kubernetes-yaml.yml
├─ app/
│  ├─ main.py
│  ├─ requirements.txt
│  └─ Dockerfile
├─ kind/
│  ├─ cluster-calico.yaml
│  └─ cluster-config.yaml
├─ manifests/
│  ├─ 00-namespaces/
│  ├─ 01-security-context/
│  ├─ 02-service-account/
│  ├─ 03-rbac/
│  ├─ 04-registry-auth/
│  ├─ 05-network-policy/
│  └─ 06-admission/
├─ scripts/
│  ├─ setup.ps1
│  ├─ setup.sh
│  ├─ apply-all.ps1
│  ├─ apply-all.sh
│  ├─ create-cluster.sh
│  ├─ apply-labs.sh
│  ├─ check.ps1
│  ├─ check.sh
│  ├─ check-network-policy.sh
│  ├─ cleanup.ps1
│  └─ cleanup.sh
├─ docs/
│  ├─ 01-security-context.md
│  ├─ 02-service-account.md
│  ├─ 03-rbac.md
│  ├─ 04-network-policy.md
│  ├─ 05-admission.md
│  ├─ troubleshooting.md
│  └─ evidences/
├─ README.md
├─ LICENSE
└─ .gitignore
```

## 6. Como executar no Windows 11
Pré-requisitos: Docker Desktop, kind e kubectl instalados.

```powershell
# 1) Criar cluster Kind com Calico
.\scripts\setup.ps1

# 2) Aplicar laboratório (somente cenários seguros)
.\scripts\apply-all.ps1

# 3) Executar validações técnicas
.\scripts\check.ps1

# 4) Limpar somente manifests
.\scripts\cleanup.ps1 -ManifestsOnly

# 5) Limpar manifests e cluster (com confirmação)
.\scripts\cleanup.ps1 -DeleteCluster
```

## 7. Como executar no WSL2/Linux
Pré-requisitos: Docker, kind e kubectl instalados.

```bash
# 0) (primeira execução) garantir permissão de execução
chmod +x scripts/*.sh

# 1) Criar cluster Kind com Calico
bash scripts/setup.sh

# 2) Aplicar laboratório (somente cenários seguros)
bash scripts/apply-all.sh

# 3) Executar validações técnicas
bash scripts/check.sh

# 4) Limpar somente manifests
bash scripts/cleanup.sh --manifests-only

# 5) Limpar manifests e cluster (com confirmação)
bash scripts/cleanup.sh --delete-cluster
```

## 8. Demonstrações práticas
### Security Context
- Execução como não-root.
- Root filesystem somente leitura.
- Escrita permitida apenas em `/data` e `/tmp` conforme volumes `emptyDir`.

### ServiceAccount
- `app-secure-sa` com `automountServiceAccountToken: false` para workloads que não acessam API.
- `pod-reader-sa` para cenários de autenticação de workload com RBAC restrito.

### RBAC
- Role de leitura (`get/list/watch`) para Pods.
- Role restrita para leitura de Pods e Services.
- Exemplo didático de `cluster-admin` separado do fluxo padrão.

### NetworkPolicy
- `default deny` no backend.
- Permissão explícita por label de Pod (`access=allowed`) no namespace frontend.
- Permissão por namespace para observability.

### Admission
- Namespace com política `restricted`.
- Pod violador bloqueado em admissão.
- Pod compatível aceito.

## 9. Evidências esperadas
Adicionar prints e saídas de comando em `docs/evidences/`:
- `kubectl get nodes`
- `kubectl get pods -A`
- retorno do endpoint `/security`
- retorno do endpoint `/write-test`
- saída de `kubectl auth can-i`
- teste de NetworkPolicy permitido e bloqueado
- pipeline do GitHub Actions passando

## 10. Boas práticas demonstradas
- Princípio do menor privilégio em RBAC.
- Hardening de containers com SecurityContext.
- Isolamento de tráfego com NetworkPolicy.
- Identidade de workload com ServiceAccount dedicada.
- Controle de admissão com Pod Security Admission.
- Pipeline CI para lint, conformidade de schema e security scan.
- Separação explícita entre exemplos seguros e exemplos didáticos inseguros.

## 11. Pontos de atenção
- Não usar credenciais reais.
- Não usar cluster-admin em produção.
- Não versionar secrets reais.
- NetworkPolicy exige CNI compatível.

## 12. Autor
Luiz André de Souza  
GitHub: [brodyandre](https://github.com/brodyandre)  
LinkedIn: [www.linkedin.com/in/luiz-andre-souza-data-engineer](https://www.linkedin.com/in/luiz-andre-souza-data-engineer)
