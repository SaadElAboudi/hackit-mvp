#!/bin/bash

# Script de démarrage propre pour le backend
# Gère automatiquement les conflits de port

PORT=${PORT:-3000}

echo "🔍 Vérification du port $PORT..."

# Tuer tout processus utilisant le port
if lsof -ti:$PORT > /dev/null 2>&1; then
  echo "⚠️  Port $PORT occupé. Nettoyage en cours..."
  lsof -ti:$PORT | xargs kill -9 2>/dev/null
  sleep 1
fi

echo "✅ Port $PORT disponible"
echo "🚀 Démarrage du serveur..."

# Démarrer le serveur
npm run dev

