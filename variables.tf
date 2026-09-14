variable "kube_config_path" {
  description = "Caminho do kubeconfig."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Contexto do kubeconfig (cluster-alvo)."
  type        = string
  default     = "docker-desktop"
}

variable "namespace" {
  type    = string
  default = "oficina"
}

variable "api_image" {
  description = "Imagem da API (buildada no Docker Desktop ou registry)."
  type        = string
  default     = "fiap-app:local"
}

variable "api_replicas" {
  description = "Replicas iniciais (o HPA ajusta em runtime)."
  type        = number
  default     = 2
}

variable "node_port" {
  description = "NodePort de acesso direto ao Service (debug)."
  type        = number
  default     = 30080
}

# --- Configuracao do banco gerenciado (outputs do fiap-infra-db) ---
variable "postgres_host" {
  type    = string
  default = "gondola.proxy.rlwy.net"
}
variable "postgres_port" {
  type    = number
  default = 11177
}
variable "postgres_database" {
  type    = string
  default = "railway"
}
variable "postgres_username" {
  type    = string
  default = "postgres"
}

# --- Segredos (injetar via TF_VAR_* ou terraform.tfvars; nunca versionar) ---
variable "jwt_secret" {
  description = "Segredo JWT HS256 (>=32 chars). Mesmo da Lambda e da app."
  type        = string
  sensitive   = true
}
variable "postgres_password" {
  description = "Senha do Postgres gerenciado (Railway)."
  type        = string
  sensitive   = true
}
variable "webhook_secret" {
  description = "Segredo do webhook de aprovacao de orcamento."
  type        = string
  sensitive   = true
  default     = "change-me-webhook-secret"
}

variable "enable_ingress" {
  description = "Cria o Ingress NGINX (requer ingress-nginx instalado no cluster)."
  type        = bool
  default     = true
}

variable "newrelic_license_key" {
  description = "New Relic INGEST license key (APM). Injetada como env NEW_RELIC_LICENSE_KEY."
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_kong" {
  description = "Cria o Ingress Kong + KongPlugin de rate-limiting (requer o Kong Ingress Controller instalado via Helm)."
  type        = bool
  default     = false
}

variable "kong_rate_limit_per_minute" {
  description = "Limite de requisicoes por minuto no Kong (rate-limiting)."
  type        = number
  default     = 1200
}
