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
- [~] Workflow de revue d'artefact présent (commentaires, statuts, compare), encore à polir côté UX/tests.

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
- [x] Centre d'état intégrations et historique de partages.

## 7) Qualité et robustesse

- [x] Tests backend orientées orchestrateur, WS et intégrations.
- [~] Enveloppe d'erreur + `requestId` largement uniformisés sur les flux room, avec quelques flux legacy hors room encore hétérogènes.
- [x] Validation stricte des payloads écriture sur les routes room.
- [x] Métriques opérationnelles backend, endpoints santé, SLOs et alertes de base.

## 8) Priorités recommandées (prochaines itérations)

1. Finaliser la maturité artefacts côté Flutter : review UX, compare, widget tests.
2. Valider l'observabilité en staging : dashboards, alert routing, playbook opérateur.
3. Étendre les connecteurs d'export via l'abstraction existante (Drive/Jira/Asana si prioritaire).
4. Continuer l'uniformisation des flux legacy hors rooms sur le même contrat d'erreur.

## Référence

- `codex.md`
- `docs/architecture.md`
- `docs/implementation_roadmap.md`

