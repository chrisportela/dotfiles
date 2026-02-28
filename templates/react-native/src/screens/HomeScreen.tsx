import React from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { Section } from '@/src/components/Section';

export type HomeStackParamList = {
  Home: undefined;
  Details: { itemId: string };
};

type Props = NativeStackScreenProps<HomeStackParamList, 'Home'>;

export function HomeScreen({ navigation }: Props): React.JSX.Element {
  return (
    <View style={styles.container}>
      <Section title="Welcome">
        <Text style={styles.paragraph}>
          This is the Home screen. Tap the button below to open Details.
        </Text>
        <Pressable
          style={styles.button}
          onPress={() => navigation.navigate('Details', { itemId: '42' })}
        >
          <Text style={styles.buttonText}>Open Details</Text>
        </Pressable>
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
    marginBottom: 12,
    color: '#333',
  },
  button: {
    backgroundColor: '#007AFF',
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
    alignSelf: 'flex-start',
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
