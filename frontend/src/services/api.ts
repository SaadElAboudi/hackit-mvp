import axios from 'axios';

const API_URL = 'http://localhost:3000/api/search';

export const searchQuery = async (query) => {
  try {
    const response = await axios.post(API_URL, { query });
    return response.data;
  } catch (error) {
    console.error('Error fetching search results:', error);
    throw error;
  }
};