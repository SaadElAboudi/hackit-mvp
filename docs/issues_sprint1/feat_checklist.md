### Objectif
Permettre à l’utilisateur de cocher chaque étape comme réalisée (checklist interactive) pour suivre sa progression.

### Modèle
- Local state: checkedIndices: Set<number> par message (clé = messageId)
- Persistance: SharedPreferences/localStorage clé `checklist:<messageId>` → JSON array d’indices cochés

### Comportement
- Toggle par clic ou touche espace quand la step a le focus.
- (v1) Pas de synchronisation backend.
- (v1.1) Bouton "Tout décocher" / "Tout cocher" (optionnel)

### Accessibilité
- Role ARIA checkbox + label = texte de l’étape.
- Navigation clavier (tab + espace).

### Edge cases
- Régénération de résultat → messageId différent → checklist réinitialisée.
- Steps modifiées → ne pas tenter de remap (v1 simple).

### Tests
- Reload page conserve l’état.
- Toggle réversible.
- Steps vides → aucune checklist.

### Suivi
- Milestone: 1 (Foundation)
- Labels: area:frontend, type:feature, priority:high