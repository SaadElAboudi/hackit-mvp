### Objectif
Conserver l’historique des recherches et permettre de marquer des résultats en favoris pour y revenir vite.

### Modèle (local-first)
- SearchEntry { id, query, createdAt, resultCount, durationMs }
- Favorite { id, videoId, title, channel, addedAt }
- Persistance: localStorage (web), SharedPreferences (mobile). Clé: hackit:v1:*.
- Rétention: max 50 recherches, max 50 favoris, LRU prune.

### UX
- Écran “Historique” listant les recherches (tap → recharger la requête).
- Icône ⭐ sur chaque résultat (toggle favori).
- Écran “Favoris” listant les vidéos étoilées.

### API/Backend
- Aucun besoin serveur au départ.

### Tests
- Ajout/suppression favoris persiste.
- Historique s’append et se prune au delà du quota.

### Suivi
- Milestone: 1 (Foundation)
- Labels: area:frontend, type:feature, priority:medium