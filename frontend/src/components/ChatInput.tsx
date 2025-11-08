import React, { useState } from 'react';
import { View, TextInput, Button } from 'react-native';

const ChatInput = ({ onSearch }) => {
  const [query, setQuery] = useState('');

  const handleSearch = () => {
    if (query.trim()) {
      onSearch(query);
      setQuery('');
    }
  };

  return (
    <View className="flex-row items-center p-4">
      <TextInput
        className="flex-1 border border-gray-300 rounded p-2"
        placeholder="Posez votre question..."
        value={query}
        onChangeText={setQuery}
      />
      <Button title="Rechercher" onPress={handleSearch} />
    </View>
  );
};

export default ChatInput;