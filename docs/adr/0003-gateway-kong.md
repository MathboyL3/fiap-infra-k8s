# ADR 0003 — Kong como API Gateway

- **Status:** Aceita
- **Data:** Fase 3 (extra)

## Contexto
O ponto de entrada inicial do cluster era o **Ingress NGINX** (roteamento + `limit-rps`). Para um
**API Gateway** mais completo — e para reforçar o requisito de "gateway" do enunciado — avaliamos o
**Kong**, que oferece plugins de rate-limiting, autenticação, transformação, logging e observabilidade
de forma declarativa.

## Decisão
Suportar o **Kong** como gateway do cluster, via **Kong Ingress Controller** (Helm, `kong/ingress`,
modo DB-less). O Terraform ([`kong.tf`](../../kong.tf)) cria, quando `enable_kong = true`:

- um `Ingress` com `ingressClassName: kong` roteando `/` para o `Service fiap-app`;
- um `KongPlugin` de **rate-limiting** (`kong_rate_limit_per_minute`, padrão 1200/min), anexado ao
  Ingress pela annotation `konghq.com/plugins`.

O **Ingress NGINX permanece disponível** (`enable_ingress`), então os dois gateways coexistem e a
migração é reversível. A validação do **JWT continua na aplicação** (ambos os gateways encaminham o
header `Authorization`).

## Arquitetura resultante (com a app no cluster)
- **Railway (nuvem gerenciada):** Postgres + serviço de autenticação (`fiap-auth`, CPF→JWT).
- **Kubernetes local:** a **API .NET** (Deployment + HPA) atrás do **Kong**, consumindo o banco e
  aceitando o JWT emitido pela auth.

## Consequências
- (+) Gateway com recursos de nível de produção (rate-limiting, plugins, `Via`/`X-Kong-*`, request-id).
- (+) Declarado como IaC (Terraform) e reversível (coexiste com o NGINX).
- (−) Requer o Kong Ingress Controller instalado no cluster (passo de Helm, fora do Terraform).
- (−) Um componente a mais para operar do que o NGINX simples.

## Como validar
```bash
kubectl port-forward -n kong svc/kong-gateway-proxy 18000:80
curl -i http://localhost:18000/health/ready        # 200 + Via: kong + X-RateLimit-*
curl -o /dev/null -w "%{http_code}" http://localhost:18000/api/ordens-servico   # 401 sem token
```
