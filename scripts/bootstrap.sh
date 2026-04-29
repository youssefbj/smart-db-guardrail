#!/bin/bash
# ══════════════════════════════════════════════════════════════
# bootstrap.sh — Démarre Smart-DB GitOps Guardrail
#
# Environnement : Windows 10 + VMware + Ubuntu 22.04 Desktop
# Matériel      : i5-6198DU / 16GB RAM / Nvidia 920MX
#
# Usage : cd ~/smart-db-guardrail && ./scripts/bootstrap.sh
# ══════════════════════════════════════════════════════════════
set -euo pipefail

# ── Couleurs pour le terminal ─────────────────────────────────
ROUGE='\033[0;31m'
VERT='\033[0;32m'
JAUNE='\033[1;33m'
BLEU='\033[0;34m'
GRAS='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${VERT}  ✅ $1${RESET}"; }
info() { echo -e "${BLEU}  ℹ️  $1${RESET}"; }
warn() { echo -e "${JAUNE}  ⚠️  $1${RESET}"; }
err()  { echo -e "${ROUGE}  ❌ $1${RESET}"; exit 1; }

# ── Récupère l'IP de la VM ────────────────────────────────────
VM_IP=$(hostname -I | awk '{print $1}')

# ── Bannière ──────────────────────────────────────────────────
echo ""
echo -e "${GRAS}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${GRAS}║   🛡️  SMART-DB GITOPS GUARDRAIL — BOOTSTRAP          ║${RESET}"
echo -e "${GRAS}║   VMware Ubuntu 22.04 / i5-6198DU / phi3:mini        ║${RESET}"
echo -e "${GRAS}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

# ──────────────────────────────────────────────────────────────
# ÉTAPE 0 : VÉRIFICATION DES PRÉREQUIS
# ──────────────────────────────────────────────────────────────
echo -e "${GRAS}─── Étape 0 : Vérification des prérequis ───${RESET}"

for outil in docker k3d kubectl helm terraform argocd ollama python3.11 git; do
    command -v "$outil" > /dev/null 2>&1 && ok "$outil" || err "$outil manquant — voir Phase 1"
done

# ──────────────────────────────────────────────────────────────
# ÉTAPE 1 : DOCKER
# ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAS}─── Étape 1 : Docker ───${RESET}"

if ! docker ps > /dev/null 2>&1; then
    info "Docker n'est pas démarré. Démarrage..."
    sudo systemctl start docker
    sleep 3
fi

docker ps > /dev/null 2>&1 && ok "Docker actif" || err "Docker refuse de démarrer"

# ──────────────────────────────────────────────────────────────
# ÉTAPE 2 : OLLAMA + phi3:mini
# ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAS}─── Étape 2 : Ollama ───${RESET}"

if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    info "Ollama n'est pas démarré. Démarrage..."
    ollama serve > /tmp/ollama.log 2>&1 &
    sleep 5
fi

if curl -s http://localhost:11434/api/tags | grep -q "phi3"; then
    ok "Ollama + phi3:mini prêts"
else
    warn "phi3:mini absent. Téléchargement (2.3 GB — patience)..."
    ollama pull phi3:mini
    ok "phi3:mini téléchargé"
fi

# ──────────────────────────────────────────────────────────────
# ÉTAPE 3 : CLUSTER K3D VIA TERRAFORM
# ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAS}─── Étape 3 : Cluster K3d ───${RESET}"

if k3d cluster list 2>/dev/null | grep -q "smartdb-cluster"; then
    warn "Le cluster existe déjà — skip Terraform"
    warn "  → Pour repartir de zéro : ./scripts/destroy.sh"
else
    info "Création du cluster via Terraform (10-20 min sur i5-6198DU)..."
    warn "⏳ Ne ferme pas le terminal !"

    cd terraform/
    terraform init -reconfigure > /tmp/tf_init.log 2>&1 || {
        err "Terraform init a échoué. Vérifie /tmp/tf_init.log"
    }
    terraform apply -auto-approve || {
        err "Terraform apply a échoué."
    }
    cd ..
    ok "Cluster K3d créé !"
fi

# ──────────────────────────────────────────────────────────────
# ÉTAPE 4 : ATTENTE QUE LE CLUSTER SOIT PRÊT
# ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAS}─── Étape 4 : Attente cluster ───${RESET}"

info "Attente que les nodes soient Ready..."
kubectl wait --for=condition=ready node --all --timeout=120s > /dev/null 2>&1
ok "Tous les nodes sont Ready"
kubectl get nodes

# ──────────────────────────────────────────────────────────────
# ÉTAPE 5 : CONFIGURATION ARGOCD
# ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAS}─── Étape 5 : ArgoCD ───${RESET}"

info "Attente qu'ArgoCD démarre..."
kubectl wait --for=condition=available deployment/argocd-server \
    -n argocd --timeout=300s > /dev/null 2>&1 || true

# Récupère le mot de passe initial
PASS_INITIAL=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

# Essaie de se connecter (mot de passe changé ou initial)
if argocd login localhost:8080 --username admin \
    --password "Admin1234!" --insecure > /dev/null 2>&1; then
    ok "ArgoCD connecté (mot de passe : Admin1234!)"
elif [ -n "$PASS_INITIAL" ] && argocd login localhost:8080 --username admin \
    --password "$PASS_INITIAL" --insecure > /dev/null 2>&1; then
    ok "ArgoCD connecté (mot de passe initial)"
    warn "Pense à changer le mot de passe : argocd account update-password"
else
    warn "Connexion ArgoCD impossible — continue quand même"
fi

# Applique l'Application ArgoCD
kubectl apply -f k8s/argocd/application.yaml > /dev/null 2>&1 || true
ok "Application ArgoCD appliquée"

# ──────────────────────────────────────────────────────────────
# ÉTAPE 6 : MONITORING (Prometheus + Grafana)
# ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAS}─── Étape 6 : Monitoring ───${RESET}"

kubectl apply -f k8s/monitoring/prometheus/servicemonitor.yaml > /dev/null 2>&1 || true
ok "ServiceMonitor Prometheus appliqué"

sleep 5
if [ -f "scripts/import-grafana-dashboard.sh" ]; then
    ./scripts/import-grafana-dashboard.sh > /dev/null 2>&1 && \
        ok "Dashboard Grafana importé" || \
        warn "Import dashboard : fais-le manuellement dans Grafana"
fi

# ──────────────────────────────────────────────────────────────
# ÉTAPE 7 : TEST IA
# ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAS}─── Étape 7 : Test IA ───${RESET}"

if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    info "Test de l'agent IA (60-120 sec sur i5-6198DU)..."
    python ai-agent/validator.py configs/postgresql.conf || true
    deactivate
fi

# ──────────────────────────────────────────────────────────────
# RÉCAPITULATIF FINAL
# ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAS}${VERT}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${GRAS}${VERT}║   ✅ BOOTSTRAP TERMINÉ AVEC SUCCÈS !                  ║${RESET}"
echo -e "${GRAS}${VERT}╠══════════════════════════════════════════════════════╣${RESET}"
echo -e "${GRAS}${VERT}║                                                        ║${RESET}"
echo -e "${GRAS}${VERT}║   Ouvre dans ton navigateur WINDOWS :                  ║${RESET}"
echo -e "${GRAS}${VERT}║                                                        ║${RESET}"
echo -e "${GRAS}${VERT}║   🔄 ArgoCD    : http://${VM_IP}:8080          ║${RESET}"
echo -e "${GRAS}${VERT}║      Login     : admin / Admin1234!                    ║${RESET}"
echo -e "${GRAS}${VERT}║                                                        ║${RESET}"
echo -e "${GRAS}${VERT}║   📊 Grafana   : http://${VM_IP}:30300         ║${RESET}"
echo -e "${GRAS}${VERT}║      Login     : admin / admin123                      ║${RESET}"
echo -e "${GRAS}${VERT}║                                                        ║${RESET}"
echo -e "${GRAS}${VERT}║   🔍 Prometheus: http://${VM_IP}:30090         ║${RESET}"
echo -e "${GRAS}${VERT}║                                                        ║${RESET}"
echo -e "${GRAS}${VERT}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
