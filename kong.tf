# ---------------------------------------------------------------------------
# Kong como API Gateway (alternativa ao Ingress NGINX).
#
# O Kong Ingress Controller precisa estar instalado no cluster (via Helm):
#   helm repo add kong https://charts.konghq.com && helm repo update
#   helm install kong kong/ingress -n kong --create-namespace
#
# Cria um Ingress com ingressClassName=kong roteando para a API e um
# KongPlugin de rate-limiting (equivalente ao limit-rps do NGINX).
# Ative com: enable_kong = true (e, se quiser, enable_ingress = false).
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "kong_rate_limiting" {
  count = var.enable_kong ? 1 : 0

  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongPlugin"
    metadata = {
      name      = "rate-limiting"
      namespace = kubernetes_namespace_v1.ns.metadata[0].name
    }
    plugin = "rate-limiting"
    config = {
      minute = var.kong_rate_limit_per_minute
      policy = "local"
    }
  }
}

resource "kubernetes_ingress_v1" "api_kong" {
  count = var.enable_kong ? 1 : 0

  metadata {
    name      = "fiap-app-kong"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = local.api_labels
    annotations = {
      "konghq.com/strip-path" = "false"
      "konghq.com/plugins"    = "rate-limiting"
    }
  }

  spec {
    ingress_class_name = "kong"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.api.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.kong_rate_limiting]
}
