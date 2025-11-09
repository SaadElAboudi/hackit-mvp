### Objectif
Réduire la frustration en cas de lenteur/timeouts Gemini via un circuit breaker temporaire et un mode dégradé.

### Détection
- Incrémenter un compteur sur timeout/erreur réseau Gemini.
- Si 3 erreurs consécutives (fenêtre 2min) → breaker actif 5min.

### État & Exposition
- Variables mémoire: GEMINI_OPERATIONAL=false, breakerUntil=timestamp.
- /health, /health/extended: { gemini: { operational, breakerActive, retryAt } }.

### Comportement
- Quand breaker actif: ignorer reformulation/résumé IA → heuristique locale.
- Logs + métriques.

### UI
- HealthBadge: statut "Dégradé" avec tooltip “IA temporairement désactivée (latence)”.

### Tests
- Simulation 3 timeouts → breaker actif, retour à la normale après délai.
- /health/extended reflète l’état.

### Suivi
- Milestone: 1 (Foundation)
- Labels: area:backend, type:feature, priority:high