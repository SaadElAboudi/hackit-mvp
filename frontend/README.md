# Hackit MVP Frontend

## Description
This project is a React Native application that allows users to ask questions and receive clear summaries along with relevant video explanations. The application integrates with OpenAI and YouTube APIs to provide a seamless user experience.

## Getting Started

### Prerequisites
- Node.js (version 14 or higher)
- Expo CLI
- Yarn or npm

### Installation

1. Clone the repository:
   ```
   git clone <repository-url>
   cd hackit-mvp/frontend
   ```

2. Install dependencies:
   ```
   npm install
   ```

3. Start the development server:
   ```
   npm start
   ```

### Running the App
You can run the app on an emulator or a physical device using the Expo Go app. Scan the QR code provided in the terminal after running the start command.

## Project Structure
- `src/`: Contains the main application code.
  - `App.tsx`: Main entry point of the application.
  - `screens/`: Contains screen components.
    - `HomeScreen.tsx`: Screen for user input.
    - `ResultScreen.tsx`: Screen for displaying results.
  - `components/`: Contains reusable components.
    - `ChatInput.tsx`: Component for user input.
    - `VideoCard.tsx`: Displays video information.
    - `SummaryView.tsx`: Displays the video summary.
  - `navigation/`: Contains navigation setup.
    - `index.tsx`: Navigation configuration.
  - `services/`: Contains API service functions.
    - `api.ts`: Functions for making API calls.
  - `hooks/`: Contains custom hooks.
    - `useSearch.ts`: Manages search logic.

## Usage
- Users can enter their questions in the `HomeScreen`.
- The app will process the query and display the results in the `ResultScreen`, including a summary and a relevant video.

## Contributing
Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

## License
This project is licensed under the MIT License.