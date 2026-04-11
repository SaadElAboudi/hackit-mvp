Plan

Hackit 2.0 — Workspace conversationnel avec IA collègue
Résumé
Audit repo: le socle temps réel Salons est déjà réel et utile, mais le produit est aujourd’hui fragmenté entre un chat collaboratif, une IA privée en panneau latéral, un backend de recherche plus mature que le frontend, et un embryon Thread/Version non exposé. Les docs et le code ne racontent plus la même histoire.
Décision produit: faire de Hackit un ChatGPT collaboratif pour pros, centré sur des channels partageables, où l’IA est un coéquipier visible par tous quand on la sollicite, capable de discuter, synthétiser, transformer un échange en document, et enrichir le channel avec de la recherche sourcée.
Positionnement: “un channel = une équipe, un contexte, une mémoire, une IA collègue”.
Critères de succès v1: créer un channel, inviter quelqu’un, obtenir en moins de 3 minutes un premier livrable partagé, révisable et traçable par toute l’équipe.
Spécification fonctionnelle
Objet principal: le produit n’est plus un “chat privé avec option partage”, mais un channel partagé avec membres, présence, historique, mémoire et IA commune.
L’IA a deux modes seulement:
Shared AI par défaut dans le channel, visible de tous.
Private Draft Mode conservé en secondaire plus tard, pas comme expérience principale.
Commandes cœur du MVP:
@ia pour répondre dans le channel.
/doc pour transformer un échange en document/canvas.
/mission pour assigner une tâche cadrée à l’IA.
/search pour lancer une recherche sourcée dans le channel.
/decide pour extraire décisions, risques et next steps.
Types d’artefacts à supporter:
messages de conversation,
documents/canvases versionnés,
cartes de recherche avec citations,
décisions et actions extraites,
mémoire épinglée de channel.
Parcours utilisateur cible:
créer un channel,
inviter des membres,
échanger en temps réel,
interpeller l’IA à la demande,
générer un document partagé,
commenter/challenger ce document,
demander une révision IA,
conserver une version validée,
réutiliser ensuite la mémoire et les sources du channel.
Règle d’autonomie: l’IA n’agit jamais “en douce”; elle intervient sur mention, commande ou mission explicite, puis propose des actions structurées à valider.
Spécification technique
Décision d’architecture: conserver rooms comme socle backend v1 pour ne pas casser l’existant, mais exposer le mot Channels côté produit/UI.
Ne pas réactiver le vieux chemin Project/Thread/Version tel quel: il dépend d’un Project absent et n’est pas routé. Réutiliser ses bonnes idées en créant des objets room-scoped.
Nouvelles interfaces/types:
Room: ajouter purpose, visibility, ownerId, pinnedArtifactId, lastActivityAt.
RoomMessage: étendre type en text | ai | artifact | research | decision | system.
RoomArtifact: document/canvas rattaché à un roomId.
ArtifactVersion: version immutable d’un artefact, avec auteur, source prompt, statut, commentaires.
RoomMission: demande explicite à l’IA avec statut queued | running | done | failed.
RoomMemory: faits/prefs/décisions épinglés et réinjectés dans le contexte IA.
Backend à construire:
un AI Orchestrator unique pour remplacer la séparation actuelle entre IA privée et IA de salon;
parsing des mentions/commandes côté serveur;
contexte partagé du channel: derniers messages + artefacts épinglés + mémoire + résultats de recherche;
streaming des réponses IA via WebSocket déjà en place;
réutilisation du backend search/transcript/citations existant comme outil interne de l’IA et commande /search.
API v1 recommandée:
garder /api/rooms et ajouter /api/rooms/:id/artifacts
/api/rooms/:id/missions
/api/rooms/:id/memory
/api/rooms/:id/search
/api/rooms/:id/decisions
Events WebSocket à normaliser:
message
typing
presence
artifact_created
artifact_version_created
mission_status
decision_created
research_attached
Frontend cible:
layout desktop-first en 3 panneaux: liste des channels, conversation, panneau contextuel (artifacts/memory/members);
composer enrichi avec mentions et slash commands;
vue “Canvas” par channel;
les cartes de recherche et citations doivent vivre dans le flux du channel, pas dans une feature isolée.
Garde-fous:
identité anonyme + invitations pour MVP,
rôles simples owner/member/guest,
audit log minimal des actions IA,
message system expliquant pourquoi l’IA a répondu et sur quelle base.
Feuille de route
Phase 0, 1 à 2 semaines: réaligner le produit.
Mettre à jour docs/UI naming.
Choisir “Channels + IA collègue” comme histoire produit unique.
Déprécier l’IA privée comme expérience principale.
Phase 1, 3 à 4 semaines: Shared AI MVP.
Réactiver l’IA visible par tous dans les rooms.
Ajouter commandes @ia, /mission, /decide.
Persister statut IA, traces et contexte partagé.
Phase 2, 4 à 5 semaines: Canvas et versioning.
Introduire RoomArtifact et ArtifactVersion.
Transformer documents uploadés et réponses IA en canvases.
Ajouter commentaires/challenges, révisions et version validée.
Phase 3, 4 à 5 semaines: Recherche collaborative.
Brancher le moteur search/transcript/citations existant dans les channels.
Ajouter cartes de recherche, sources, citations et “jump to source”.
Alimenter la mémoire du channel à partir des artefacts et décisions.
Phase 4, après PMF initial: proactivité contrôlée.
suggestions de synthèse,
briefs automatiques avant réunion,
intégrations Notion/Slack/Drive,
agents spécialisés par mission.
Tests et scénarios
Deux utilisateurs dans un même channel voient la même réponse @ia, le même typing, la même version de document et les mêmes commentaires.
Une commande /doc crée un artefact versionné sans écraser l’historique.
Une révision IA après challenge crée une nouvelle version et garde la précédente consultable.
Une commande /search joint au channel des sources cliquables, horodatées et traçables.
La mémoire du channel influence les réponses suivantes, mais peut être inspectée et supprimée.
Les permissions empêchent un non-membre d’accéder à l’historique, aux artefacts et aux missions.
Reconnexion WebSocket, duplication de messages et retry IA sont couverts par tests d’intégration.
Hypothèses et choix par défaut
Cible prioritaire: grand public pro.
Surface prioritaire: web desktop-first, mobile ensuite.
Modèle d’autonomie: IA sur demande uniquement dans le MVP.
Nommage produit: Channels en UI, rooms conservé en backend tant que la migration n’apporte pas de valeur claire.
La recherche existante n’est pas abandonnée: elle devient une capabilité collaborative intégrée au channel, ce qui différencie Hackit d’un simple clone de ChatGPT.
