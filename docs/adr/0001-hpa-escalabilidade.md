# ADR-0001 — Escalabilidade automática com HPA

- **Status:** Aceito
- **Data:** Fase 3
- **Decisores:** Equipe Tech Challenge

## Contexto
Com a expansão para múltiplas unidades e aumento da base de clientes, a aplicação precisa **escalar automaticamente** conforme a carga, garantindo disponibilidade sem superdimensionar recursos.

## Decisão
Usar **HorizontalPodAutoscaler v2** no Deployment `fiap-app`:
- **min 2 / max 6** réplicas.
- Métricas: **CPU 60%** e **memória 75%** de utilização.
- **Behavior** explícito: *scale up* rápido (janela 0s, +2 pods/30s) e *scale down* conservador (janela 120s, −1 pod/60s) para evitar oscilação (*flapping*).
- `resources.requests` de CPU/memória definidos no container (obrigatório para o HPA calcular utilização).

## Justificativa
- **v2** permite múltiplas métricas e políticas de comportamento (v1 é limitada a CPU).
- **min 2** garante alta disponibilidade (sem ponto único) mesmo em carga baixa.
- Scale up agressivo protege a latência sob pico; scale down lento evita derrubar pods cedo demais.
- Requer **metrics-server** (presente no Docker Desktop; em nuvem é gerenciado).

## Consequências
- **Positivas:** elasticidade automática, alta disponibilidade, uso eficiente de recursos; observável via `kubectl get hpa` e no dashboard (Fase 5).
- **Negativas:** depende do metrics-server; limites de recurso mal calibrados podem sub/superescalar — ajustar com base nas métricas reais (New Relic).
