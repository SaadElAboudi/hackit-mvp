# Hackit MVP — Liste des fonctionnalités

Ce document regroupe les fonctionnalités pertinentes et intéressantes pour Hackit (présentes, MVP à finir, et idées d'évolution).

Légende statut: `[x]` implémenté · `[~]` partiel/en cours · `[ ]` à faire. Les tags [MVP] / [Plus] / [Premium] indiquent la phase stratégique.

## 1) Coeur du produit
- [x] [MVP] Recherche question → résultats vidéo: Backend `/api/search` + écrans de base (React Native Home/Result, Flutter partiel).
- [~] [MVP] Résumé IA par vidéo: Génération de résumé via OpenAI (Gemini optionnelle) mais format 5 points non encore standardisé côté affichage.
- [ ] [MVP] Chat et suivi de contexte: Pas de gestion multi-tour ou contexte persistant actuellement.
- [ ] [Plus] Comparaison de vidéos.
- [ ] [Plus] Mode "pas-à-pas".
- [ ] [Premium] Mode "quiz-moi".

## 2) Recherche & Découverte
- [~] [MVP] Provider YouTube: Recherche + fallback `yt-search` OK, pas de tri avancé ni pagination (maxResults fixe=5).
- [ ] [Plus] Multi-sources (TikTok/Vimeo).
- [ ] [Plus] Filtres avancés.
- [ ] [Plus] Tendances / sujets populaires.
- [ ] [Plus] Recherche sémantique (expansion intelligente au-delà de simple reformulation).

## 3) Traitement du contenu (IA)
- [x] [MVP] Reformulation de requêtes: Implémentée (OpenAI `reformulateQuestion`, Gemini optionnelle via USE_GEMINI).
- [ ] [MVP] Récupération & résumé de transcript: Pas de transcript fetch dans le code actuel.
- [ ] [Plus] Temps forts horodatés.
- [ ] [Plus] Extraction de procédures / checklists.
- [ ] [Plus] Extraction de code/commandes.
- [ ] [Premium] Synthèse multi-vidéos.

## 4) Expérience utilisateur (UX)
- [~] [MVP] État de chargement & erreurs: Hooks `useSearch` gère loading/error mais pas encore UI complète (skeletons, retry distinct).
- [ ] [MVP] Mini-lecteur intégré: Pas de lecteur embarqué (utilisation liens externes probable).
- [x] [MVP] Mode sombre: Présent côté Flutter (`AppTheme.darkTheme` / `lightTheme`), persistance à ajouter.
- [~] [Plus] Accessibilité AA: Présence de tests accessibilité (fichiers test) mais audit complet non confirmé.
- [ ] [Plus] PiP.
- [ ] [Plus] Voice input/output.
- [ ] [Premium] Mode mains libres.

## 5) Personnalisation
- [ ] [Plus] Historique & favoris.
- [ ] [Plus] Collections/Playlists d’apprentissage.
- [ ] [Plus] Profil d’apprentissage.
- [ ] [Premium] Recommandations personnalisées.

## 6) Collaboration & Partage
- [ ] [MVP] Partage de liens (simples liens possibles mais pas enrichis timecode/résumé packagé).
- [ ] [Plus] Export PDF/Markdown.
- [ ] [Plus] Commentaires/notes.
- [ ] [Premium] Espaces d’équipe.

## 7) Croissance & Rétention
- [ ] [MVP] Feedback simple.
- [ ] [Plus] Relances et suggestions.
- [ ] [Plus] Onboarding guidé.
- [ ] [Premium] Rappels intelligents.

## 8) Monétisation
- [ ] [MVP] Free tier avec limites.
- [ ] [Plus] Pro individuel.
- [ ] [Premium] Équipes/Enterprise.

## 9) Qualité & Fiabilité
- [~] [MVP] Bascule provider IA: Deux services séparés (OpenAI/Gemini) mais pas de failover automatique ni timeout orchestration.
- [ ] [MVP] Cache des requêtes.
- [ ] [MVP] Rate limiting & protection API.
- [ ] [Plus] Circuit breaker provider.
- [ ] [Plus] Tests de fumée réels (workflow réel partiel YouTube API – besoin vérification profondeur).

## 10) Sécurité & Confidentialité
- [ ] [MVP] Politique de confidentialité (document à créer).
- [ ] [MVP] Masquage/retention minimales (logs actuels simples, besoin de règles explicites).
- [ ] [Plus] Conformité RGPD.
- [ ] [Premium] Chiffrement au repos + BYO Keys.

## 11) Observabilité & Analytics
- [ ] [MVP] Logs structurés + corrélation (actuels: console.log / console.error).
- [ ] [MVP] Métriques clés.
- [ ] [Plus] Tableaux de bord.
- [ ] [Plus] Événements produit.

## 12) Plateformes & Intégrations
- [~] [MVP] Flutter Mobile/Web: Thème et base présents, parcours search pas totalement finalisé (tests bloc présents mais feature incomplète).
- [~] [Plus] React Native: Écrans basiques (Home/Result) sans navigation avancée ni deep linking.
- [ ] [Plus] Extension navigateur.
- [ ] [Plus] API publique + OpenAPI.
- [ ] [Premium] Intégrations Slack/Teams.

---

## Recommandations d’exécution (priorités pratiques)
1. Standardiser affichage résumé (format 5 points) + ajouter gestion erreurs/retry UI.
2. Implémenter pagination & rate limiting + couche validation (zod/joi).
3. Unifier providers IA avec failover + ajouter cache & métriques.
4. Introduire transcript fetch + feedback utilisateur.
5. Étendre Flutter & RN pour parcours complet puis multi-sources TikTok.

