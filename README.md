# 🛡️ Smart-DB GitOps Guardrail

[![CI/CD Guardrail](https://github.com/youssefbj/smart-db-guardrail/actions/workflows/guardrail.yml/badge.svg)](https://github.com/youssefbj/smart-db-guardrail/actions/workflows/guardrail.yml)
[![Terraform](https://img.shields.io/badge/Terraform-1.7.5-7B42BC?logo=terraform)](https://terraform.io)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo)](https://argo-cd.readthedocs.io)
[![Ollama](https://img.shields.io/badge/AI-phi3:mini-blue)](https://ollama.com)
[![K3d](https://img.shields.io/badge/K8s-K3d-326CE5?logo=kubernetes)](https://k3d.io)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql)](https://postgresql.org)
[![Grafana](https://img.shields.io/badge/Grafana-10.x-F46800?logo=grafana)](https://grafana.com)

> **AI-powered DevSecOps pipeline for secure PostgreSQL deployments through intelligent CI/CD guardrails**
> > **End-to-end AI-driven GitOps pipeline where each commit is validated by a local LLM (Ollama / phi3:mini), enforcing Policy-as-Code to automatically block insecure PostgreSQL configurations before they reach Kubernetes, with full observability via Prometheus and Grafana**

---

## 🎯 Concept

This project implements an **"AI-assisted Policy-as-Code"** approach for database security.

Before every deployment, a PostgreSQL configuration (postgresql.conf) is analyzed and scored based on security risk:
- Safe configurations are automatically approved  
- Risky configurations are blocked at the CI/CD level  

This ensures that no insecure configuration can be deployed to the Kubernetes cluster.
---

```
DEVELOPER
    │
    │  git push (modifies postgresql.conf)
    ▼
GITHUB REPOSITORY
    │
    │  Automatically triggers the pipeline
    ▼
GITHUB ACTIONS — 4 Sequential Validation Stages
    │
    ├── 1. Terraform Validate
    │       → Validates syntax and integrity of Infrastructure as Code
    │
    ├── 2. Python Unit Tests
    │       → Ensures the AI agent is functioning correctly
    │
    ├── 3. AI Guardrail (Core Component)
    │       → Python agent sends postgresql.conf to Ollama (phi3:mini)
    │       → AI analyzes configuration and returns a security score
    │       │
    │       ├── Score ≥ 70 → APPROVED → exit code 0
    │       │                   Pipeline continues ✅
    │       │
    │       └── Score < 70 → REJECTED → exit code 1
    │                           Pipeline BLOCKED 🚫
    │                           No deployment triggered
    │
    └── 4. Deployment Confirmation
            → Runs ONLY if all previous stages succeed

    │
    │  If validation is successful
    ▼
ARGOCD — GitOps Deployment
    │
    │  Continuously monitors the repository
    │  Detects validated commits
    │  Automatically synchronizes cluster state
    ▼
KUBERNETES (K3d)
    │
    ├── PostgreSQL 16 deployed with validated configuration
    └── postgres-exporter collects metrics
    ▼
PROMETHEUS
    │
    │  Scrapes PostgreSQL metrics every 30 seconds
    ▼
GRAFANA — Real-Time Monitoring
    ├── PostgreSQL Status (UP/DOWN)
    ├── AI Security Score
    ├── Active Connections
    ├── Database Size
    ├── Connection History
    ├── Transactions per Second
    └── Full AI Validation Report
```

---

## 🖥️ Development Environment

| Component | Details |
|-----------|--------|
| Host | Windows 10 64-bit + VMware Workstation/Player |
| VM | Ubuntu 22.04.3 LTS Desktop |
| CPU | Intel i5-6198DU (2 cores / 4 threads) — CPU-only for AI |
| VM RAM | 10 GB out of 16 GB total |
| GPU | Nvidia 920MX (not used — phi3:mini runs on CPU) |
| VM Network | VMware NAT → accessible from Windows via VM IP |

---

## 🏗️ Tech Stack

| Tool | Role | Version |
|------|------|---------|
| K3d | Local Kubernetes cluster (Docker-based) | v5.x |
| Terraform | Infrastructure as Code | v1.7.5 |
| ArgoCD | GitOps Continuous Delivery | v3.x |
| Ollama + phi3:mini | Local AI (CPU, 2.3 GB) | 0.x |
| PostgreSQL | Protected database | 16-alpine |
| Prometheus | Metrics collection | v2.x |
| Grafana | Monitoring dashboard + AI report | v10.x |
| GitHub Actions | CI/CD pipeline (4 jobs) | — |
| Python | AI validation agent | 3.11.x (isolated venv) |

---

## 🚀 Quick Start

```bash
# Inside Ubuntu VM (VMware terminal)
git clone https://github.com/${GITHUB_USERNAME}/smart-db-guardrail
cd smart-db-guardrail
./scripts/bootstrap.sh
```

The script automatically creates:
- ✅ K3d cluster with 3 nodes
- ✅ ArgoCD GitOps linked to the GitHub repository
- ✅ PostgreSQL monitored by Prometheus
- ✅ Grafana dashboard with AI validation reports

**Access from your Windows browser:**
- 🔄 ArgoCD : `http://IP_VM:8080`
- 📊 Grafana : `http://IP_VM:30300`

---

## 📸 Demo (inside Ubuntu VM)

### ✅ Secure config → Approved (60–120 sec on i5)

```bash
source venv/bin/activate
python ai-agent/validator.py configs/postgresql.conf
# → ✅ APPROVED — Score: 85/100 — Exit code: 0
# → ArgoCD auto-sync triggered
```

### 🚫 Unsafe config → Blocked

```bash
python ai-agent/validator.py configs/postgresql-bad.conf
# → 🚫 REJECTED — Score: 10/100 — Exit code: 1
# → GitHub Actions pipeline stopped
# → ArgoCD does not deploy anything
```

---

## 📁 Project Structure

```
smart-db-guardrail/
├── .github/workflows/
│   └── guardrail.yml           ← 4-job CI/CD pipeline
├── terraform/
│   ├── main.tf                 ← K3d cluster + ArgoCD + Grafana
│   ├── variables.tf
│   ├── providers.tf
│   └── outputs.tf
├── k8s/
│   ├── argocd/
│   │   └── application.yaml   ← GitOps: watches k8s/postgres/
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
│   ├── validator.py           ← Main AI agent
│   ├── prompts.py             ← Instructions for phi3:mini
│   ├── test_validator.py      ← 13 unit tests
│   └── requirements.txt
├── configs/
│   ├── postgresql.conf        ← Secure config (AI approves ✅)
│   └── postgresql-bad.conf    ← Unsafe config (AI blocks 🚫)
├── scripts/
│   ├── bootstrap.sh           ← Start everything in one command
│   ├── destroy.sh             ← Full cleanup
│   └── import-grafana-dashboard.sh
└── README.md
```

---

## 🔑 Skills Demonstrated

| Domain | Concrete Evidence |
|--------|------------------|
| **GitOps** | ArgoCD automatically deploys from GitHub |
| **IaC** | Terraform provisions the entire infrastructure |
| **AIOps** | Local AI integrated into CI/CD |
| **DevSecOps** | Policy-as-Code blocks unsafe configurations |
| **Kubernetes** | K3d, namespaces, pods, services, configmaps, secrets |
| **Helm** | ArgoCD + kube-prometheus-stack via Helm |
| **Observability** | Prometheus + Grafana + AI report dashboard |
| **CI/CD** | GitHub Actions 4-job pipeline |
| **Python** | AI agent, unit tests, isolated venv |

---

## 🛠️ Useful Commands

```bash
# Check cluster status
kubectl get pods --all-namespaces

# ArgoCD
argocd app list
argocd app get smartdb-postgres

# Test AI manually
source venv/bin/activate
python ai-agent/validator.py configs/postgresql.conf

# PostgreSQL logs
kubectl logs -n database deploy/postgres -c postgres --tail=20

# Destroy everything
./scripts/destroy.sh
```

---

*Developed by Youssef Ben Jannet — DevOps & Cloud Engineer*  
*Environment: Windows 10 + VMware + Ubuntu 22.04 LTS*
