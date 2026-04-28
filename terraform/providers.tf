# providers.tf
# Plugins utilisés par Terraform :
#   null       → exécuter des commandes shell (pour k3d)
#   kubernetes → créer les namespaces K8s
#   helm       → installer ArgoCD et Grafana via Helm

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

# Ces deux providers lisent ~/.kube/config
# que K3d créera automatiquement au démarrage du cluster.
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "k3d-smartdb-cluster"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "k3d-smartdb-cluster"
  }
}
