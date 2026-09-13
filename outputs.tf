output "namespace" {
  value = kubernetes_namespace_v1.ns.metadata[0].name
}

output "api_service" {
  value = kubernetes_service_v1.api.metadata[0].name
}

output "api_node_port" {
  value = var.node_port
}

output "hpa" {
  value = "${kubernetes_horizontal_pod_autoscaler_v2.api.metadata[0].name} (min=2 max=6, cpu 60% / mem 75%)"
}

output "acesso_local" {
  description = "Acesso local via port-forward (confiavel no Docker Desktop)."
  value       = "kubectl port-forward -n ${var.namespace} svc/fiap-app 8080:80  ->  http://localhost:8080"
}
