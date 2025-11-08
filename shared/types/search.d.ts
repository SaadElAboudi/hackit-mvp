export interface SearchResult {
  title: string;
  steps: string[];
  videoUrl: string;
  source: 'youtube-api' | 'yt-search-fallback' | 'mock';
  reformulated?: boolean;
}

export interface SearchRequest {
  query: string;
}

export interface SearchError {
  error: string;
  detail?: string;
  query?: string;
}