import React from 'react';
import { View, Text, Image, TouchableOpacity } from 'react-native';

interface VideoCardProps {
  title: string;
  videoUrl: string;
  thumbnailUrl: string;
}

const VideoCard: React.FC<VideoCardProps> = ({ title, videoUrl, thumbnailUrl }) => {
  return (
    <TouchableOpacity onPress={() => Linking.openURL(videoUrl)} style={{ margin: 10, borderRadius: 8, overflow: 'hidden', backgroundColor: '#fff', shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.2, shadowRadius: 4 }}>
      <Image source={{ uri: thumbnailUrl }} style={{ width: '100%', height: 200 }} />
      <View style={{ padding: 10 }}>
        <Text style={{ fontSize: 16, fontWeight: 'bold' }}>{title}</Text>
      </View>
    </TouchableOpacity>
  );
};

export default VideoCard;