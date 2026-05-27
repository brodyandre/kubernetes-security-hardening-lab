# 03 - RBAC

## Conceito principal
RBAC (Role-Based Access Control) define **o que** cada identidade pode fazer na API Kubernetes.

Elementos principais:

- `Role`: permissões com escopo de namespace.
- `ClusterRole`: permissões em escopo de cluster (ou reutilizável via RoleBinding).
- `RoleBinding`: liga um `Role` (ou `ClusterRole`) a usuários, grupos ou ServiceAccounts em um namespace.
- `ClusterRoleBinding`: liga permissões em escopo cluster-wide.
- Menor privilégio: conceder apenas verbos e recursos estritamente necessários.

## Por que isso importa em segurança
- Limita dano em caso de token comprometido.
- Evita escalonamento de privilégio acidental.
- Melhora rastreabilidade e auditoria de acessos.
- Reduz risco operacional causado por permissões excessivas.

## Como foi implementado neste laboratório
- Manifestos de acesso restrito:
  - `manifests/03-rbac/readonly-role.yaml`
  - `manifests/03-rbac/readonly-rolebinding.yaml`
  - `manifests/03-rbac/restricted-role.yaml`
  - `manifests/03-rbac/restricted-rolebinding.yaml`
  - `manifests/03-rbac/kube-board-readonly-demo.yaml`
- Exemplo didático de risco (fora do fluxo padrão):
  - `manifests/03-rbac/admin-clusterrolebinding-demo.yaml`
- Cenários:
  - `pod-reader-sa` com leitura de pods (`get/list/watch`).
  - `app-restricted-sa` com leitura de pods e services (`get/list`).
  - `kube-board-sa` com leitura de recursos de observação (pods/services/deployments/replicasets).
  - `cluster-admin` apenas para demonstração de risco, não recomendado para produção.

## Comandos kubectl úteis
```bash
# Aplicar RBAC seguro
kubectl apply -f manifests/03-rbac/readonly-role.yaml
kubectl apply -f manifests/03-rbac/readonly-rolebinding.yaml
kubectl apply -f manifests/03-rbac/restricted-role.yaml
kubectl apply -f manifests/03-rbac/restricted-rolebinding.yaml
kubectl apply -f manifests/03-rbac/kube-board-readonly-demo.yaml

# Verificar o que a conta pod-reader-sa pode ou não pode fazer
kubectl auth can-i list pods \
  --as=system:serviceaccount:k8s-security-lab:pod-reader-sa \
  -n k8s-security-lab

kubectl auth can-i delete pods \
  --as=system:serviceaccount:k8s-security-lab:pod-reader-sa \
  -n k8s-security-lab

# Consultar RBAC criado
kubectl -n k8s-security-lab get role,rolebinding,sa
kubectl get clusterrolebinding demo-cluster-admin-binding
```

## Resultado esperado
- `pod-reader-sa` consegue listar pods, mas não consegue deletar pods.
- `app-restricted-sa` consulta pods/services sem capacidade de escrita.
- `kube-board-sa` consegue observabilidade básica sem poderes administrativos.
- `demo-cluster-admin-binding` fica isolado como exemplo de alto risco.

## Erros comuns
- Criar `RoleBinding` no namespace errado.
- Referenciar ServiceAccount sem namespace correto.
- Conceder `verbs: ["*"]` por conveniência.
- Usar `ClusterRoleBinding` quando um `RoleBinding` já resolveria.
- Não validar permissões com `kubectl auth can-i`.

## Como isso se conecta com ambientes reais de produção
- RBAC é base de segregação de funções em times de plataforma, dados e desenvolvimento.
- Perfis de leitura/execução/admin devem ser definidos por contexto de operação.
- `cluster-admin` deve ser restrito a poucos operadores e, idealmente, com acesso temporário.
- Revisão periódica de permissões e trilhas de auditoria é prática obrigatória de segurança.
