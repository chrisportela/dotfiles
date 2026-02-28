import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { Section } from '@/src/components/Section';
import type { HomeStackParamList } from '@/src/screens/HomeScreen';

type Props = NativeStackScreenProps<HomeStackParamList, 'Details'>;

export function DetailsScreen({ route }: Props): React.JSX.Element {
  const { itemId } = route.params;
  return (
    <View style={styles.container}>
      <Section title="Details">
        <Text style={styles.paragraph}>Item ID: {itemId}</Text>
        <Text style={styles.paragraph}>
          You navigated here from the Home screen.
        </Text>
      </Section>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    backgroundColor: '#fff',
  },
  paragraph: {
    fontSize: 16,
    marginBottom: 8,
    color: '#333',
  },
});
