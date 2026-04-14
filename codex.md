# Hackit 2.0 — Workspace conversationnel avec IA collègue

> Dernière mise à jour : 11 avril 2026

---

## Résumé

Le socle temps réel `Salons` est déjà réel et utile, mais le produit était fragmenté entre un chat collaboratif, une IA privée en panneau latéral, un backend de recherche plus mature que le frontend, et un embryon `Thread/Version` non exposé.

**Décision produit :** faire de Hackit un **ChatGPT collaboratif pour pros**, centré sur des **channels partageables**, où l'IA est un **coéquipier visible par tous** quand on la sollicite, capable de discuter, synthétiser, transformer un échange en document, et enrichir le channel avec de la recherche sourcée.

**Positionnement :** _"un channel = une équipe, un contexte, une mémoire, une IA collègue"_

**Critère de succès v1 :** créer un channel, inviter quelqu'un, obtenir en moins de 3 minutes un premier livrable partagé, révisable et traçable par toute l'équipe.

---

## Spécification fonctionnelle

### Objet principal
Le produit n'est plus un "chat privé avec option partage", mais un **channel partagé** avec membres, présence, historique, mémoire et IA commune.

### Modes IA
| Mode | Description | Priorité |
|---|---|---|
| **Shared AI** | Réponses visibles par tous dans le channel | MVP |
| **Private Draft** | Brouillon personnel avant envoi | Post-MVP |

### Commandes cœur
| Commande | Action |
|---|---|
| `@ia` | L'IA répond dans le channel, visible de tous |
| `/doc` | Transformer un échange en document/canvas partagé |
| `/mission` | Assigner une tâche cadrée à l'IA |
| `/search` | Lancer une recherche sourcée dans le channel |
| `/decide` | Extraire décisions, risques et next steps |

### Types d'artefacts
- Messages de conversation (`text`, `ai`, `system`)
- Documents/canvases versionnés (`artifact`)
- Cartes de recherche avec citations (`research`)
- Décisions et actions extraites (`decision`)
- Mémoire épinglée de channel

### Parcours utilisateur cible
1. Créer un channel
2. Inviter des membres
3. Échanger en temps réel
4. Interpeller l'IA avec `@ia` ou `/commande`
5. Générer un document partagé (`/doc`)
6. Commenter / challenger ce document
7. Demander une révision IA
8. Conserver une version validée
9. Réutiliser la mémoire et les sources du channel

### Règle d'autonomie
L'IA n'agit jamais "en douce" ; elle intervient sur mention, commande ou mission explicite, puis propose des actions structurées à valider.

---

## Spécification technique

### Architecture
- Conserver `rooms` comme socle backend v1 pour ne pas casser l'existant, mais exposer le mot **Channels** côté produit/UI.
- Ne pas réactiver le vieux chemin `Project/Thread/Version` : il dépend d'un `Project` absent et n'est pas routé. Réutiliser ses bonnes idées via des objets **room-scoped**.

### Modèles de données

#### Room
```ts
{
  id, name, description,
  purpose: string,
  visibility: 'public' | 'private',
  ownerId: string,
  pinnedArtifactId?: string,
  lastActivityAt: Date,
  members: Member[],
  createdAt: Date
}
```

#### RoomMessage
```ts
{
  id, roomId, senderId, senderName,
  isAI: boolean,
  content: string,
  type: 'text' | 'ai' | 'artifact' | 'research' | 'decision' | 'system',
  createdAt: Date
}
```

#### RoomArtifact
```ts
{
  id, roomId, title, content,
  type: 'document' | 'canvas',
  currentVersion: number,
  createdBy: string,
  createdAt: Date
}
```

#### ArtifactVersion
```ts
{
  id, artifactId, roomId,
  content: string,
  version: number,
  sourcePrompt?: string,
  status: 'draft' | 'validated',
  createdBy: string,
  createdAt: Date
}
```

#### RoomMission
```ts
{
  id, roomId, prompt,
  status: 'queued' | 'running' | 'done' | 'failed',
  createdBy: string,
  createdAt: Date
}
```

#### RoomMemory
```ts
{
  id, roomId, content,
  type: 'fact' | 'decision' | 'preference',
  createdBy: string,
  createdAt: Date
}
```

### API REST v1

| Méthode | Route | Description |
|---|---|---|
| `GET/POST` | `/api/rooms` | Lister / créer un channel |
| `GET` | `/api/rooms/:id/messages` | Historique |
| `POST` | `/api/rooms/:id/messages` | Envoyer (déclenche orchestrateur IA si mention/commande) |
| `GET/POST` | `/api/rooms/:id/artifacts` | Artefacts du channel |
| `GET/POST` | `/api/rooms/:id/missions` | Missions IA |
| `GET/POST` | `/api/rooms/:id/memory` | Mémoire épinglée |
| `GET` | `/api/rooms/:id/search` | Recherche dans le channel |
| `GET` | `/api/rooms/:id/decisions` | Décisions extraites |
| `POST` | `/api/rooms/:id/invite` | Lien d'invitation |

### Events WebSocket
| Event | Description |
|---|---|
| `message` | Nouveau message (user ou IA) |
| `message_chunk` | Fragment de réponse IA en streaming |
| `typing` | Indicateur de saisie |
| `presence` | Connexion/déconnexion d'un membre |
| `artifact_created` | Nouvel artefact dans le channel |
| `artifact_version_created` | Nouvelle version d'un artefact |
| `mission_status` | Changement de statut d'une mission |
| `decision_created` | Décision extraite par l'IA |
| `research_attached` | Résultats de recherche joints au channel |

### Frontend
- Layout desktop-first en 3 panneaux : liste des channels · conversation · panneau contextuel (artifacts/memory/members)
- Composer enrichi avec mentions `@` et slash commands `/`
- Vue "Canvas" par channel (lecture + révision)
- Cartes de recherche et citations dans le flux du channel, pas dans une feature isolée

### Garde-fous
- Identité anonyme + invitations pour MVP
- Rôles simples `owner / member / guest`
- Audit log minimal des actions IA
- Message système expliquant pourquoi l'IA a répondu et sur quelle base

---

## État d'avancement (11 avril 2026)

### Backend ✅
- `Room.js` — champs étendus (`purpose`, `visibility`, `ownerId`, `lastActivityAt`)
- `RoomMessage.js` — types étendus
- `RoomArtifact.js` + `ArtifactVersion.js` — modèles créés
- `RoomMission.js` + `RoomMemory.js` — modèles créés
- `roomOrchestrator.js` — orchestrateur unifié (`triggerRoomAutomation`, `parseRoomCommand`, handlers par commande, streaming avec `tryGeminiStreaming`)
- `gemini.js` — `streamWithGemini()` via SSE `?alt=sse`, throttle 80ms
- `roomWS.js` — events normalisés + `broadcastRoomMessageChunk()`
- `rooms.js` — routes `/artifacts`, `/missions`, `/memory`, `/decisions`, `/search`, `/invite` ; permissions `isRoomOwner` sur add-member, owner-or-creator sur delete-memory
- `/api/ai/chat` — endpoint copilote privé (backup, via `gemini-2.0-flash-lite`)

### Flutter ✅
- `room.dart` — modèles `Room`, `RoomMessage`, `RoomArtifact`, `RoomMission`, `RoomMemory` ; `WsRoomEventType` incl. `messageChunk` avec getters `tempId`/`delta`
- `room_provider.dart` — handlers WS : `message`, `messageChunk` (streaming placeholder), `typing`, `artifact`, `mission`, `memory`, `decision`
- `room_service.dart` — appels API artifacts/missions/memory ; `postMission()`
- `salon_chat_screen.dart` — support `@ia` + `/commandes`, `_showLaunchMissionDialog`, `_SystemEventChip`
- `salons_screen.dart` — renommage UI "Channels"

---

## Feuille de route

### Phase 0 — Réalignement produit ✅ _terminée_
- [x] Naming "Channels" en UI
- [x] Suppression BYOK (clé Gemini côté utilisateur)
- [x] IA routée via backend

### Phase 1 — Shared AI MVP ✅ _terminée_
> Objectif : `@ia` répond dans le channel, visible par tous

- [x] Orchestrateur backend
- [x] Parsing commandes côté serveur
- [x] Persistance messages IA dans le channel
- [x] Streaming WS des réponses IA (`message_chunk` events, throttle 80ms, fallback non-streaming → heuristique)
- [x] `POST /missions` côté client Flutter (`postMission` / `createMission` / dialog)
- [x] Middleware rôles/permissions (`isRoomOwner` sur add-member, owner-or-creator sur delete-memory)
- [x] Modèles Dart `RoomArtifact`, `RoomMission`, `RoomMemory`
- [x] Rebuild Flutter + déploiement (`54d53da` gh-pages, `fe8799c` main)

### Phase 2 — Canvas et versioning ✅ _terminée_
> Objectif : `/doc` crée un canvas versionné partagé

- [x] Vue Canvas Flutter (lecture + révision d'artefact)
- [x] Widget `ArtifactCard` dans le flux de messages
- [x] Composer `/doc` → crée `RoomArtifact` + `ArtifactVersion`
- [x] Système de commentaires / challenges sur un artefact
- [x] Révision IA d'un artefact → nouvelle `ArtifactVersion`
- [x] Version validée consultable (historique versions)
- [x] Panneau contextuel droit (artifacts / memory / members)
- [x] Event WS `artifact_version_created` branché côté Flutter

### Phase 3 — Recherche collaborative ✅ _implémentée_
> Objectif : `/search` insère des cartes sourcées dans le channel

- [x] Brancher le moteur search/transcript/citations existant dans les channels
- [x] Widget `ResearchCard` avec citations cliquables
- [x] Mémoire du channel alimentée par artefacts et décisions
- [x] "Jump to source" dans le flux
- [x] Event WS `research_attached` côté Flutter

_Note qualité_: les prochains points restants sont surtout des tests E2E multi-clients (WS + persistance room search).

### Phase 4 — Proactivité contrôlée (post-PMF)
- [x] Suggestions de synthèse automatiques
- [x] Briefs automatiques avant réunion
- [x] Intégrations Slack (connect/disconnect/share, `/share slack`, REST routes, WS event, 16 tests)
- [x] Intégrations Slack (connect/disconnect/share, `/share slack`, REST routes, WS event, 16 tests)
- [x] Intégration Notion (connect/disconnect/export, `/share notion`, markdown→blocks, REST routes, WS event, 18 tests)
- [x] Agents spécialisés par mission

---

## Tests et scénarios cibles
- Deux utilisateurs dans un même channel voient la même réponse `@ia`, le même typing indicator, la même version de document et les mêmes commentaires.
- Une commande `/doc` crée un artefact versionné sans écraser l'historique.
- Une révision IA après challenge crée une nouvelle version et garde la précédente consultable.
- Une commande `/search` joint au channel des sources cliquables, horodatées et traçables.
- La mémoire du channel influence les réponses suivantes, mais peut être inspectée et supprimée.
- Les permissions empêchent un non-membre d'accéder à l'historique, aux artefacts et aux missions.
- Reconnexion WebSocket, duplication de messages et retry IA sont couverts par tests d'intégration.

---

## Hypothèses et choix par défaut
- Cible prioritaire : **grand public pro**
- Surface prioritaire : **web desktop-first**, mobile ensuite
- Modèle d'autonomie : **IA sur demande uniquement** dans le MVP
- Nommage produit : **Channels** en UI, `rooms` conservé en backend tant que la migration n'apporte pas de valeur claire
- La recherche existante n'est pas abandonnée : elle devient une **capabilité collaborative** intégrée au channel, ce qui différencie Hackit d'un simple clone de ChatGPT
