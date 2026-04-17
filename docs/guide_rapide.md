# Guide Rapide - Hackit MVP

## Démarrage local

Backend:

```bash
cd backend
npm ci
cp .env.example .env
npm run dev
```

Frontend Flutter (web):

```bash
cd frontend_flutter
flutter pub get
flutter run -d chrome --web-port 8080
```

Configuration des secrets :
- `docs/secrets.md`

## Parcours produit (MVP actuel)

Hackit est centré sur les canaux collaboratifs (`Salons`) :
1. Créer ou rejoindre un salon.
2. Envoyer des messages à plusieurs.
3. Solliciter l'IA via `@ia` ou les commandes slash.
4. Produire un livrable partagé (document, décision, brief, recherche, mission).
5. Partager vers Slack ou Notion si intégration active.

## Commandes principales

- `@ia` : réponse IA visible par tous dans le salon.
- `/doc` : générer un artefact partagé.
- `/search` : ajouter une recherche sourcée au salon.
- `/decide` : extraire décisions, risques et next steps.
- `/brief` : produire un brief avant réunion.
- `/mission` : lancer une mission IA (profil spécialisé possible).
- `/share slack` ou `/share notion` : exporter un résumé vers une intégration connectée.

## Ce qui est déjà branché

- Temps réel via WebSocket pour messages et événements de salon.
- Suggestions proactives (synthèse et brief) avec garde-fous.
- Intégrations Slack et Notion (connect/disconnect/share/export).
- Missions spécialisées (`auto`, `strategist`, `researcher`, `facilitator`, `analyst`, `writer`).

## Tests utiles

```bash
# backend
cd backend && npm test

# flutter
cd frontend_flutter && flutter analyze
cd frontend_flutter && flutter test -r compact
```

## Documentation de référence

- `README.md`
- `codex.md`
- `docs/architecture.md`
- `docs/implementation_roadmap.md`
