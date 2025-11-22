# Guide d'utilisation rapide Hackit MVP

## 1. Démarrage
- Installez les dépendances :
  - Backend : `npm ci` dans le dossier `backend`
  - Frontend Flutter : `flutter pub get` dans `frontend_flutter`
- Configurez vos clés API dans `.env` (voir `docs/secrets.md`).
- Lancez le backend : `npm start` dans `backend`
- Lancez le frontend : `flutter run -d chrome` ou sur mobile

## 2. Fonctionnalités principales
- **Recherche** : Posez une question dans le chat, obtenez une réponse AI + vidéos pertinentes.
- **Favoris** : Ajoutez/supprimez des vidéos en favoris (badge AppBar, accès rapide).
- **Historique** : Consultez et gérez vos recherches passées.
- **Mode invité** : Utilisation sans compte, userId anonyme sauvegardé localement.
- **Mode démo** : Test complet avec un JWT pour le user demo.

## 3. Navigation
- Accès direct aux écrans Home, Leçons, Favoris, Historique via la barre de navigation.
- Headers premium sur chaque écran pour une expérience cohérente.

## 4. Bonnes pratiques
- Utilisez des commits clairs et explicites.
- Respectez la structure du projet et les conventions de code.
- Pour contribuer, ouvrez une pull request avec description et tests si possible.

## 5. Dépannage
- Consultez les logs backend et frontend en cas de problème.
- Vérifiez la configuration des clés API et du `.env`.
- Pour toute question, ouvrez une issue sur GitHub.

---

Pour plus de détails, consultez le README principal et les fichiers du dossier `docs/`.
