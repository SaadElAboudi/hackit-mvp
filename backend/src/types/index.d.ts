interface SearchQuery {
  query: string;
}

interface Video {
  title: string;
  videoUrl: string;
  source: string;
}

interface Summary {
  title: string;
  steps: string[];
  videoUrl: string;
  source: string;
}