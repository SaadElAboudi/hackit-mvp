# Hackit MVP

![Frontend Flutter CI](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/frontend_flutter-ci.yml/badge.svg)
![Backend CI](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/backend-ci.yml/badge.svg)

## Description
Hackit MVP is a project designed to provide users with quick and clear answers to their questions through a chat interface. The application leverages AI to summarize information and find relevant video content from platforms like YouTube and TikTok.

## Features
- User-friendly chat interface for asking questions.
- AI-powered question reformulation and summarization.
- Integration with YouTube and TikTok APIs to fetch relevant video content.
- Step-by-step guides generated from video content.

## Tech Stack
- **Frontend**: Flutter (Web/Desktop/Mobile) in `frontend_flutter`.
- **Backend**: Node.js (Express) in `backend/`.
- **Database**: Supabase or MongoDB Atlas for storing user queries and feedback.
- **AI Services**: OpenAI API for natural language processing and summarization.
- **Video Services**: YouTube Data API and TikTok API for video retrieval.

## Project Structure
```
hackit-mvp
├── frontend          # Frontend application
├── backend           # Backend API
├── shared            # Shared types and configurations
├── .gitignore        # Files to ignore in version control
├── package.json      # Project metadata and dependencies
└── README.md         # Project documentation
```

## Setup Instructions

### Frontend (Flutter)
1. Navigate to the `frontend_flutter` directory.
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run analyzer and tests (widgets subset):
   ```bash
   flutter analyze
   flutter test -r compact test/widgets
   ```
4. Run on web (dev):
   ```bash
   flutter run -d chrome
   ```

### Backend
1. Navigate to the `backend` directory.
2. Install dependencies:
   ```
   npm install
   ```
3. Create a `.env` file based on `.env.example` and add your API keys.
4. Start the server:
   ```bash
   npm start
   ```
5. Smoke test locally:
   ```bash
   npm run test:smoke
   ```

## Usage
- Open the frontend application and enter your question in the chat interface.
- The application will return a summarized answer along with a relevant video link.

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any enhancements or bug fixes.

## License
This project is licensed under the MIT License.