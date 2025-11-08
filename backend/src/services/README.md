# Backend HackIt

## Configuration

### Variables d'environnement requises

```env
# API Gemini
GEMINI_API_KEY=votre_clé_api_gemini
GEMINI_MODEL=models/text-bison-001  # ou autre modèle Gemini
USE_GEMINI=true                     # active les fonctionnalités Gemini

# API YouTube
YOUTUBE_API_KEY=votre_clé_api_youtube
```

## Services

### Service Gemini (`services/gemini.js`)

Gère toutes les interactions avec l'API Gemini de Google pour :
- Reformulation intelligente des requêtes
- Génération de résumés de vidéos
- Analyse contextuelle

#### Fonctionnalités

1. **Reformulation de questions**
   - Traduit et optimise les requêtes pour YouTube
   - Améliore la pertinence des résultats

2. **Génération de résumés**
   - Crée des résumés structurés en 5 points
   - Extrait les informations clés des titres

3. **Configuration**
   - Température : 0.2 (réponses cohérentes)
   - Tokens limités selon la fonction
   - Mode sans-Gemini disponible