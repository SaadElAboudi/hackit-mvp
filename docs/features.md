# Hackit MVP — Fonctionnalités

Ce document liste les fonctionnalités du produit dans son cadrage actuel : workspace collaboratif basé sur des canaux (`Salons`) et une IA partagée.

Légende : `[x]` implémenté, `[~]` partiel, `[ ]` à planifier.

## 1) Collaboration en canaux

- [x] Salons temps réel avec historique de messages.
- [x] Présence et diffusion d'événements via WebSocket.
- [x] IA partagée dans le canal via `@ia`.
- [~] Gestion avancée des rôles (owner/member/guest en progression selon routes).

## 2) Commandes IA du canal

- [x] `/doc` pour générer un artefact partagé.
- [x] `/search` pour attacher une recherche au canal.
- [x] `/decide` pour extraire décisions, risques et actions.
- [x] `/brief` pour produire un brief de réunion.
- [x] `/mission` pour lancer une mission IA avec profil spécialisé.
- [x] `/share slack` et `/share notion` pour exporter un résumé.

## 3) Artefacts, missions et mémoire

- [x] Artefacts versionnés et affichage dans le flux.
- [x] Missions avec suivi de statut.
- [x] Mémoire room-scoped exploitable par l'orchestrateur.
- [~] Workflow de revue d'artefact (commentaires, compare diff) à enrichir.

## 4) Proactivité contrôlée

- [x] Suggestions automatiques de synthèse (seuil + cooldown).
- [x] Suggestions automatiques de brief avant réunion.
- [x] Intervention IA explicable via événements système.

## 5) Intégrations externes

- [x] Slack: connect/disconnect/status/share.
- [x] Notion: connect/disconnect/status/export.
- [ ] Connecteurs additionnels (Drive/Jira/Asana) via couche d'abstraction.

## 6) Frontend Flutter

- [x] Écran principal de chat collaboratif (`salon_chat_screen.dart`).
- [x] Cartes de synthèse/brief/recherche/artefact dans le timeline.
- [x] Sélection de profil agent lors du lancement de mission.
- [~] Centre d'état intégrations et historique de partages.

## 7) Qualité et robustesse

- [x] Tests backend orientées orchestrateur, WS et intégrations.
- [~] Uniformisation enveloppe d'erreur + `requestId` sur tous les flux.
- [~] Validation stricte des payloads écriture sur toutes les routes room.
- [ ] Métriques opérationnelles (latence commande, fallback IA, erreurs WS).

## 8) Priorités recommandées (prochaines itérations)

1. Gouvernance API : validation schema, enveloppe erreur standard, requestId.
2. Maturité artefacts : commentaires, diff de versions, transitions de statut.
3. Intégrations : idempotence/retry des exports + historique de partage.
4. Observabilité : métriques backend et alerting de dégradation.

## Référence

- `codex.md`
- `docs/architecture.md`
- `docs/implementation_roadmap.md`

