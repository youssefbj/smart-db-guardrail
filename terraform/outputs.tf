output "cluster_name" {
  value = var.cluster_name
}

output "vm_ip" {
  description = "IP de la VM — utilise depuis Windows"
  value       = "192.168.44.129"
}

output "argocd_acces_windows" {
  description = "URL ArgoCD dans ton navigateur Windows"
  value       = "http://192.168.44.129:8080  (login: admin / voir Phase 4)"
}

output "grafana_acces_windows" {
  description = "URL Grafana dans ton navigateur Windows"
  value       = "http://192.168.44.129:30300  (login: admin / admin123)"
}

output "prometheus_acces_windows" {
  description = "URL Prometheus dans ton navigateur Windows"
  value       = "http://192.168.44.129:30090"
}

output "commande_password_argocd" {
  description = "Pour récupérer le mot de passe initial ArgoCD"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
}
