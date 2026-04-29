#!/bin/bash
# ══════════════════════════════════════════════════════════════
# destroy.sh — Supprime tout l'environnement proprement
#
# ⚠️  ATTENTION : Tout sera supprimé (cluster, pods, données).
# Cette action est IRRÉVERSIBLE (sauf si tu as un snapshot VMware).
#
# Usage : ./scripts/destroy.sh
# ══════════════════════════════════════════════════════════════
set -euo pipefail

echo ""
echo "⚠️  ATTENTION : Tu vas supprimer TOUT l'environnement."
echo "   - Cluster K3d (tous les pods : ArgoCD, PostgreSQL, Grafana...)"
echo "   - Toutes les données PostgreSQL"
echo "   - Tous les rapports générés"
echo ""
echo "   → Pour annuler : appuie sur Ctrl+C"
echo ""
read -p "   Tape exactement 'DESTROY' pour confirmer : " CONFIRMATION
echo ""

if [ "$CONFIRMATION" != "DESTROY" ]; then
    echo "  Annulé. Rien n'a été supprimé."
    exit 0
fi

echo "🗑️  Suppression en cours..."

# Détruit via Terraform (propre)
if [ -d "terraform/.terraform" ]; then
    echo "  → Destruction Terraform..."
    cd terraform/
    terraform destroy -auto-approve 2>/dev/null || {
        echo "  → Terraform destroy échoué, suppression directe K3d..."
        k3d cluster delete smartdb-cluster 2>/dev/null || true
    }
    cd ..
else
    # Terraform pas initialisé, supprime K3d directement
    echo "  → Suppression directe du cluster K3d..."
    k3d cluster delete smartdb-cluster 2>/dev/null || true
fi

echo "  ✅ Cluster supprimé"

# Nettoie les fichiers générés
rm -f ai-agent/validation_report.json
rm -f /tmp/ollama.log
rm -f /tmp/tf_init.log

echo "  ✅ Fichiers temporaires nettoyés"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   ✅ Environnement complètement supprimé     ║"
echo "║                                              ║"
echo "║   Pour repartir de zéro :                   ║"
echo "║   ./scripts/bootstrap.sh                    ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
