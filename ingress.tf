# ---------------------------------------------------------------------------
# Ingress (NGINX) — ponto de entrada unico. As rotas sensiveis sao protegidas
# por JWT: a aplicacao valida o Bearer token (mesmo issuer/audience/secret da
# Lambda fiap-auth). O Ingress centraliza roteamento, TLS e rate limit.
#
# Requer ingress-nginx instalado no cluster:
#   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
# ---------------------------------------------------------------------------
resource "kubernetes_ingress_v1" "api" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = "fiap-app"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = local.api_labels
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
      "nginx.ingress.kubernetes.io/ssl-redirect"   = "false"
      # Rate limit basico no gateway (protecao de borda).
      "nginx.ingress.kubernetes.io/limit-rps" = "20"
    }
  }

  spec {
    ingress_class_name = "nginx"
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
}
