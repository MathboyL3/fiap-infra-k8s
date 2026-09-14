terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
  }
}

# Aponta para o cluster local (Docker Desktop). Em nuvem real, trocar o provider
# por credenciais do EKS/GKE/AKS — os recursos k8s permanecem iguais.
provider "kubernetes" {
  config_path    = var.kube_config_path
  config_context = var.kube_context
}

# Provider Helm usa o mesmo kubeconfig (para instalar o Kong via chart oficial).
provider "helm" {
  kubernetes {
    config_path    = var.kube_config_path
    config_context = var.kube_context
  }
}
