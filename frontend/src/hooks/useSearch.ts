import { useState } from 'react';
import axios from 'axios';

const useSearch = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [result, setResult] = useState(null);

  const search = async (query) => {
    setLoading(true);
    setError(null);
    try {
      const response = await axios.post('/api/search', { query });
      setResult(response.data);
    } catch (err) {
      setError(err.response ? err.response.data : 'An error occurred');
    } finally {
      setLoading(false);
    }
  };

  return { loading, error, result, search };
};

export default useSearch;