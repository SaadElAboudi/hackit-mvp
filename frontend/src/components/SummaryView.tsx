import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

interface SummaryViewProps {
  title: string;
  summary: string;
  steps: string[];
}

const SummaryView: React.FC<SummaryViewProps> = ({ title, summary, steps }) => {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>{title}</Text>
      <Text style={styles.summary}>{summary}</Text>
      <Text style={styles.stepsTitle}>Étapes :</Text>
      {steps.map((step, index) => (
        <Text key={index} style={styles.step}>
          {index + 1}. {step}
        </Text>
      ))}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    padding: 16,
    backgroundColor: '#fff',
    borderRadius: 8,
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  title: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  summary: {
    fontSize: 16,
    marginBottom: 12,
  },
  stepsTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 4,
  },
  step: {
    fontSize: 16,
    marginLeft: 8,
  },
});

export default SummaryView;