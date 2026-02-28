import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Section } from '@/src/components/Section';

export function SettingsScreen(): React.JSX.Element {
  return (
    <View style={styles.container}>
      <Section title="Settings">
        <Text style={styles.paragraph}>
          Edit this screen to add your app settings.
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
    color: '#333',
  },
});
