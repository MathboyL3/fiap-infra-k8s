# ---------------------------------------------------------------------------
# RabbitMQ (Fase 4) — broker de mensagens da Saga entre os microsserviços.
# Imagem oficial com management UI. Sem plugins extras: os timeouts da Saga
# usam Quartz persistente no os-service (não o delayed-message exchange).
# ---------------------------------------------------------------------------
resource "kubernetes_secret_v1" "rabbitmq" {
  metadata {
    name      = "rabbitmq-credentials"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = local.common_labels
  }
  type = "Opaque"
  data = {
    RabbitMq__Username = var.rabbitmq_user
    RabbitMq__Password = var.rabbitmq_password
  }
}

resource "kubernetes_stateful_set_v1" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = merge(local.common_labels, { "app.kubernetes.io/name" = "rabbitmq" })
  }
  spec {
    service_name = "rabbitmq"
    replicas     = 1
    selector { match_labels = { "app.kubernetes.io/name" = "rabbitmq" } }
    template {
      metadata { labels = merge(local.common_labels, { "app.kubernetes.io/name" = "rabbitmq" }) }
      spec {
        container {
          name  = "rabbitmq"
          image = "rabbitmq:3.13-management"
          port {
            name           = "amqp"
            container_port = 5672
          }
          port {
            name           = "management"
            container_port = 15672
          }
          env {
            name = "RABBITMQ_DEFAULT_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.rabbitmq.metadata[0].name
                key  = "RabbitMq__Username"
              }
            }
          }
          env {
            name = "RABBITMQ_DEFAULT_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.rabbitmq.metadata[0].name
                key  = "RabbitMq__Password"
              }
            }
          }
          readiness_probe {
            exec { command = ["rabbitmq-diagnostics", "-q", "ping"] }
            initial_delay_seconds = 20
            period_seconds        = 15
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/rabbitmq"
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

resource "kubernetes_service_v1" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = local.common_labels
  }
  spec {
    type     = "NodePort"
    selector = { "app.kubernetes.io/name" = "rabbitmq" }
    port {
      name        = "amqp"
      port        = 5672
      target_port = 5672
    }
    port {
      name        = "management"
      port        = 15672
      target_port = 15672
      node_port   = 31672
    }
  }
}
