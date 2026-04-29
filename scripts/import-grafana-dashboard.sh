#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Importe le dashboard JSON dans Grafana via l'API REST.
# Fonctionne depuis l'intérieur de la VM Ubuntu.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

GRAFANA_URL="http://localhost:30300"
GRAFANA_USER="admin"
GRAFANA_PASS="admin123"
FICHIER="k8s/monitoring/grafana/dashboard.json"

VM_IP=$(hostname -I | awk '{print $1}')

echo "📊 Import du dashboard Grafana..."
echo "   URL interne VM : $GRAFANA_URL"

# Vérifie que Grafana répond
if ! curl -s "$GRAFANA_URL/api/health" | grep -q "ok"; then
    echo "❌ Grafana ne répond pas sur $GRAFANA_URL"
    echo "   Vérifie : kubectl get pods -n monitoring | grep grafana"
    exit 1
fi

# Prépare le payload JSON de manière sécurisée
PAYLOAD=$(python3 -c "
import json, sys
with open('$FICHIER', 'r') as f:
    d = json.load(f)
print(json.dumps({'dashboard': d, 'overwrite': True, 'folderId': 0}))
")

# Envoie à Grafana
REPONSE=$(curl -s -X POST \
    "$GRAFANA_URL/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -d "$PAYLOAD")

echo "Réponse API : $REPONSE"

if echo "$REPONSE" | grep -q '"status":"success"'; then
    echo ""
    echo "✅ Dashboard importé avec succès !"
    echo "   Ouvre dans Windows : http://$VM_IP:30300/d/smartdb-guardrail-v1"
else
    echo ""
    echo "⚠️  Import via API non concluant."
    echo "   Import manuel dans Grafana :"
    echo "   1. Va sur http://$VM_IP:30300"
    echo "   2. Dashboards → New → Import"
    echo "   3. Upload le fichier : $FICHIER"
fi
