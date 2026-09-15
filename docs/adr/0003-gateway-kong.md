# ADR 0003 — Kong como API Gateway (DB-backed) + Konga, via Terraform

- **Status:** Aceita (revisada)
- **Data:** Fase 3 (extra)

## Contexto
O ponto de entrada inicial do cluster era o **Ingress NGINX** (roteamento + `limit-rps`). As aulas
da fase ensinam o **Kong** como API Gateway, operado pela GUI **Konga** (criação de Serviços, Rotas
e Consumers). Para aproximar a entrega do que o curso ensina — e ter um ambiente pronto para
**demonstração em vídeo** — decidimos subir o Kong no modo em que a GUI funciona de verdade.

## Decisão
Provisionar o **Kong em modo DB-backed** e a GUI **Konga**, **inteiramente por Terraform**
([`kong.tf`](../../kong.tf)), ativados por `enable_kong = true`. Um único `terraform apply` cria, no
namespace `kong`:

1. **PostgreSQL dedicado ao Kong** (StatefulSet + Service + Secret) — isolado do banco da aplicação
   (que é gerenciado no Railway). O Kong precisa de banco próprio para o modo DB-backed e para a
   Konga poder ler/editar a configuração.
2. **Kong** via provider `helm` (chart oficial `kong/kong`), com `database=postgres`, **Admin API**
   HTTP (`kong-kong-admin:8001`), migrations automáticas e **proxy em NodePort `32080`**. O Ingress
   Controller é desabilitado (`ingressController=false`), pois a config é declarada via Admin API.
3. **Job de configuração** (imagem `curlimages/curl`) que aplica, de forma idempotente (PUT), a
   **Service** `fiap-app` (upstream `fiap-app.oficina.svc.cluster.local:80`), a **Route** `/` e o
   plugin **rate-limiting** (`kong_rate_limit_per_minute`, padrão 1200/min).
4. **Konga** (`pantsel/konga`) apontando para a Admin API — **NodePort `31337`** — permitindo
   inspecionar/editar Serviços, Rotas e Consumers pela interface gráfica.

O **Ingress NGINX permanece disponível** (`enable_ingress`), então os dois gateways coexistem e a
mudança é reversível. A validação do **JWT continua na aplicação** (o gateway encaminha o header
`Authorization`).

## Arquitetura resultante
- **Railway (nuvem gerenciada):** Postgres da aplicação + serviço de autenticação (`fiap-auth`,
  CPF→JWT, serverless).
- **Kubernetes local:** a **API .NET** (Deployment + HPA) atrás do **Kong** (DB-backed), com a
  **Konga** e o **Kong Manager** como GUIs. O Kong roteia para a API e aplica rate-limiting; a API
  valida o JWT emitido pela auth.

## Consequências
- (+) `terraform apply` deixa **gateway + GUI prontos**, sem passos manuais — ideal para a demo.
- (+) Konga **funcional** (DB-backed), como no curso; Kong Manager também disponível.
- (+) Config do gateway versionada/reproduzível (Job idempotente).
- (−) Componentes a mais para operar (Kong + Postgres do Kong + Konga) que o NGINX simples.
- (−) O chart do Kong é instalado pelo provider `helm` — exige o provider configurado (já incluso
  em `versions.tf`). O repositório do chart é acessado em tempo de `apply`.

## Como validar
```bash
# proxy do gateway
kubectl port-forward -n kong svc/kong-kong-proxy 18080:80
curl -i http://localhost:18080/health/ready        # 200 + Via: kong + X-RateLimit-*
curl -o /dev/null -w "%{http_code}" http://localhost:18080/api/ordens-servico   # 401 sem token

# GUIs
kubectl port-forward -n kong svc/konga 31337:1337              # Konga  -> http://localhost:31337
kubectl port-forward -n kong svc/kong-kong-manager 8002:8002   # Kong Manager
```
