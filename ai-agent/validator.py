"""
validator.py — Agent de validation IA pour Smart-DB GitOps Guardrail.

Environnement testé :
    OS       : Ubuntu 22.04.3 LTS Desktop dans VMware
    Python   : 3.11.x (via venv isolé — JAMAIS le Python système)
    Ollama   : version récente (0.1.x ou plus)
    Modèle   : phi3:mini (2.3 GB, CPU-only)
    CPU      : Intel i5-6198DU (2 cœurs physiques / 4 threads)
    RAM VM   : 10 GB

Usage :
    source venv/bin/activate
    python ai-agent/validator.py configs/postgresql.conf     → exit 0 (approuvé)
    python ai-agent/validator.py configs/postgresql-bad.conf → exit 1 (bloqué)

Exit codes :
    0 → OUI  → GitHub Actions continue → ArgoCD déploie
    1 → NON  → GitHub Actions s'arrête → rien n'est déployé
    2 → Erreur Ollama → vérifier que Ollama tourne
"""

import json
import sys
import re
import os
import requests
from pathlib import Path
from datetime import datetime, timezone

# Import depuis le fichier prompts.py dans le même dossier
from prompts import SYSTEM_PROMPT, build_validation_prompt


# ──────────────────────────────────────────────────────────────
# CONFIGURATION (modifiable via variables d'environnement)
# ──────────────────────────────────────────────────────────────
OLLAMA_URL   = os.getenv("OLLAMA_URL",   "http://localhost:11434/api/generate")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi3:mini")
REPORT_FILE  = "validation_report.json"

# Codes couleur ANSI pour le terminal Ubuntu
VERT  = "\033[32m"
ROUGE = "\033[31m"
JAUNE = "\033[33m"
BLEU  = "\033[34m"
GRAS  = "\033[1m"
RESET = "\033[0m"


def afficher_banniere():
    """Affiche la bannière au démarrage."""
    print(f"\n{GRAS}{'═' * 62}{RESET}")
    print(f"{GRAS}  🛡️  SMART-DB GITOPS GUARDRAIL — AGENT IA{RESET}")
    print(f"  Modèle    : {OLLAMA_MODEL} via Ollama")
    print(f"  Plateforme: Ubuntu 22.04 / VMware / i5-6198DU")
    print(f"  ⏳ Note    : 60-120 sec par analyse (CPU-only)")
    print(f"{GRAS}{'═' * 62}{RESET}")


def appeler_ollama(prompt: str, system: str) -> str:
    """
    Envoie le fichier de config à Ollama et retourne la réponse brute.
    
    Ollama tourne dans la VM Ubuntu sur localhost:11434.
    Il est accessible seulement depuis l'intérieur de la VM.
    """
    payload = {
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "system": system,
        "stream": False,      # Réponse complète en une fois (pas de streaming)
        "options": {
            "temperature": 0.1,   # Proche de 0 = réponses déterministes
            "top_p": 0.9,
            "num_predict": 1200,  # Longueur max de la réponse
            "seed": 42,           # Pour des résultats reproductibles
            # i5-6198DU : 2 cœurs physiques → 3 threads dans la VM
            # On utilise 2 pour l'IA et garde 1 pour le reste de la VM
            "num_thread": 2,
        }
    }

    print(f"\n  {BLEU}📡 Connexion à Ollama (localhost:11434)...{RESET}")
    print(f"  {BLEU}🤖 Modèle : {OLLAMA_MODEL}{RESET}")
    print(f"  {JAUNE}⏳ Analyse en cours... (60-120 sec sur i5-6198DU){RESET}")
    print(f"  {JAUNE}   ↳ Ne ferme pas ce terminal !{RESET}")

    try:
        reponse = requests.post(
            OLLAMA_URL,
            json=payload,
            timeout=360    # 6 minutes max (le i5 peut être lent)
        )
        reponse.raise_for_status()
        donnees = reponse.json()

        if "response" not in donnees:
            print(f"{ROUGE}❌ Réponse inattendue d'Ollama : {donnees}{RESET}")
            sys.exit(2)

        print(f"  {VERT}✅ Réponse reçue !{RESET}")
        return donnees["response"]

    except requests.exceptions.ConnectionError:
        print(f"\n{ROUGE}{'═' * 62}{RESET}")
        print(f"{ROUGE}  ❌ OLLAMA NE RÉPOND PAS !{RESET}")
        print(f"{ROUGE}{'═' * 62}{RESET}")
        print()
        print("  Solutions :")
        print("  1. Ouvre un 2e terminal dans Ubuntu")
        print("  2. Tape : ollama serve")
        print("  3. Attends 5 secondes")
        print("  4. Reviens ici et relance la commande")
        print()
        sys.exit(2)

    except requests.exceptions.Timeout:
        print(f"\n{ROUGE}❌ Timeout après 6 minutes.{RESET}")
        print("  Le CPU est peut-être surchargé.")
        print("  Ferme les applications ouvertes dans Ubuntu et réessaie.")
        sys.exit(2)

    except Exception as erreur:
        print(f"\n{ROUGE}❌ Erreur inattendue : {erreur}{RESET}")
        sys.exit(2)


def parser_reponse(texte_brut: str) -> dict:
    """
    Analyse la réponse texte d'Ollama et extrait les données structurées.
    
    phi3:mini peut parfois répondre avec un format légèrement différent.
    Cette fonction gère tous les cas de figure et retourne toujours
    un dictionnaire valide.
    """
    print(f"\n  🔍 Analyse de la réponse IA...")

    # ── 1. Cherche le VERDICT ───────────────────────────────────
    verdict = "NON"    # Par défaut : on bloque si aucun verdict clair
    correspondance = re.search(
        r"VERDICT\s*:\s*(OUI|NON)",
        texte_brut,
        re.IGNORECASE
    )
    if correspondance:
        verdict = correspondance.group(1).upper()
    else:
        # Cherche dans le JSON si le VERDICT n'est pas en tête
        dans_json = re.search(
            r'"verdict"\s*:\s*"(OUI|NON)"',
            texte_brut,
            re.IGNORECASE
        )
        if dans_json:
            verdict = dans_json.group(1).upper()

    # ── 2. Extrait le bloc JSON ──────────────────────────────────
    correspondance_json = re.search(r'\{[\s\S]*\}', texte_brut)

    if correspondance_json:
        json_str = correspondance_json.group()

        # Tentative 1 : parse directement
        try:
            donnees = json.loads(json_str)
            donnees["verdict"] = verdict
            return donnees
        except json.JSONDecodeError:
            pass

        # Tentative 2 : corrige les virgules finales (erreur fréquente de l'IA)
        json_propre = re.sub(r',(\s*[}\]])', r'\1', json_str)
        try:
            donnees = json.loads(json_propre)
            donnees["verdict"] = verdict
            return donnees
        except json.JSONDecodeError as erreur:
            print(f"  {JAUNE}⚠️  JSON mal formé : {erreur}{RESET}")

    # ── 3. Fallback si tout échoue ───────────────────────────────
    print(f"  {JAUNE}⚠️  Format IA illisible — utilisation du résultat minimal{RESET}")
    return {
        "verdict": verdict,
        "score_securite": 0 if verdict == "NON" else 50,
        "risques": [{
            "niveau": "INCONNU",
            "description": "Le format de la réponse IA était illisible",
            "ligne_config": "N/A",
            "correction": "Relancer la validation"
        }],
        "points_positifs": [],
        "recommandations": ["Relancer la validation pour un rapport complet"],
        "resume": "Analyse incomplète. Relancer pour un rapport détaillé."
    }


def afficher_rapport(resultat: dict, chemin_fichier: str):
    """Affiche le rapport de validation de façon lisible dans le terminal."""

    verdict  = resultat.get("verdict", "NON")
    score    = resultat.get("score_securite", 0)
    risques  = resultat.get("risques", [])
    positifs = resultat.get("points_positifs", [])

    # Barre de score colorée
    s = int(score) if isinstance(score, (int, float)) else 0
    barre = "█" * (s // 10) + "░" * (10 - s // 10)
    couleur_score = VERT if s >= 70 else ROUGE

    print(f"\n{'═' * 62}")
    print(f"  RAPPORT DE VALIDATION IA")
    print(f"{'─' * 62}")
    print(f"  Fichier      : {Path(chemin_fichier).name}")
    print(f"  Modèle       : {OLLAMA_MODEL}")
    print(f"  Date         : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Environnement: VMware Ubuntu 22.04 / i5-6198DU CPU")
    print(f"{'─' * 62}")

    if verdict == "OUI":
        print(f"  Verdict      : {VERT}{GRAS}✅ APPROUVÉ — Déploiement autorisé{RESET}")
    else:
        print(f"  Verdict      : {ROUGE}{GRAS}🚫 REJETÉ — Déploiement bloqué{RESET}")

    print(f"  Score        : {couleur_score}{s}/100  [{barre}]{RESET}")
    print(f"{'═' * 62}")

    # Affiche les risques
    icones_niveaux = {
        "CRITIQUE": "🔴",
        "HAUT":     "🟠",
        "MOYEN":    "🟡",
        "FAIBLE":   "🟢",
        "INCONNU":  "⚪"
    }

    if risques:
        print(f"\n  ⚠️  RISQUES DÉTECTÉS ({len(risques)}) :")
        for risque in risques:
            niveau = risque.get("niveau", "INCONNU")
            icone  = icones_niveaux.get(niveau, "⚪")
            print(f"\n    {icone} [{niveau}]")
            print(f"       Problème   : {risque.get('description', '')}")
            ligne = risque.get("ligne_config", "N/A")
            if ligne and ligne != "N/A":
                print(f"       Ligne      : {ligne}")
            correction = risque.get("correction", "")
            if correction:
                print(f"       Correction : {correction}")
    else:
        print(f"\n  {VERT}✅ Aucun risque critique détecté !{RESET}")

    # Affiche les points positifs
    if positifs:
        print(f"\n  ✅ POINTS POSITIFS :")
        for point in positifs:
            print(f"     • {point}")

    # Résumé
    resume = resultat.get("resume", "")
    if resume:
        print(f"\n  📋 RÉSUMÉ :\n     {resume}")

    print(f"\n{'═' * 62}")


def sauvegarder_rapport(resultat: dict, chemin_fichier: str) -> str:
    """
    Sauvegarde le rapport JSON.
    Ce fichier est utilisé par :
    - Grafana (panneau "Rapport IA" du dashboard)
    - GitHub Actions (artefact téléchargeable)
    """
    rapport_complet = {
        "metadata": {
            "fichier_analyse":  str(Path(chemin_fichier).absolute()),
            "timestamp_utc":    datetime.now(timezone.utc).isoformat(),
            "modele_ia":        OLLAMA_MODEL,
            "environnement":    "VMware Workstation/Player",
            "os_vm":            "Ubuntu 22.04.3 LTS Desktop",
            "cpu_vm":           "Intel i5-6198DU (CPU-only, Nvidia 920MX non utilisé)",
            "ram_vm":           "10 GB",
            "venv_python":      "3.11.x (environnement isolé)"
        },
        **resultat
    }

    # Sauvegarde dans le dossier ai-agent/ (là où ce script est lancé)
    chemin_rapport = Path(__file__).parent / REPORT_FILE
    chemin_rapport.write_text(
        json.dumps(rapport_complet, indent=2, ensure_ascii=False),
        encoding="utf-8"
    )

    print(f"  📄 Rapport JSON sauvegardé : {chemin_rapport}")
    return str(chemin_rapport)


def main():
    """Point d'entrée principal du script."""

    afficher_banniere()

    # ── Vérifie les arguments de la ligne de commande ────────────
    if len(sys.argv) < 2:
        print(f"\n{ROUGE}❌ USAGE : python validator.py <chemin_config>{RESET}")
        print()
        print("  Exemples :")
        print("    python ai-agent/validator.py configs/postgresql.conf")
        print("    python ai-agent/validator.py configs/postgresql-bad.conf")
        print()
        print("  ⚠️  Assure-toi d'avoir activé le venv :")
        print("    source venv/bin/activate")
        sys.exit(1)

    chemin = sys.argv[1]
    path = Path(chemin)

    # ── Vérifie que le fichier existe ────────────────────────────
    if not path.exists():
        print(f"\n{ROUGE}❌ Fichier introuvable : {chemin}{RESET}")
        print("  Vérification :")
        print(f"    ls -la {path.parent}")
        sys.exit(1)

    print(f"\n  📂 Fichier : {path.name}")
    print(f"  📍 Chemin  : {path.absolute()}")

    # ── Lit le fichier ───────────────────────────────────────────
    try:
        contenu = path.read_text(encoding="utf-8")
        nb_lignes = len(contenu.splitlines())
        print(f"  📏 Lignes  : {nb_lignes}")
    except Exception as erreur:
        print(f"\n{ROUGE}❌ Lecture impossible : {erreur}{RESET}")
        sys.exit(1)

    # ── Détermine le type de fichier ─────────────────────────────
    if path.suffix == ".sql":
        type_fichier = "SQL Schema"
    elif "hba" in path.name:
        type_fichier = "pg_hba.conf (contrôle d'accès)"
    else:
        type_fichier = "postgresql.conf (configuration principale)"
    print(f"  📋 Type    : {type_fichier}")

    # ── Appelle Ollama et analyse ─────────────────────────────────
    prompt   = build_validation_prompt(contenu, type_fichier)
    brut     = appeler_ollama(prompt, SYSTEM_PROMPT)
    resultat = parser_reponse(brut)

    # ── Affiche et sauvegarde le rapport ─────────────────────────
    afficher_rapport(resultat, chemin)
    sauvegarder_rapport(resultat, chemin)

    # ── Exit code (lu par GitHub Actions) ────────────────────────
    verdict = resultat.get("verdict", "NON")

    if verdict == "OUI":
        print(f"\n  {VERT}{GRAS}✅ PIPELINE : DÉPLOIEMENT AUTORISÉ{RESET}")
        print("  ArgoCD va synchroniser automatiquement.\n")
        sys.exit(0)
    else:
        print(f"\n  {ROUGE}{GRAS}🚫 PIPELINE : DÉPLOIEMENT BLOQUÉ{RESET}")
        print("  Corrige les risques et re-pousse ton code.\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
