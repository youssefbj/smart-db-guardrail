variable "cluster_name" {
  type    = string
  default = "smartdb-cluster"
}

variable "argocd_namespace" {
  type    = string
  default = "argocd"
}

variable "postgres_namespace" {
  type    = string
  default = "database"
}

variable "monitoring_namespace" {
  type    = string
  default = "monitoring"
}

# Chart 7.x = compatible avec ArgoCD CLI v3.x
variable "argocd_chart_version" {
  type    = string
  default = "7.8.23"
}

variable "monitoring_chart_version" {
  type    = string
  default = "61.9.0"
}
