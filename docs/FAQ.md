# FAQ Hackit MVP

## 1. Installation & Démarrage
**Q : Je n’arrive pas à lancer le backend, que faire ?**
- Vérifiez que Node.js est installé (`node -v`).
- Installez les dépendances avec `npm ci`.
- Vérifiez le fichier `.env` et les clés API.

**Q : Comment lancer le frontend Flutter ?**
- Installez Flutter (`flutter --version`).
- Dans `frontend_flutter`, lancez `flutter pub get` puis `flutter run -d chrome` ou sur mobile.

## 2. Fonctionnalités
**Q : Comment sauvegarder une réponse ?**
- Les résultats de l'onglet Recherche sont disponibles pendant la session. Pour conserver une réponse, copiez le texte ou partagez-le depuis l'interface.

**Q : Comment effacer l'historique de recherche ?**
- L'historique est stocké localement. Utilisez le bouton « Nouveau brief » dans l'onglet Recherche pour démarrer une nouvelle session, ou appuyez sur ✕ sur un message de la liste.

**Q : Puis-je utiliser l’app sans compte ?**
- Oui, le mode invité est disponible (userId anonyme sauvegardé localement).

**Q : Comment tester toutes les fonctionnalités sans inscription ?**
- Aucune inscription requise. L'application génère automatiquement un identifiant anonyme au premier lancement.

## 3. Dépannage
**Q : J’ai une erreur API ou clé manquante.**
- Vérifiez le fichier `.env` et les clés API (voir `docs/secrets.md`).

**Q : L’interface est vide ou bug.**
- Relancez le hot reload (Flutter) ou le serveur backend.
- Vérifiez les logs pour plus d’infos.

## 4. Contribution
**Q : Comment contribuer au projet ?**
- Forkez le repo, créez une branche, ouvrez une pull request avec description claire et tests si possible.

**Q : Quelles conventions respecter ?**
- Commits explicites, structure du projet, conventions Dart/Flutter et Node.js.

## 5. Divers
**Q : Où trouver la documentation complète ?**
- Consultez le README principal et les fichiers du dossier `docs/`.

**Q : Comment contacter l’équipe ?**
- Ouvrez une issue sur GitHub ou contactez via le canal indiqué dans le README.

---

Pour toute autre question, ouvrez une issue ou consultez la doc !
