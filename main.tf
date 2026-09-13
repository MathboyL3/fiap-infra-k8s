# ---------------------------------------------------------------------------
# fiap-infra-k8s — Cluster/infra Kubernetes escalavel (HPA) via Terraform
# ---------------------------------------------------------------------------
locals {
  common_labels = { "app.kubernetes.io/part-of" = "oficina" }
  api_labels = {
    "app.kubernetes.io/name"    = "fiap-app"
    "app.kubernetes.io/part-of" = "oficina"
  }
}

resource "kubernetes_namespace_v1" "ns" {
  metadata {
    name   = var.namespace
    labels = local.common_labels
  }
}

# ConfigMap: configuracao NAO sensivel da API.
resource "kubernetes_config_map_v1" "config" {
  metadata {
    name      = "oficina-config"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = local.common_labels
  }
  data = {
    ASPNETCORE_ENVIRONMENT = "Production"
    ASPNETCORE_URLS        = "http://+:8080"
    Jwt__Issuer            = "Oficina.Api"
    Jwt__Audience          = "Oficina.Api"
    Jwt__ExpirationMinutes = "60"
    Postgres__Host         = var.postgres_host
    Postgres__Port         = tostring(var.postgres_port)
    Postgres__Database     = var.postgres_database
    Postgres__Username     = var.postgres_username
  }
}

# Secret: segredos (JWT, senha do banco, webhook).
resource "kubernetes_secret_v1" "secrets" {
  metadata {
    name      = "oficina-secrets"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = local.common_labels
  }
  type = "Opaque"
  data = {
    Jwt__Secret        = var.jwt_secret
    Webhook__Secret    = var.webhook_secret
    Postgres__Password = var.postgres_password
  }
}

# Deployment da API (.NET), escalavel pelo HPA.
resource "kubernetes_deployment_v1" "api" {
  metadata {
    name      = "fiap-app"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = local.api_labels
  }
  wait_for_rollout = false

  spec {
    replicas = var.api_replicas
    selector { match_labels = { "app.kubernetes.io/name" = "fiap-app" } }
    template {
      metadata { labels = local.api_labels }
      spec {
        container {
          name              = "fiap-app"
          image             = var.api_image
          image_pull_policy = "IfNotPresent"
          port {
            name           = "http"
            container_port = 8080
          }
          env_from {
            config_map_ref { name = kubernetes_config_map_v1.config.metadata[0].name }
          }
          env {
            name = "Jwt__Secret"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.secrets.metadata[0].name
                key  = "Jwt__Secret"
              }
            }
          }
          env {
            name = "Webhook__Secret"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.secrets.metadata[0].name
                key  = "Webhook__Secret"
              }
            }
          }
          env {
            name = "Postgres__Password"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.secrets.metadata[0].name
                key  = "Postgres__Password"
              }
            }
          }
          # Connection string para o Postgres gerenciado (Railway), com SSL.
          env {
            name  = "ConnectionStrings__Postgres"
            value = "Host=${var.postgres_host};Port=${var.postgres_port};Database=${var.postgres_database};Username=${var.postgres_username};Password=$(Postgres__Password);SSL Mode=Prefer;Trust Server Certificate=true"
          }

          startup_probe {
            http_get {
              path = "/health/live"
              port = "http"
            }
            failure_threshold = 30
            period_seconds    = 5
          }
          liveness_probe {
            http_get {
              path = "/health/live"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/health/ready"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          # requests de CPU sao obrigatorios para o HPA calcular utilizacao.
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
      }
    }
  }
}

# Service (NodePort para debug direto; o Ingress e o ponto de entrada oficial).
resource "kubernetes_service_v1" "api" {
  metadata {
    name      = "fiap-app"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = local.api_labels
  }
  spec {
    type     = "NodePort"
    selector = { "app.kubernetes.io/name" = "fiap-app" }
    port {
      name        = "http"
      port        = 80
      target_port = 8080
      node_port   = var.node_port
    }
  }
}

# HPA: escalabilidade automatica por CPU e memoria.
resource "kubernetes_horizontal_pod_autoscaler_v2" "api" {
  metadata {
    name      = "fiap-app"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = local.api_labels
  }
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.api.metadata[0].name
    }
    min_replicas = 2
    max_replicas = 6

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 60
        }
      }
    }
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 75
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 0
        select_policy                = "Max"
        policy {
          type           = "Pods"
          value          = 2
          period_seconds = 30
        }
      }
      scale_down {
        stabilization_window_seconds = 120
        select_policy                = "Max"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }
    }
  }
}
