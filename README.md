# 🛡️ Smart-DB GitOps Guardrail

[![CI/CD Guardrail](https://github.com/youssefbj/smart-db-guardrail/actions/workflows/guardrail.yml/badge.svg)](https://github.com/youssefbj/smart-db-guardrail/actions/workflows/guardrail.yml)
[![Terraform](https://img.shields.io/badge/Terraform-1.7.5-7B42BC?logo=terraform)](https://terraform.io)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo)](https://argo-cd.readthedocs.io)
[![Ollama](https://img.shields.io/badge/AI-phi3:mini-blue)](https://ollama.com)
[![K3d](https://img.shields.io/badge/K8s-K3d-326CE5?logo=kubernetes)](https://k3d.io)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql)](https://postgresql.org)
[![Grafana](https://img.shields.io/badge/Grafana-10.x-F46800?logo=grafana)](https://grafana.com)

> **Pipeline GitOps qui bloque automatiquement tout déploiement PostgreSQL non sécurisé — validation IA locale via Ollama + phi3:mini, tournant dans une VM VMware Ubuntu 22.04.**

---

## 🎯 Concept

Ce projet implémente le pattern **"Policy-as-Code assisté par IA"** :
avant chaque déploiement, une IA analyse la configuration PostgreSQL
et **bloque le pipeline** si elle détecte un risque de sécurité.

```
git push
    │
    ▼
GitHub Actions CI
    ├── Terraform validate .............. ✅
    ├── Python unit tests (13 tests) .... ✅
    └── AI Guardrail (Ollama phi3:mini)
            ├── OUI → ArgoCD déploie PostgreSQL ✅
            └── NON → Pipeline bloqué 🚫
```

---

## 🖥️ Environnement de Développement

| Composant | Détail |
|-----------|--------|
| Hôte | Windows 10 64-bit + VMware Workstation/Player |
| VM | Ubuntu 22.04.3 LTS Desktop |
| CPU | Intel i5-6198DU (2 cœurs / 4 threads) — CPU-only pour l'IA |
| RAM VM | 10 GB sur 16 GB totaux |
| GPU | Nvidia 920MX (non utilisé — phi3:mini tourne sur CPU) |
| Réseau VM | NAT VMware → accès depuis Windows via IP VM |

---

## 🏗️ Stack Technique

| Outil | Rôle | Version |
|-------|------|---------|
| K3d | Cluster Kubernetes local (dans Docker) | v5.x |
| Terraform | Infrastructure as Code | v1.7.5 |
| ArgoCD | GitOps Continuous Delivery | v3.x |
| Ollama + phi3:mini | IA locale CPU (2.3 GB) | 0.x |
| PostgreSQL | Base de données protégée | 16-alpine |
| Prometheus | Collecte métriques | v2.x |
| Grafana | Dashboard supervision + rapport IA | v10.x |
| GitHub Actions | Pipeline CI/CD (4 jobs) | — |
| Python | Agent de validation IA | 3.11.x (venv isolé) |

---

## 🚀 Démarrage Rapide

```bash
# Dans la VM Ubuntu (terminal Ubuntu dans VMware)
git clone https://github.com/youssefbj/smart-db-guardrail
cd smart-db-guardrail
./scripts/bootstrap.sh
```

Le script crée automatiquement :
- ✅ Cluster K3d avec 3 nodes
- ✅ ArgoCD en GitOps sur le repo GitHub
- ✅ PostgreSQL supervisé par Prometheus
- ✅ Dashboard Grafana avec rapport IA

**Accès depuis ton navigateur Windows :**
- 🔄 ArgoCD : `http://IP_VM:8080`
- 📊 Grafana : `http://IP_VM:30300`

---

## 📸 Démonstration (dans la VM Ubuntu)

### ✅ Config sécurisée → Approuvée (60-120 sec sur i5)

```bash
source venv/bin/activate
python ai-agent/validator.py configs/postgresql.conf
# → ✅ APPROUVÉ — Score: 85/100 — Exit code: 0
# → ArgoCD synchronise automatiquement
```

### 🚫 Config dangereuse → Bloquée

```bash
python ai-agent/validator.py configs/postgresql-bad.conf
# → 🚫 REJETÉ — Score: 10/100 — Exit code: 1
# → Pipeline GitHub Actions stoppé
# → ArgoCD ne déploie rien
```

---

## 📁 Structure du Projet

```
smart-db-guardrail/
├── .github/workflows/
│   └── guardrail.yml           ← Pipeline 4 jobs CI/CD
├── terraform/
│   ├── main.tf                 ← Cluster K3d + ArgoCD + Grafana
│   ├── variables.tf
│   ├── providers.tf
│   └── outputs.tf
├── k8s/
│   ├── argocd/
│   │   └── application.yaml   ← GitOps : surveille k8s/postgres/
│   ├── postgres/
│   │   ├── deployment.yaml    ← PostgreSQL 16 + exporter sidecar
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml
│   │   └── namespace.yaml
│   └── monitoring/
│       ├── prometheus/servicemonitor.yaml
│       └── grafana/dashboard.json
├── ai-agent/
│   ├── validator.py           ← Agent IA principal
│   ├── prompts.py             ← Instructions pour phi3:mini
│   ├── test_validator.py      ← 13 tests unitaires
│   └── requirements.txt
├── configs/
│   ├── postgresql.conf        ← Config sécurisée (IA approuve ✅)
│   └── postgresql-bad.conf   ← Config dangereuse (IA bloque 🚫)
├── scripts/
│   ├── bootstrap.sh           ← Démarrage en 1 commande
│   ├── destroy.sh             ← Nettoyage complet
│   └── import-grafana-dashboard.sh
└── README.md
```

---

## 🔑 Compétences Démontrées

| Domaine | Preuve concrète |
|---------|-----------------|
| **GitOps** | ArgoCD surveille GitHub et déploie automatiquement |
| **IaC** | Terraform crée cluster + services en une commande |
| **AIOps** | IA locale intégrée dans le pipeline CI/CD |
| **DevSecOps** | Policy-as-Code : guardrail bloque les mauvaises configs |
| **Kubernetes** | K3d, namespaces, pods, services, configmaps, secrets |
| **Helm** | ArgoCD + kube-prometheus-stack installés via Helm |
| **Observabilité** | Prometheus + Grafana + rapport IA dans le dashboard |
| **CI/CD** | GitHub Actions 4 jobs avec artefacts |
| **Python** | Agent IA, tests unitaires, venv isolé |

---

## 🛠️ Commandes Utiles

```bash
# Voir l'état du cluster
kubectl get pods --all-namespaces

# Voir ArgoCD
argocd app list
argocd app get smartdb-postgres

# Tester l'IA manuellement
source venv/bin/activate
python ai-agent/validator.py configs/postgresql.conf

# Voir les logs PostgreSQL
kubectl logs -n database deploy/postgres -c postgres --tail=20

# Supprimer tout
./scripts/destroy.sh
```

---

*Développé par Youssef Ben Jannet — DevOps & Cloud Engineer*
*Environnement : Windows 10 + VMware + Ubuntu 22.04 LTS*
