# Guide d'utilisation rapide — Hackit MVP

## Démarrage

**Backend :**
```bash
cd backend && npm ci
cp .env.example .env   # configurer YT_API_KEY, GEMINI_API_KEY, MONGODB_URI
npm run dev
```

**Frontend Flutter :**
```bash
cd frontend_flutter && flutter pub get
flutter run -d chrome --web-port 8080
```

Paramétrage des clés API → [docs/secrets.md](docs/secrets.md)

## Navigation

L'application comporte **2 onglets** :

| Onglet | Description |
|--------|-------------|
| **Recherche** | Saisissez un brief professionnel → l'IA génère un plan structuré en streaming (cadrer, produire, communiquer, audit) avec vidéos sources et mode défi |
| **Salons** | Créez ou rejoignez un salon d'équipe — l'IA participe comme collaboratrice (`@ia`), peut défier des documents, respecte des directives |

## Fonctionnalités principales

- **Recherche structurée** : plan en 4 axes, sources vidéo YouTube, mode chall- **Recherche structurée** : plan en 4 axes, sources vidéo YouTube, mode chall- **Rechercheme- **Recherche structurée** : plan en 4 axnti- **Rechenyme généré localement — aucune inscription - **Recherche structurée** : plan en 4 axes, sources vidéo YouTube, moden - **Reche�gradati- **Recherche structues

- Commits explicites et atomiques
- Tests requis pour les modifications backend (`npm test`)
- Pour contribuer : fork → branche → pull request avec description claire

## Dépannage

- Vérifier les logs backend (`npm run dev`) et - Vérifier les logs b Confirmer les clés API dans `.env` (voir [docs/secrets.md](docs/secrets.md))
- Pour toute question : ouvrir une issue GitHub
