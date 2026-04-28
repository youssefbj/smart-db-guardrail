"""
test_validator.py — Tests unitaires de l'agent IA.

Ces tests ne nécessitent PAS Ollama.
Ils testent uniquement la logique Python (lecture de fichiers,
parsing de la réponse, etc.).

Usage :
    source venv/bin/activate
    python ai-agent/test_validator.py
"""

import sys
import unittest
from pathlib import Path

# Ajoute le dossier ai-agent au chemin Python
sys.path.insert(0, str(Path(__file__).parent))

from validator import parser_reponse


class TestParserReponse(unittest.TestCase):
    """Tests pour la fonction parser_reponse."""

    def test_verdict_oui_format_correct(self):
        """Une réponse OUI bien formée doit être correctement parsée."""
        reponse = (
            'VERDICT: OUI\n'
            '{"verdict": "OUI", "score_securite": 87, "risques": [], '
            '"points_positifs": ["ssl on", "scram-sha-256"], '
            '"recommandations": [], "resume": "Configuration sécurisée."}'
        )
        resultat = parser_reponse(reponse)
        self.assertEqual(resultat["verdict"], "OUI")
        self.assertEqual(resultat["score_securite"], 87)
        self.assertEqual(len(resultat["risques"]), 0)

    def test_verdict_non_avec_risques(self):
        """Une réponse NON avec risques doit être correctement parsée."""
        reponse = (
            'VERDICT: NON\n'
            '{"verdict": "NON", "score_securite": 10, '
            '"risques": [{"niveau": "CRITIQUE", "description": "SSL off",'
            '"ligne_config": "ssl = off", "correction": "ssl = on"}],'
            '"points_positifs": [], "recommandations": ["ssl = on"],'
            '"resume": "Configuration dangereuse."}'
        )
        resultat = parser_reponse(reponse)
        self.assertEqual(resultat["verdict"], "NON")
        self.assertEqual(len(resultat["risques"]), 1)
        self.assertEqual(resultat["risques"][0]["niveau"], "CRITIQUE")

    def test_verdict_par_defaut_non(self):
        """Si aucun verdict clair, retourne NON par sécurité."""
        resultat = parser_reponse("Je ne sais pas analyser ce fichier.")
        self.assertEqual(resultat["verdict"], "NON")

    def test_verdict_insensible_casse(self):
        """Le VERDICT doit être détecté même en minuscules."""
        reponse = (
            'verdict: oui\n'
            '{"verdict": "OUI", "score_securite": 75, '
            '"risques": [], "points_positifs": [],'
            '"recommandations": [], "resume": "OK."}'
        )
        resultat = parser_reponse(reponse)
        self.assertEqual(resultat["verdict"], "OUI")

    def test_json_virgule_finale(self):
        """Gère les virgules finales (erreur fréquente de phi3:mini)."""
        reponse = (
            'VERDICT: OUI\n'
            '{"verdict": "OUI", "score_securite": 80, '
            '"risques": [], "points_positifs": ["ssl on",],'
            '"recommandations": [], "resume": "OK."}'
        )
        resultat = parser_reponse(reponse)
        self.assertIn(resultat["verdict"], ["OUI", "NON"])


class TestFichiersConfiguration(unittest.TestCase):
    """Tests qui vérifient les fichiers de configuration créés en Phase 4."""

    base = Path(__file__).parent.parent / "configs"

    def test_bonne_config_existe(self):
        """Le fichier postgresql.conf sécurisé doit exister."""
        chemin = self.base / "postgresql.conf"
        self.assertTrue(chemin.exists(), f"Fichier manquant : {chemin}")

    def test_mauvaise_config_existe(self):
        """Le fichier postgresql-bad.conf dangereux doit exister."""
        chemin = self.base / "postgresql-bad.conf"
        self.assertTrue(chemin.exists(), f"Fichier manquant : {chemin}")

    def test_bonne_config_ssl_on(self):
        """La bonne config doit avoir ssl = on."""
        contenu = (self.base / "postgresql.conf").read_text()
        self.assertIn("ssl = on", contenu)

    def test_mauvaise_config_ssl_off(self):
        """La mauvaise config doit avoir ssl = off."""
        contenu = (self.base / "postgresql-bad.conf").read_text()
        self.assertIn("ssl = off", contenu)

    def test_bonne_config_scram(self):
        """La bonne config doit utiliser scram-sha-256."""
        contenu = (self.base / "postgresql.conf").read_text()
        self.assertIn("scram-sha-256", contenu)

    def test_mauvaise_config_md5(self):
        """La mauvaise config doit utiliser md5 (dangereux)."""
        contenu = (self.base / "postgresql-bad.conf").read_text()
        self.assertIn("md5", contenu)

    def test_bonne_config_listen_localhost(self):
        """La bonne config doit écouter seulement sur localhost."""
        contenu = (self.base / "postgresql.conf").read_text()
        self.assertIn("listen_addresses = 'localhost'", contenu)

    def test_mauvaise_config_listen_partout(self):
        """La mauvaise config doit écouter sur tout Internet (dangereux)."""
        contenu = (self.base / "postgresql-bad.conf").read_text()
        self.assertIn("listen_addresses = '*'", contenu)


if __name__ == "__main__":
    print("🧪 Tests unitaires — VMware Ubuntu 22.04 / Python 3.11\n")
    suite = unittest.TestSuite()
    for cls in [TestParserReponse, TestFichiersConfiguration]:
        suite.addTests(unittest.TestLoader().loadTestsFromTestCase(cls))

    runner  = unittest.TextTestRunner(verbosity=2)
    resultat = runner.run(suite)

    print()
    if resultat.wasSuccessful():
        print("✅ Tous les tests sont passés !")
    else:
        print(f"❌ {len(resultat.failures + resultat.errors)} test(s) échoué(s)")
        print("   Vérifie que les fichiers configs/ ont bien été créés (Phase 4).")

    sys.exit(0 if resultat.wasSuccessful() else 1)
