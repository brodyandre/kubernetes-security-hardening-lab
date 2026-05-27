# 04 - NetworkPolicy

## Conceito principal
`NetworkPolicy` controla tráfego entre Pods no plano de rede do cluster.

Conceitos-chave:

- `default deny`: estratégia de bloquear por padrão e liberar apenas o necessário.
- `podSelector`: seleciona quais Pods a política protege no namespace atual.
- `namespaceSelector`: seleciona namespaces com base em labels.
- `ingress`: define quem pode entrar no Pod.
- `egress`: define para onde o Pod pode sair.

## Por que isso importa em segurança
- Evita comunicação lateral não autorizada entre serviços.
- Limita impacto de comprometimento de um Pod.
- Ajuda a implementar segmentação por domínio (frontend, backend, observabilidade).
- É camada essencial de defesa em profundidade junto com RBAC e SecurityContext.

## Como foi implementado neste laboratório
- Workloads de teste:
  - `manifests/05-network-policy/backend-api-deployment.yaml`
  - `manifests/05-network-policy/backend-api-service.yaml`
  - `manifests/05-network-policy/frontend-client-allowed.yaml`
  - `manifests/05-network-policy/frontend-client-denied.yaml`
  - `manifests/05-network-policy/observability-client.yaml`
- Policies:
  - `manifests/05-network-policy/default-deny-backend.yaml`
  - `manifests/05-network-policy/allow-frontend-to-backend-api.yaml`
  - `manifests/05-network-policy/allow-observability-to-backend-api.yaml`
  - `manifests/05-network-policy/allow-dns-egress.yaml`
- Regras aplicadas:
  - `backend-api` (namespace `security-backend`) recebe `default deny ingress`.
  - Apenas Pods com `access=allowed` em `security-frontend` acessam backend.
  - Namespace `security-observability` pode acessar backend (simulação de monitoramento).
  - Egress DNS liberado para CoreDNS (porta 53 UDP/TCP).
- Infra de rede:
  - cluster kind criado com CNI padrão desabilitado e Calico instalado (`scripts/setup.*`).
  - sem CNI compatível, as policies podem ser aceitas pela API, mas não aplicadas no dataplane.

## Comandos kubectl úteis
```bash
# Aplicar cenário
kubectl apply -f manifests/05-network-policy/

# Inspecionar policies
kubectl -n security-backend get networkpolicy
kubectl -n security-backend describe networkpolicy default-deny-backend

# Testes de conectividade (permitido e bloqueado)
kubectl -n security-frontend exec pod/frontend-client-allowed -- \
  sh -c "curl -fsS --max-time 5 http://backend-api.security-backend.svc.cluster.local:8080/health"

kubectl -n security-frontend exec pod/frontend-client-denied -- \
  sh -c "curl -fsS --max-time 5 http://backend-api.security-backend.svc.cluster.local:8080/health"

kubectl -n security-observability exec pod/observability-client -- \
  sh -c "curl -fsS --max-time 5 http://backend-api.security-backend.svc.cluster.local:8080/health"
```

## Resultado esperado
- `frontend-client-allowed` consegue acessar `backend-api`.
- `frontend-client-denied` não consegue acessar `backend-api`.
- `observability-client` consegue acessar `backend-api`.
- Backend mantém isolamento padrão para fontes não permitidas.

## Erros comuns
- CNI sem suporte a NetworkPolicy (política criada, mas sem efeito).
- Namespace sem labels esperados para `namespaceSelector`.
- Esquecer que `podSelector` atua apenas dentro do namespace da policy.
- Definir somente ingress e esquecer egress necessário (ex.: DNS).
- Testar conectividade sem aguardar Pods `Ready`.

## Como isso se conecta com ambientes reais de produção
- Segmentação por namespace/domínio é prática padrão em plataformas multi-times.
- Políticas de rede reduzem blast radius em incidentes.
- Regras de DNS e dependências externas devem ser modeladas explicitamente.
- Este mesmo padrão é aplicável em clusters gerenciados, desde que o CNI seja compatível.
