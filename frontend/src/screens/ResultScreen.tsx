import React from 'react';
import { View, Text, Button, ScrollView } from 'react-native';
import VideoCard from '../components/VideoCard';
import SummaryView from '../components/SummaryView';

const ResultScreen = ({ route, navigation }) => {
  const { title, summary, steps, videoUrl } = route.params;

  return (
    <ScrollView className="p-4">
      <Text className="text-xl font-bold mb-4">{title}</Text>
      <SummaryView summary={summary} steps={steps} />
      <VideoCard videoUrl={videoUrl} />
      <Button title="Retour" onPress={() => navigation.goBack()} />
    </ScrollView>
  );
};

export default ResultScreen;