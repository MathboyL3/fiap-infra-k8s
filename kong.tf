# ---------------------------------------------------------------------------
# Kong API Gateway (DB-backed) + Postgres dedicado + Konga (GUI) — tudo IaC.
#
# Com enable_kong = true, um unico `terraform apply` sobe:
#   1. namespace `kong`;
#   2. um PostgreSQL dedicado ao Kong (StatefulSet + Service + Secret);
#   3. o Kong (chart oficial kong/kong via provider helm) em modo DB-backed,
#      com Admin API HTTP habilitado e migrations automaticas;
#   4. o Konga (GUI open source do curso) apontando para o Admin API do Kong.
#
# Deixa o ambiente pronto para demonstracao (proxy + GUI) sem passos manuais.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "kong" {
  count = var.enable_kong ? 1 : 0
  metadata { name = "kong" }
}

# --- Postgres dedicado ao Kong -------------------------------------------
resource "kubernetes_secret_v1" "kong_pg" {
  count = var.enable_kong ? 1 : 0
  metadata {
    name      = "kong-postgres"
    namespace = kubernetes_namespace_v1.kong[0].metadata[0].name
  }
  data = {
    POSTGRES_USER     = "kong"
    POSTGRES_PASSWORD = var.kong_pg_password
    POSTGRES_DB       = "kong"
  }
}

resource "kubernetes_stateful_set_v1" "kong_pg" {
  count = var.enable_kong ? 1 : 0
  metadata {
    name      = "kong-postgres"
    namespace = kubernetes_namespace_v1.kong[0].metadata[0].name
  }
  spec {
    service_name = "kong-postgres"
    replicas     = 1
    selector { match_labels = { app = "kong-postgres" } }
    template {
      metadata { labels = { app = "kong-postgres" } }
      spec {
        container {
          name  = "postgres"
          image = "postgres:16-alpine"
          env_from {
            secret_ref { name = kubernetes_secret_v1.kong_pg[0].metadata[0].name }
          }
          port { container_port = 5432 }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "pgdata"
          }
          readiness_probe {
            exec { command = ["pg_isready", "-U", "kong"] }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
    volume_claim_template {
      metadata { name = "data" }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources { requests = { storage = "1Gi" } }
      }
    }
  }
}

resource "kubernetes_service_v1" "kong_pg" {
  count = var.enable_kong ? 1 : 0
  metadata {
    name      = "kong-postgres"
    namespace = kubernetes_namespace_v1.kong[0].metadata[0].name
  }
  spec {
    selector = { app = "kong-postgres" }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# --- Kong (chart oficial, DB-backed) -------------------------------------
resource "helm_release" "kong" {
  count      = var.enable_kong ? 1 : 0
  name       = "kong"
  repository = "https://charts.konghq.com"
  chart      = "kong"
  namespace  = kubernetes_namespace_v1.kong[0].metadata[0].name

  # espera os recursos ficarem prontos
  timeout = 600

  values = [yamlencode({
    env = {
      database    = "postgres"
      pg_host     = "kong-postgres"
      pg_port     = "5432"
      pg_user     = "kong"
      pg_password = var.kong_pg_password
      pg_database = "kong"
    }
    postgresql = { enabled = false }
    migrations = { init = true, preUpgrade = true, postUpgrade = true }
    admin = {
      enabled = true
      http    = { enabled = true, servicePort = 8001, containerPort = 8001 }
      type    = "ClusterIP"
      tls     = { enabled = false }
    }
    proxy             = { enabled = true, type = "NodePort", http = { enabled = true, servicePort = 80, containerPort = 8000, nodePort = 32080 } }
    ingressController = { enabled = false }
  })]

  depends_on = [
    kubernetes_stateful_set_v1.kong_pg,
    kubernetes_service_v1.kong_pg,
  ]
}

# --- Konga (GUI do Kong — estilo do curso) -------------------------------
resource "kubernetes_deployment_v1" "konga" {
  count = var.enable_kong ? 1 : 0
  metadata {
    name      = "konga"
    namespace = kubernetes_namespace_v1.kong[0].metadata[0].name
    labels    = { app = "konga" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "konga" } }
    template {
      metadata { labels = { app = "konga" } }
      spec {
        container {
          name  = "konga"
          image = "pantsel/konga:latest"
          env {
            name  = "NODE_ENV"
            value = "production"
          }
          # Admin API do Kong (HTTP) para o Konga gerenciar servicos/rotas/consumers
          env {
            name  = "DEFAULT_KONG_ADMIN_URL"
            value = "http://kong-kong-admin:8001"
          }
          port { container_port = 1337 }
        }
      }
    }
  }
  depends_on = [helm_release.kong]
}

resource "kubernetes_service_v1" "konga" {
  count = var.enable_kong ? 1 : 0
  metadata {
    name      = "konga"
    namespace = kubernetes_namespace_v1.kong[0].metadata[0].name
    labels    = { app = "konga" }
  }
  spec {
    type     = "NodePort"
    selector = { app = "konga" }
    port {
      port        = 1337
      target_port = 1337
      node_port   = 31337
    }
  }
}

# --- Configuracao declarativa do Kong via Admin API (Service/Rota/Plugin) ---
# Um Job roda dentro do cluster e faz PUT idempotente no Admin API interno,
# criando a Service `fiap-app` (upstream = Service .NET no ns oficina), a Route
# `fiap-app-route` (path /) e o plugin rate-limiting. Assim o `terraform apply`
# entrega o gateway JA CONFIGURADO (sem passos manuais na GUI), e o Konga fica
# livre para o usuario inspecionar/editar ao vivo na demonstracao.
resource "kubernetes_job_v1" "kong_config" {
  count = var.enable_kong ? 1 : 0
  metadata {
    name      = "kong-config"
    namespace = kubernetes_namespace_v1.kong[0].metadata[0].name
  }
  spec {
    backoff_limit = 6
    template {
      metadata { labels = { app = "kong-config" } }
      spec {
        restart_policy = "OnFailure"
        container {
          name  = "kong-config"
          image = "curlimages/curl:8.10.1"
          env {
            name  = "ADMIN"
            value = "http://kong-kong-admin:8001"
          }
          env {
            name  = "RL"
            value = tostring(var.kong_rate_limit_per_minute)
          }
          command = ["/bin/sh", "-c"]
          args = [<<-SH
            set -e
            echo "aguardando Admin API..."
            until curl -sf "$ADMIN" >/dev/null; do sleep 3; done
            echo "criando Service fiap-app..."
            curl -sf -X PUT "$ADMIN/services/fiap-app" \
              --data "url=http://fiap-app.oficina.svc.cluster.local:80"
            echo
            echo "criando Route fiap-app-route..."
            curl -sf -X PUT "$ADMIN/services/fiap-app/routes/fiap-app-route" \
              --data "paths[]=/" --data "strip_path=false"
            echo
            echo "criando plugin rate-limiting ($RL/min)..."
            curl -sf -X PUT "$ADMIN/plugins/a1b2c3d4-0000-4000-8000-000000000001" \
              --data "name=rate-limiting" \
              --data "instance_name=rate-limiting-fiap" \
              --data "service.name=fiap-app" \
              --data "config.minute=$RL" \
              --data "config.policy=local"
            echo
            echo "config do Kong aplicada."
          SH
          ]
        }
      }
    }
  }
  depends_on          = [helm_release.kong]
  wait_for_completion = true
  timeouts {
    create = "5m"
    update = "5m"
  }
}
