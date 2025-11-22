# Schéma d’architecture Hackit MVP

```
+-------------------+         +-------------------+         +-------------------+
|   Frontend Web    |         |  Frontend Flutter |         |  Frontend Mobile  |
|  (React/Flutter)  |         |   (Flutter)       |         |  (React Native)   |
+-------------------+         +-------------------+         +-------------------+
          |                            |                            |
          +------------+---------------+----------------------------+
                       |        HTTP / REST API (JSON)              |
                       v                                            |
                +------------------------------------------+        |
                |               Backend API                |        |
                |         (Node.js / Express)              |        |
                +------------------------------------------+        |
                       |        |         |                        |
         +-------------+        |         +------------------------+
         |                      |                                  |
         v                      v                                  v
+----------------+   +---------------------+         +----------------------+
|  OpenAI API    |   |  Gemini API         |         |  YouTube Data API    |
| (AI Provider)  |   | (AI Provider)       |         | (Video Provider)     |
+----------------+   +---------------------+         +----------------------+

                +------------------------------------------+
                |           Shared Types / Configs         |
                |         (shared/types, shared/config)    |
                +------------------------------------------+

                +------------------------------------------+
                |           Database / Storage             |
                |   (MongoDB, SharedPreferences, Local)    |
                +------------------------------------------+
```

- Les frontends (web, mobile, Flutter) communiquent avec le backend via une API REST.
- Le backend orchestre les appels aux providers IA (OpenAI, Gemini) et vidéo (YouTube).
- Les types et configs partagés assurent la cohérence des données.
- La persistance se fait côté backend (MongoDB) et côté frontend (SharedPreferences pour favoris/historique).

Pour une version graphique, utilisez un outil comme Excalidraw, draw.io ou Mermaid.
