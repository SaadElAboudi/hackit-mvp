# Hackit 2.0 â€” Plan produit & technique

> Workspace conversationnel avec IA collègue  
> Dernière mise Ã  jour : 11 avril 2026

---

## Résumé

Le socle temps réel (Rooms/Salons) est fonctionnel, mais le produit est fragmenté :
- un chat collaboratif sans IA partagée
- une IA privée en panneau latéral (BYOK supprimé)
- un moteur de recherche backend plus mature que le frontend
- des modèles `Thread/Version/RoomArtifact` définis mais pas encore exposés côté UI

**Décision produit :** faire de Hackit un **ChatGPT collaboratif pour pros** â€” des channels partageables oÃ¹ l'IA est un coéquipier visible par tous, capable de discuter, synthétiser, transformer un échange en document et enrichir le channel avec de la recherche sourcée.

**Positionnement :** _"un channel = une équipe, un contexte, une mémoire, une IA collègue"_

**Critère de succès v1 :** créer un channel, inviter quelqu'un, obtenir en moins de 3 minutes un premier livrable partagé, révisable et traÃ§able par toute l'équipe.

---

## Spécification fonctionnelle

### Objet principal
Le produit n'est plus un _"chat privé avec option partage"_, mais un **channel partagé** avec membres, présence, historique, mémoire et IA commune.

### Modes IA
| Mode | Description | Priorité |
|---|---|---|
| **Shared AI** | Réponses visibles par tous dans le channel | MVP |
| **Private Draft** | Brouillon personnel avant envoi | Post-MVP |

### Commandes coeur
| Commande | Action |
|---|---|
| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| `@ia` | L'| décisions, risques et next steps |

### Types d'artefacts
- Messages de conversation (`text`, `ai`, `system`)
- Documents/canvases versionnés (`artifact`)
- Cartes de recherche avec citations (`research`)
- Décisions et actions extraites (`decision`)
- Mémoire épinglée de channel

### Parcours utilisateur cible
1. Créer 1. Créer 1. Créer 1. Créer 1. Créer 1. Créer 1. Créer 1. Créer 1. Créer 1.avec `@ia` ou `/commande`
5. Générer un document partagé (`/doc`)
6. Commenter / 6. Commenter / 6. Commenter / 6. r une révision IA
8. Conserver une version validée
9. Réutiliser la mémoire et les9. Réutiliser la mémoire et les9. Réutiliser la mémoire et le"en9. Réutiliser nterv9. Réutiliser la mÃmention, com9. Réutiliser la mémoire et les9. Réutiliser la mémoire et les9. Réutiliser la mémoire et le"en9. Réutiliser nterv9. Réutiliser la mÃmention, com9. Réutiliser la mémoire et les9. Réutiliser la mémoire et les9. Réutiliser la mémoire et le"en9. Réutiliser nterv9. Réutiliser la mÃmention, com9. Réutiliser la l'a9. Réutiliser la mÃt/Thread/Version` (dépendance `Project` absente, non routé)
- Réutiliser les idées `Thread/Version` via des objets **room-scoped**

### Modèles de données

#### Room
```ts
{
  id, name, description,
  purpose: string,          purpose: string,          pity: 'public'|'private',  // ajouté
  ownerId: string,                 // ajouté
  pinnedArtifactId?: string,       //  pinnedArtifactId?: string,       //  pi    pinnedArtifactId?: strinber[],
  createdAt: Date
}
```

#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#### Room#### nd# s#### Room#### Room#### Room#### Room#### nd#### Room#### Room#### Room#`ts#### id, roomId, content,
  type: 'fact'|'de  type: 'fact'|'de  typ createdBy: string,
  createdAt: Date
}
```

### API REST v1

| Méthode | Route | Description |
|---|---|---|
| `GET/POST` | `/api/rooms` | Lister / créer un channel |
| `GET` | `/api/rooms/:id/messages` | Historique |
| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench| `POST` | `/api/rooms/:id/messages` | Envoyer (déd/invite` | Lien d'invitati| `POST` | `/api/rooms/:id/messages` | Envoyer (déclench|---| `POST` | `/apiNouveau message |
| `typing` | Indicateur de saisie |
| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pfact c| `pres| `pres| `prex| `pres| `pres| `prex|ted` | N| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pfact c| `pres| `pres| `prex| `pres| `pres| `prex|ted` | N| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pfact c| `pres| `pres| `prex| `pres| `pres| `prex|ted` | N| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pfact c| `pres| `pres| `prex| `pres| `pres| `prex|ted` | N| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pfact c| `pres| `pres| `prex| `pres| `pres| `prex|ted` | N| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pfact c| `pres| `pres| `prex| `pres| `pres| `prex|ted` | N| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pres| `prex| `pres| `pfact c| `pres| `pres| `prex| `pres| `pres| `prex|ted` | N| `pres| `pres| `prex| `pres| `pres| `prex|l'IA a répondu et sur quelle base

---

## Ã‰tat d'avancement (11 avril 2026)

### Backend â€” Implémenté âœ…
- `Room.js` â€” champs étendus (`purpose`, `visibility`, `ownerId`, `lastActivityAt`)
- `RoomMessage.js` â€” types étendus
- `RoomArtifact.js` + `ArtifactVersion.js` â€” modèles créés
- `RoomMission.js` + `RoomMemory.js` â€” modèles créés
- `roomOrchestrator.js` â€” orchestrateur unifié branché (`triggerRoomAutomation`, `parseRoomCommand`, handlers par commande)
- `rooms.js` â€” routes `/artifacts`, `/missions`, `/memory`, `/decisions`, `/search`, `/invite`
- `roomWS.js` â€” events normalisés, orchestrateur intégré
- `/api/ai/chat` â€” endpoint copilote privé (backup, via `gemini-2.0-flash-lite`)

### Flutter â€” Implémenté âœ…
- `room.dart` â€” modèle mis Ã  jour
- `room_provider.dart` â€” nouveaux events WS gérés
- `room_service.dart` â€” appels API artifacts/missions/memory
- `salon_chat_screen.dart` â€” support `@ia` + `/commandes`
- `salons_screen.dart` â€” renommage UI "Channels"

### Non encore implémenté âŒ
**********************************es ré************************réponse **********************************es ré************************réponse ********les `o**********************************eutorisation par room

**Flutter :**
- Modèles Dart `RoomArtifact`, `ArtifactVersion`, `RoomMission`, `RoomMemory`
- Layout 3 panneaux (liste / conversation / panneau contextuel)
- Widgets `ArtifactCard`, `ResearchCard`, `DecisionCard`, `MissionCard`
- Vue Canvas (affichage + révision d'artefact)
- Composer avec autocomplete `@mention` et `/slash`
- Rebuild web + redéploiement gh-pages

---

## Feuille de route

### Phase 0 â€” Réalignement produit âœ… _terminée_
- Naming "Channels" en UI
- Suppression BYOK (clé Gemini côté utilisateur)
- IA routée via backend

### Phase 1 â€” Shared AI MVP ðŸ”„ _en cours_
> Objectif : `@ia` répond dans le channel, visible par tous

- [x] Orchestrateur backend
- [x] Parsing commandes côté serveur
- [x] Persistance messages IA dans le channel
- [ ] Streaming WS des réponses IA
- [ ] `POST /missions` côté client Flutter
- [ ] Middleware rôles/permissions
- [ ] Modèles Dart `RoomArtifact`, `RoomMission`, `RoomMemory`
- [ ] Rebuild Flutter + déploiement

### Phase 2 â€” Canvas et versioning
> Objectif : `/doc` crée un canvas versionné partagé

- [ ] Vue Canvas Flutter (lecture + révision)
- [ ] Widget artefact dans le flux de messages- [ ] Widget artefact dans le flux de messages- [ ] Widget artefact daact_version_created`

### Phase 3 â€” Recherche collaborative
> Objectif : `/search` insère des cartes sourcées dans le channel

- [ ] Brancher mo- [ ] Brancher mo-cri- [ ] Brancher mo- [ ] Brancher mo-cri- [ ] Brancherment implémenté)
- [ ] Widget `ResearchCard` avec citations cliquables
- [ ] Mémoire du channel alimentée par artefacts et décisions
- [ ] "Jump to source" dans le flux

### Phase 4 â€” Proactivité contrôlée _(post-PMF)_
- Suggestions de synthèse automatiques
- Briefs avant réunion
- Intégrations Notion / Slack / Drive
- Agents spécialisés par mission

---

## Scénarios de test cibles

| Scénario | Critère de succès |
|---||---||---||---||---||---||---||---||---||---||---||---||---||-, |---||---||---||---||---||---||---|'artefact |
| `/doc` | Crée un artefact versionné sans écraser l'historique |
| Révision après challenge | Nouvelle version créée, ancienne consultable |
| `/search` | Sources cliquables, horodatées, traÃ§ables dans le flux |
| Mémoire | Influence les réponses suivantes, inspectable et supprimable |
| Permissions | Non-membre ne peut pas accéder Ã  l'historique, aux artefacts ni aux missions |
| Réseau | Reconnexion WS, déduplication messages, retry IA couverts par tests |

---

## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #te## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #te## ## re## ## ## ## ## ## ## ## ## ## ## #te |
| Autonomie IA | Sur demande uniquement (MVP) |
| No| No| No| No| No| No| No| No| No| No| er| No| No| No| No| No| he| No| No| No| No| No| No| No| No| No|apacité collaborative, pas abandonnée |
| Clé API Gemini | Côté back| Clé API Gemini | Côté back| Cé client |
