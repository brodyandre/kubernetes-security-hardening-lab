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
│  ├─ cleanup.sh
│  ├─ publish-github.ps1
│  └─ publish-github.sh
├─ docs/
│  ├─ 01-security-context.md
│  ├─ 02-service-account.md
│  ├─ 03-rbac.md
│  ├─ 04-network-policy.md
│  ├─ 05-admission.md
│  ├─ troubleshooting.md
│  └─ evidences/
│     └─ screenshots/
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

# 6) Publicar automaticamente no GitHub e acompanhar workflow
.\scripts\publish-github.ps1 -OpenRepoPage
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

# 6) Publicar automaticamente no GitHub e acompanhar workflow
bash scripts/publish-github.sh
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

### 9.1 Índice remissivo das evidências
<a id="indice-remissivo"></a>

1. [01 - Estado dos nós (`kubectl get nodes`)](#ev-01)
2. [02 - Estado dos pods (`kubectl get pods -A`)](#ev-02)
3. [03 - RBAC permitido (`can-i list pods`)](#ev-03)
4. [04 - RBAC negado (`can-i delete pods`)](#ev-04)
5. [05 - Security Context (`GET /security`)](#ev-05)
6. [06 - Teste de escrita (`GET /write-test`)](#ev-06)
7. [07 - NetworkPolicy permitido (frontend allowed)](#ev-07)
8. [08 - NetworkPolicy bloqueado (frontend denied)](#ev-08)
9. [09 - NetworkPolicy permitido (observability allowed)](#ev-09)
10. [10 - Admissão bloqueando pod inseguro (`dry-run=server`)](#ev-10)
11. [11 - GitHub Actions workflow aprovado](#ev-11)

### 9.2 Evidências anexadas

<a id="ev-01"></a>
#### 01 - Estado dos nós (`kubectl get nodes`)
Contexto: validação inicial do cluster Kind com Calico (Seção 6 e Seção 7).

![01 - kubectl get nodes](docs/evidences/screenshots/01-kubectl-get-nodes.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-02"></a>
#### 02 - Estado dos pods (`kubectl get pods -A`)
Contexto: verificação de saúde dos workloads de sistema e do laboratório.

![02 - kubectl get pods -A](docs/evidences/screenshots/02-kubectl-get-pods-all.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-03"></a>
#### 03 - RBAC permitido (`can-i list pods`)
Contexto: demonstração de autorização mínima para `pod-reader-sa` (Seção 8 > RBAC).

![03 - can-i list pods](docs/evidences/screenshots/03-kubectl-auth-can-i-list-pods-yes.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-04"></a>
#### 04 - RBAC negado (`can-i delete pods`)
Contexto: demonstração de operação bloqueada por menor privilégio.

![04 - can-i delete pods](docs/evidences/screenshots/04-kubectl-auth-can-i-delete-pods-no.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-05"></a>
#### 05 - Security Context (`GET /security`)
Contexto: prova de execução não-root, GID, capabilities e token de ServiceAccount desabilitado (Seção 8 > Security Context).

![05 - endpoint security](docs/evidences/screenshots/05-endpoint-security.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-06"></a>
#### 06 - Teste de escrita (`GET /write-test`)
Contexto: validação de `readOnlyRootFilesystem` com escrita permitida em `/data` e `/tmp`, e bloqueada em `/app`.

![06 - endpoint write-test](docs/evidences/screenshots/06-endpoint-write-test.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-07"></a>
#### 07 - NetworkPolicy permitido (frontend allowed)
Contexto: pod permitido (`access=allowed`) acessa o backend com sucesso (Seção 8 > NetworkPolicy).

![07 - networkpolicy frontend allowed](docs/evidences/screenshots/07-networkpolicy-frontend-allowed.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-08"></a>
#### 08 - NetworkPolicy bloqueado (frontend denied)
Contexto: pod negado (`access=denied`) recebe timeout por política de rede.

![08 - networkpolicy frontend denied](docs/evidences/screenshots/08-networkpolicy-frontend-denied.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-09"></a>
#### 09 - NetworkPolicy permitido (observability allowed)
Contexto: namespace de observabilidade autorizado a consultar o backend.

![09 - networkpolicy observability allowed](docs/evidences/screenshots/09-networkpolicy-observability-allowed.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-10"></a>
#### 10 - Admissão bloqueando pod inseguro (`dry-run=server`)
Contexto: Pod Security Admission `restricted` bloqueando workload inseguro antes da persistência (Seção 8 > Admission).

![10 - admission restricted deny](docs/evidences/screenshots/10-admission-dry-run-violates-restricted.png)

[Voltar ao índice remissivo](#indice-remissivo)

<a id="ev-11"></a>
#### 11 - GitHub Actions workflow aprovado
Contexto: validação de qualidade dos manifests (`yamllint`, `kubeconform`, `trivy config`) em pipeline CI.

![11 - github actions validate passed](docs/evidences/screenshots/11-github-actions-validate-passed.png)

[Voltar ao índice remissivo](#indice-remissivo)

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
