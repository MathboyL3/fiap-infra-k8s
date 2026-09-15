# fiap-infra-k8s

Infraestrutura **Kubernetes** escalável (com **HPA**) da aplicação, provisionada via **Terraform**. Um dos 4 repositórios do Tech Challenge — Fase 3 (SOAT/FIAP).

## Parte do sistema (4 repositórios)

| Repositório | Papel |
|---|---|
| [fiap-auth-lambda](https://github.com/MathboyL3/fiap-auth-lambda) | Autenticação por CPF → JWT (Railway Function serverless, Bun) |
| [fiap-app](https://github.com/MathboyL3/fiap-app) | API principal da oficina (.NET / Kubernetes) |
| [fiap-infra-k8s](https://github.com/MathboyL3/fiap-infra-k8s) | Infra do cluster (Terraform) |
| [fiap-infra-db](https://github.com/MathboyL3/fiap-infra-db) | Banco de dados gerenciado (Terraform + Railway) |

> Arquitetura, diagrama de componentes (cloud) e diagramas de sequência:
> [fiap-app/docs/ARQUITETURA.md](https://github.com/MathboyL3/fiap-app/blob/main/docs/ARQUITETURA.md).

## Propósito
Provisionar, de forma versionada (IaC), tudo que a aplicação (`fiap-app`) precisa para rodar no cluster:
namespace, configuração, segredos, **Deployment** escalável, **Service**, **HPA** e o **Kong** como API Gateway de entrada (com **Ingress NGINX** disponível como alternativa). A conexão de dados aponta para o **banco gerenciado** (`fiap-infra-db`, Railway) e a autenticação usa o **mesmo JWT** emitido pelo serviço `fiap-auth`.

## Tecnologias
- **Terraform** (`>= 1.6`) + provider **hashicorp/kubernetes** `~> 2.31`
- **Kubernetes** (Docker Desktop local; portável para EKS/GKE/AKS)
- **HorizontalPodAutoscaler v2** (CPU + memória)
- **Kong** (API Gateway: roteamento + rate-limiting) com **Konga** (GUI); **Ingress NGINX** como alternativa

## Arquitetura

```mermaid
flowchart TB
  User([Cliente / API consumer]) -->|HTTP + Bearer JWT| ING[Gateway (NGINX ou Kong)\ngateway + rate limit]
  ING --> SVC[Service fiap-app\nNodePort 30080]
  SVC --> P1[Pod fiap-app]
  SVC --> P2[Pod fiap-app]
  HPA[[HPA v2\nmin 2 / max 6\ncpu 60% • mem 75%]] -. escala .-> DEP[Deployment fiap-app]
  DEP --- P1
  DEP --- P2
  P1 -->|Npgsql + SSL| DB[(Postgres gerenciado\nRailway — fiap-infra-db)]
  P1 -. valida JWT .-> JWT{{JWT HS256\nOficina.Api}}
  subgraph ns["namespace: oficina"]
    ING; SVC; DEP; P1; P2; HPA
    CM[ConfigMap oficina-config]
    SEC[Secret oficina-secrets\nJwt__Secret / Postgres__Password]
  end
  CM -. envFrom .-> P1
  SEC -. env .-> P1
```

## Recursos provisionados
| Recurso | Detalhe |
|---|---|
| Namespace | `oficina` |
| ConfigMap | `oficina-config` (issuer/audience, host/porta do banco) |
| Secret | `oficina-secrets` (`Jwt__Secret`, `Postgres__Password`, `Webhook__Secret`) |
| Deployment | `fiap-app` — 2 réplicas, probes `/health/live` e `/health/ready`, requests/limits |
| Service | `fiap-app` — NodePort `30080` |
| HPA v2 | min 2 / max 6, CPU 60% + memória 75%, políticas de scale up/down |
| Ingress | `fiap-app` (classe `nginx`) — gateway de entrada + `limit-rps` |
| **Kong (gateway)** | com `enable_kong=true`: Kong DB-backed (Helm) + Postgres dedicado + rota/rate-limiting + **Konga (GUI)** |

## Gateway: NGINX ou Kong (com Konga)

O ponto de entrada pode ser o **Ingress NGINX** (padrão) ou o **Kong** — um API Gateway completo,
provisionado **inteiramente por Terraform** e pronto para demonstração.

Com `enable_kong = true`, um único `terraform apply` sobe (namespace `kong`):

- um **PostgreSQL dedicado** ao Kong (StatefulSet + Service + Secret);
- o **Kong** em modo **DB-backed** (chart oficial `kong/kong` via provider `helm`), com Admin API
  HTTP e migrations automáticas — o proxy é exposto via **NodePort `32080`**;
- um **Job de configuração** que cria, pela Admin API, a **Service** `fiap-app`
  (upstream = `fiap-app.oficina.svc.cluster.local`), a **Route** `/` e o plugin
  **rate-limiting** (`kong_rate_limit_per_minute`, padrão 1200/min);
- o **Konga** — a GUI open source do Kong (das aulas) — apontando para a Admin API
  (`http://kong-kong-admin:8001`), exposto via **NodePort `31337`**.

```bash
# habilita e sobe tudo (Kong + Postgres + config + Konga)
terraform apply -var="enable_kong=true"   -var="jwt_secret=<segredo>" -var="postgres_password=<senha-do-postgres-railway>"
```

Acessos para a demonstração (via `port-forward` ou NodePort):

```bash
# Proxy do gateway (roteia para a API)
kubectl port-forward -n kong svc/kong-kong-proxy 18080:80
curl -i http://localhost:18080/health/ready      # 200; resposta traz Via: kong e X-RateLimit-*

# Konga (GUI do curso) — conecta sozinho na Admin API
kubectl port-forward -n kong svc/konga 31337:1337   # abrir http://localhost:31337

# Kong Manager (GUI oficial que já vem no chart)
kubectl port-forward -n kong svc/kong-kong-manager 8002:8002
```

O gateway encaminha o header `Authorization` ao backend; a validação do JWT é feita pela
aplicação. Ver [`docs/adr/0003-gateway-kong.md`](docs/adr/0003-gateway-kong.md).

## Proteção de rotas por JWT
O **gateway** (Kong; ou o Ingress NGINX) é o ponto de entrada e encaminha o header `Authorization: Bearer <jwt>` ao backend. A **aplicação** valida o token (HS256, `iss/aud=Oficina.Api`, mesmo secret do serviço de autenticação) e aplica autorização por rota/role — rotas sensíveis exigem token; o endpoint público de acompanhamento permanece aberto. Ver `docs/adr/0002`.

## Pré-requisitos
- **Terraform ≥ 1.6**, **kubectl**
- Cluster Kubernetes (Docker Desktop com Kubernetes habilitado)
- **metrics-server** (para o HPA): já presente no Docker Desktop
- **ingress-nginx**:
  ```bash
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
  kubectl wait -n ingress-nginx --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller --timeout=120s
  ```

## Execução / Deploy
```bash
# Segredos (NÃO versionar). jwt_secret IGUAL ao do serviço de autenticação (fiap-auth) e da app.
export TF_VAR_jwt_secret="<segredo-hs256-32+>"
export TF_VAR_postgres_password="<senha-do-postgres-railway>"

terraform init
terraform fmt -check -recursive
terraform validate
terraform apply            # cria namespace, deployment, service, HPA, ingress
```
Acesso local:
```bash
kubectl port-forward -n oficina svc/fiap-app 8080:80   # http://localhost:8080
# ou via Ingress: http://localhost/  (com o controller ingress-nginx)
```

> **Nota:** os pods só ficam `Ready` quando a imagem `fiap-app:local` existir — ela é construída no repositório **fiap-app** (Fase 4). Antes disso os pods ficam em `ImagePullBackOff`, mas toda a infra (incl. HPA) é criada normalmente.

## CI/CD
`.github/workflows/terraform.yml`: em PR/push roda `fmt -check`, `init`, `validate`.
O `apply` roda contra um cluster **local** (Docker Desktop), que os runners hospedados do GitHub não têm — por isso é manual/local. Para nuvem (EKS/GKE/AKS), configure credenciais como secrets e habilite um job de apply (self-hosted/cloud).


## Observabilidade (New Relic)
A license key do New Relic é provisionada como Secret e injetada como `NEW_RELIC_LICENSE_KEY` no Deployment (habilita o agent APM embutido na imagem):
```bash
export TF_VAR_newrelic_license_key="<ingest-license-key>"
terraform apply
```
Para métricas de infra do cluster (CPU/mem dos pods) e logs, instale o `nri-bundle` (Helm) — ver `fiap-app/observability/README.md`.

## Documentação
- [`docs/adr/0001-hpa-escalabilidade.md`](docs/adr/0001-hpa-escalabilidade.md)
- [`docs/adr/0002-gateway-ingress-e-comunicacao.md`](docs/adr/0002-gateway-ingress-e-comunicacao.md)
- [`docs/adr/0003-gateway-kong.md`](docs/adr/0003-gateway-kong.md)
