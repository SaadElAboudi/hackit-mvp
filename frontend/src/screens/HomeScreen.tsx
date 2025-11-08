import React, { useState } from 'react';
import { View, Text, Button } from 'react-native';
import ChatInput from '../components/ChatInput';
import { useSearch } from '../hooks/useSearch';

const HomeScreen = () => {
  const [query, setQuery] = useState('');
  const { search, results } = useSearch();

  const handleSearch = () => {
    search(query);
  };

  return (
    <View className="flex-1 justify-center items-center p-4">
      <Text className="text-xl font-bold mb-4">Posez votre question</Text>
      <ChatInput query={query} setQuery={setQuery} />
      <Button title="Rechercher" onPress={handleSearch} />
      {results && (
        <View className="mt-4">
          <Text className="text-lg">Résultats:</Text>
          {/* Affichage des résultats ici */}
        </View>
      )}
    </View>
  );
};

export default HomeScreen;