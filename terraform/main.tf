# main.tf
# ─────────────────────────────────────────────────────────────────────
# PLAN DE PORTS DÉFINITIF (AUCUN CONFLIT) :
#
#   ArgoCD UI  : VM_IP:8080  → K3d loadbalancer:80  → ArgoCD pod
#   Grafana    : VM_IP:30300 → K3d NodePort:30300   → Grafana pod
#   Prometheus : VM_IP:30090 → K3d NodePort:30090   → Prometheus pod
#   PostgreSQL : Pas exposé à l'extérieur (seulement dans le cluster)
#
# POURQUOI ÇA MARCHE DEPUIS WINDOWS :
#   K3d crée un container Docker "loadbalancer" qui écoute sur
#   0.0.0.0 de la VM Ubuntu. Donc VM_IP:8080 est accessible
#   depuis Windows (via NAT VMware).
# ─────────────────────────────────────────────────────────────────────

# ══════════════════════════════════════════════════════════════════
# BLOC 1 : CRÉATION DU CLUSTER K3D
# ══════════════════════════════════════════════════════════════════
resource "null_resource" "k3d_cluster" {
  triggers = {
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    command = <<-CMD
      echo "=== Création du cluster K3d pour VMware ==="

      # Vérifie que Docker tourne
      docker ps > /dev/null 2>&1 || { echo "ERREUR: Docker n'est pas démarré!"; exit 1; }

      # Crée le cluster K3d
      # --port "HOST:CONTAINER@loadbalancer" : expose les ports
      # Le loadbalancer K3d écoute sur 0.0.0.0 → accessible depuis Windows
      k3d cluster create ${var.cluster_name} \
        --agents 2 \
        --port "8080:80@loadbalancer" \
        --port "30300:30300@server:0" \
        --port "30090:30090@server:0" \
        --k3s-arg "--disable=traefik@server:0" \
        --wait

      echo "=== Cluster créé ! ==="
      kubectl get nodes

      VM_IP=$(hostname -I | awk '{print $1}')
      echo ""
      echo "=== ACCÈS DEPUIS WINDOWS ==="
      echo "ArgoCD  → http://$VM_IP:8080"
      echo "Grafana → http://$VM_IP:30300 (dispo après Phase 7)"
      echo "============================"
    CMD
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete ${self.triggers.cluster_name} || true"
  }
}

# ══════════════════════════════════════════════════════════════════
# BLOC 2 : ATTENDRE QUE LE CLUSTER SOIT VRAIMENT PRÊT
# ══════════════════════════════════════════════════════════════════
resource "null_resource" "wait_cluster" {
  depends_on = [null_resource.k3d_cluster]

  provisioner "local-exec" {
    command = <<-CMD
      echo "Attente que tous les nodes soient Ready..."
      sleep 15
      kubectl wait \
        --for=condition=ready node \
        --all \
        --timeout=180s
      echo "Nodes prêts !"
      kubectl get nodes -o wide
    CMD
  }
}

# ══════════════════════════════════════════════════════════════════
# BLOC 3 : NAMESPACES KUBERNETES
# Chaque composant a son propre espace isolé
# ══════════════════════════════════════════════════════════════════
resource "kubernetes_namespace" "argocd" {
  depends_on = [null_resource.wait_cluster]
  metadata {
    name   = var.argocd_namespace
    labels = { "managed-by" = "terraform", "project" = "smart-db-guardrail" }
  }
}

resource "kubernetes_namespace" "database" {
  depends_on = [null_resource.wait_cluster]
  metadata {
    name   = var.postgres_namespace
    labels = { "managed-by" = "terraform", "project" = "smart-db-guardrail" }
  }
}

resource "kubernetes_namespace" "monitoring" {
  depends_on = [null_resource.wait_cluster]
  metadata {
    name   = var.monitoring_namespace
    labels = { "managed-by" = "terraform", "project" = "smart-db-guardrail" }
  }
}

# ══════════════════════════════════════════════════════════════════
# BLOC 4 : ARGOCD VIA HELM
# Chart 7.x pour ArgoCD v2.14+ / v3.x
# Exposé sur le port 8080 de la VM via K3d loadbalancer
# ══════════════════════════════════════════════════════════════════
resource "helm_release" "argocd" {
  depends_on = [kubernetes_namespace.argocd]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = var.argocd_namespace

  # Mode HTTP (pas HTTPS) pour simplifier l'accès local
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  # ─── Limites mémoire pour VM 10GB / i5-6198DU ───────────────
  set {
    name  = "server.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "256Mi"
  }

  set {
    name  = "repoServer.resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "repoServer.resources.limits.memory"
    value = "128Mi"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "256Mi"
  }

  set {
    name  = "applicationSet.resources.requests.memory"
    value = "32Mi"
  }

  set {
    name  = "applicationSet.resources.limits.memory"
    value = "64Mi"
  }

  set {
    name  = "notifications.resources.requests.memory"
    value = "32Mi"
  }

  set {
    name  = "notifications.resources.limits.memory"
    value = "64Mi"
  }

  wait    = true
  timeout = 600 # 10 minutes max
}

# ══════════════════════════════════════════════════════════════════
# BLOC 5 : PROMETHEUS + GRAFANA VIA HELM
# Grafana exposé sur NodePort 30300
# Prometheus exposé sur NodePort 30090
# ══════════════════════════════════════════════════════════════════
resource "helm_release" "monitoring" {
  depends_on = [kubernetes_namespace.monitoring]

  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.monitoring_chart_version
  namespace  = var.monitoring_namespace

  set {
    name  = "grafana.adminPassword"
    value = "admin123"
  }

  set {
    name  = "grafana.service.type"
    value = "NodePort"
  }

  set {
    name  = "grafana.service.nodePort"
    value = "30300"
  }

  # Prometheus sur NodePort 30090
  set {
    name  = "prometheus.service.type"
    value = "NodePort"
  }

  set {
    name  = "prometheus.service.nodePort"
    value = "30090"
  }

  # Limites mémoire
  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "grafana.resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "grafana.resources.limits.memory"
    value = "128Mi"
  }

  set {
    name  = "nodeExporter.enabled"
    value = "false"
  }

  wait    = true
  timeout = 900 # 15 minutes max
}
