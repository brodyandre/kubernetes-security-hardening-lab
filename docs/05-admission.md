# 05 - Admissão (Pod Security Admission)

## Conceito principal
Na API do Kubernetes, o fluxo de decisão ocorre em três etapas:

- **Autenticação (AuthN):** responde “quem é você?”.
- **Autorização (AuthZ):** responde “o que você pode fazer?”.
- **Admissão:** responde “o objeto enviado pode ser aceito?” antes de persistir no etcd.

Neste laboratório, a camada de admissão é demonstrada com **Pod Security Admission (PSA)**.

Perfis PSA utilizados:

- `baseline`: bloqueia configurações claramente perigosas, mantendo compatibilidade maior com workloads legados.
- `restricted`: aplica hardening mais rígido (não-root, redução de privilégios e controles de syscall/capabilities).

## Por que isso importa em segurança
- Bloqueia workloads inseguros antes de entrarem em execução.
- Padroniza baseline de segurança por namespace.
- Reduz dependência de revisão manual de YAML.
- Complementa RBAC e SecurityContext com governança preventiva.

## Como foi implementado neste laboratório
- Manifestos:
  - `manifests/06-admission/restricted-namespace-example.yaml`
  - `manifests/06-admission/pod-violates-restricted.yaml`
  - `manifests/06-admission/pod-compliant-restricted.yaml`
- Namespace `restricted-lab` recebe labels PSA:
  - `pod-security.kubernetes.io/enforce: restricted`
  - `pod-security.kubernetes.io/audit: restricted`
  - `pod-security.kubernetes.io/warn: restricted`
- O namespace `security-insecure-demo` (módulo de namespaces) usa `enforce: baseline`
  para cenários didáticos controlados com menor rigor que `restricted`.
- Pod violador (didático) inclui:
  - `privileged: true`
  - `runAsUser: 0`
  - `allowPrivilegeEscalation: true`
- Pod compatível aplica:
  - `runAsNonRoot: true`
  - `allowPrivilegeEscalation: false`
  - `capabilities.drop: ["ALL"]`
  - `seccompProfile: RuntimeDefault`

Observação: no fluxo padrão (`scripts/apply-all.*`) o pod violador **não** é aplicado automaticamente.

## Comandos kubectl úteis
```bash
# Criar namespace com política restricted
kubectl apply -f manifests/06-admission/restricted-namespace-example.yaml

# Testar objeto violador (falha esperada)
kubectl apply --dry-run=server -f manifests/06-admission/pod-violates-restricted.yaml

# Aplicar objeto compatível (sucesso esperado)
kubectl apply -f manifests/06-admission/pod-compliant-restricted.yaml
kubectl -n restricted-lab get pods

# Inspecionar eventos de rejeição
kubectl -n restricted-lab get events --sort-by=.lastTimestamp
```

## Resultado esperado
- `pod-violates-restricted.yaml` é rejeitado na admissão.
- `pod-compliant-restricted.yaml` é aceito e executa normalmente.
- Eventos mostram o motivo da rejeição com referência às regras do perfil restricted.

## Erros comuns
- Confundir erro de RBAC com bloqueio de admissão.
- Aplicar manifesto em namespace sem labels PSA.
- Assumir que `warn/audit` bloqueiam (quem bloqueia é `enforce`).
- Usar imagens/processos que exigem root em namespace restricted.

## Como isso se conecta com ambientes reais de produção
- PSA é controle nativo e de baixo custo operacional para elevar baseline de segurança.
- Política `restricted` é recomendada para workloads gerais; `baseline` pode ser usada em namespaces legados.
- Em ambientes corporativos, PSA costuma ser combinado com políticas avançadas (Kyverno/Gatekeeper).
- A decisão de admissão documentada em logs facilita auditoria e resposta a incidentes.
