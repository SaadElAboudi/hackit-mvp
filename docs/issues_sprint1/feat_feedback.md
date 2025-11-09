### Objectif
Capturer un feedback utilisateur par étape (👍 / 👎) pour préparer ranking et analytics.

### Modèle
- votes: Map<stepKey, +1|-1>, avec `stepKey = hash(messageId + index + stepText)`
- (v1) Local only; (v2) endpoint /feedback

### Comportement
- Un seul vote actif par step (cliquer à nouveau annule).
- Event analytics `step_feedback` {videoUrl, index, vote, query, ts} (local log ou manager analytics existant).

### UI
- Icônes compactes à droite de chaque step, avec état sélectionné.

### Edge cases
- Régénération → nouvelles keys → votes non remappés (v1 simple).

### Tests
- Toggle +1/0/-1 par step.
- Émissions analytics simulées.

### Suivi
- Milestone: 1 (Foundation)
- Labels: area:frontend, type:feature, priority:high