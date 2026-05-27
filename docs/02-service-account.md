# 02 - ServiceAccount

## Conceito principal
`ServiceAccount` é a identidade nativa de workloads no Kubernetes (Pods, Deployments, Jobs). Ela não representa uma pessoa: representa uma aplicação rodando no cluster.

Conceitos-chave deste módulo:

- `ServiceAccount`: identidade da aplicação para autenticar na API Kubernetes.
- `automountServiceAccountToken`: controla montagem automática do token no pod.
- Token de ServiceAccount: credencial usada pela aplicação para falar com a API.
- `imagePullSecret`: credencial para autenticar em registry privado ao baixar imagens.
- Diferença entre identidade de app e usuário humano:
  - usuário humano é autenticado por mecanismos externos (OIDC, certificados, IAM);
  - aplicação usa `ServiceAccount` e permissões RBAC associadas.

## Por que isso importa em segurança
- Evita uso indevido da conta default do namespace.
- Reduz exposição de token quando a aplicação não precisa acessar a API.
- Permite separar permissões por workload, com rastreabilidade de acesso.
- Garante autenticação segura para pull de imagens privadas sem embutir senha em código.

## Como foi implementado neste laboratório
- Manifestos de ServiceAccount:
  - `manifests/02-service-account/app-serviceaccount.yaml`
  - `manifests/02-service-account/pod-reader-serviceaccount.yaml`
  - `manifests/02-service-account/serviceaccount-token-secret-demo.yaml`
- `app-secure-sa` usa `automountServiceAccountToken: false`, pois a aplicação web não precisa falar com a API Kubernetes.
- `pod-reader-sa` é usado nos testes RBAC para leitura limitada de Pods.
- Foi incluído um `Secret` didático do tipo `kubernetes.io/service-account-token` para estudo de compatibilidade.
- Cenário de `imagePullSecret` está em:
  - `manifests/04-registry-auth/registry-secret-example.yaml`
  - `manifests/04-registry-auth/deployment-with-imagepullsecret-example.yaml`

## Comandos kubectl úteis
```bash
# Aplicar ServiceAccounts
kubectl apply -f manifests/02-service-account/

# Inspecionar contas e tokens
kubectl -n k8s-security-lab get sa
kubectl -n k8s-security-lab describe sa app-secure-sa
kubectl -n k8s-security-lab describe sa pod-reader-sa
kubectl -n k8s-security-lab get secret pod-reader-sa-token-demo -o yaml

# Gerar token temporário (abordagem recomendada em clusters modernos)
kubectl create token pod-reader-sa -n k8s-security-lab

# Exemplo de criação de secret para registry privado (não usar credenciais reais no Git)
kubectl create secret docker-registry registry-credentials \
  --docker-server=SEU_REGISTRY \
  --docker-username=SEU_USUARIO \
  --docker-password=SUA_SENHA \
  --docker-email=SEU_EMAIL \
  -n k8s-security-lab
```

## Resultado esperado
- `app-secure-sa` sem token montado automaticamente no pod da aplicação.
- `pod-reader-sa` disponível para cenários de leitura com RBAC.
- Secret didático criado sem credencial real.
- Fluxo de autenticação de image pull documentado para uso com registry privado.

## Erros comuns
- Usar a `default` ServiceAccount em todos os workloads.
- Montar token automaticamente em aplicações que não chamam a API.
- Conceder permissões amplas para uma única ServiceAccount compartilhada.
- Versionar credenciais reais de registry em arquivos YAML.
- Assumir que ServiceAccount substitui autenticação de usuário humano.

## Como isso se conecta com ambientes reais de produção
- Em produção, cada workload crítico deve ter ServiceAccount dedicada.
- O padrão recomendado é token temporário (`TokenRequest`) e RBAC mínimo.
- `imagePullSecrets` normalmente é integrado com secret managers e rotação de credenciais.
- Separar identidade de aplicação da identidade humana é requisito base de governança e auditoria.
