### Objectif
Ajouter des timestamps approximatifs à chaque étape du résumé pour activer des deeplinks vers la vidéo (ex: ?t=120).

### Contrat / Modèle
- Entrée: steps: string[]
- UI/API (optionnel): steps: [{ text: string, ts?: number }]
- Deeplink: clic ouvre la vidéo avec le paramètre t = secondes.

### Heuristique v1
- Si durée vidéo disponible: segment = floor(durée / max(steps.length, 1)); ts_i = i * segment
- Sinon: pas fixe de 20s → ts_i = i * 20
- Borne: 0 ≤ ts < durée quand connue

### Edge cases
- steps vide → pas de timestamps
- 1 step → ts=[0]
- Durée inconnue → pas de borne haute (0, 20, 40, ...)

### UI
- Puce discrète "t=0:40" à droite de la step; tooltip "Aller à l’instant".

### Validation
- 5 steps + 300s → [0, 60, 120, 180, 240]
- 2 steps sans durée → [0, 20]
- steps vide → aucun affichage

### Suivi
- Milestone: 1 (Foundation)
- Labels: area:frontend, type:feature, priority:high