# Hackit MVP Backend

## Description
This backend service is designed to handle user queries, reformulate them for video searches, and return relevant video summaries along with links to the videos. It integrates with the OpenAI API for natural language processing and the YouTube API for video retrieval.

## Technologies Used
- **Node.js**: JavaScript runtime for building the backend server.
- **Express**: Web framework for Node.js to handle routing and middleware.
- **OpenAI API**: For question reformulation and summary generation.
- **YouTube Data API**: For searching and retrieving video information.
- **Axios**: For making HTTP requests to external APIs.

## Setup Instructions

### Prerequisites
- Node.js installed on your machine.
- Access to OpenAI and YouTube API keys.

### Installation
1. Clone the repository:
   ```
   git clone <repository-url>
   cd hackit-mvp/backend
   ```

2. Install dependencies:
   ```
   npm install
   ```

3. Create a `.env` file in the root of the backend directory and add your API keys:
   ```
   OPENAI_API_KEY=your_openai_api_key
   YT_API_KEY=your_youtube_api_key
   ```

### Running the Server
To start the backend server, run:
```
npm start
```
The server will be running on `http://localhost:3000`.

### API Endpoints
- **POST /api/search**: Accepts a user query and returns a video summary and link.
  - Request Body:
    ```json
    {
      "query": "your question here"
    }
    ```
  - Response:
    ```json
    {
      "title": "Video Title",
      "summary": "Video summary in clear steps.",
      "videoUrl": "https://www.youtube.com/watch?v=video_id"
    }
    ```

## Directory Structure
- **src/**: Contains the main application code.
  - **controllers/**: Logic for handling requests.
  - **routes/**: Defines the API routes.
  - **services/**: Functions for interacting with external APIs.
  - **utils/**: Utility functions for various tasks.
  - **types/**: TypeScript type definitions.

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any suggestions or improvements.

## License
This project is licensed under the MIT License.