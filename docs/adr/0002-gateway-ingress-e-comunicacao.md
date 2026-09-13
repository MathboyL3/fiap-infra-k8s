# ADR-0002 — Gateway (Ingress NGINX) e padrão de comunicação

- **Status:** Aceito
- **Data:** Fase 3
- **Decisores:** Equipe Tech Challenge

## Contexto
O enunciado exige um **API Gateway** protegendo rotas sensíveis com autenticação e uma arquitetura escalável. Dentro do cluster, precisamos de um ponto de entrada único, roteamento e proteção de borda.

## Decisão
- **Ingress NGINX** como **gateway de entrada** do cluster: roteamento único, `limit-rps` (rate limit de borda) e encaminhamento do header `Authorization`.
- **Autenticação por JWT validada na aplicação** (HS256, `iss/aud=Oficina.Api`, **mesmo secret** da `fiap-auth-lambda`). Rotas sensíveis exigem Bearer token; o endpoint público de acompanhamento de OS permanece aberto.
- **Comunicação síncrona HTTP/REST** entre gateway → Service → Pods; conexão a dados via **Npgsql com SSL** ao banco gerenciado (Railway).

> Observação: há **dois gateways** por design. O **API Gateway serverless** (`fiap-auth-lambda`, LocalStack) emite o JWT (fluxo de login por CPF). O **Ingress NGINX** é o gateway do cluster para as APIs de negócio, que consomem esse JWT.

## Alternativas consideradas
- **Traefik:** ótimo, mas o ecossistema do curso e a documentação padrão usam ingress-nginx; menor curva.
- **Validar JWT no próprio gateway** (ex.: plugin/oauth2-proxy): mais complexo e o `configuration-snippet` vem desabilitado por segurança nas versões recentes do ingress-nginx. Validar na app reaproveita o middleware `[Authorize]` já existente.

## Consequências
- **Positivas:** ponto de entrada único, rate limit, TLS terminável no Ingress, autorização por role reaproveitada da aplicação. Portável para ALB/NLB + Ingress em nuvem.
- **Negativas:** a validação de JWT não ocorre na borda (é na app) — aceitável, pois a app é a autoridade de autorização por role. Se necessário no futuro, adicionar `oauth2-proxy`/authz na borda.
