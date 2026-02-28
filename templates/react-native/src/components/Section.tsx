import React from 'react';
import { View, Text, StyleSheet, type ViewProps } from 'react-native';

type SectionProps = ViewProps & {
  title: string;
  children: React.ReactNode;
};

export function Section({ title, children, style, ...rest }: SectionProps): React.JSX.Element {
  return (
    <View style={[styles.section, style]} {...rest}>
      <Text style={styles.title}>{title}</Text>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  section: {
    marginBottom: 24,
  },
  title: {
    fontSize: 20,
    fontWeight: '700',
    marginBottom: 8,
    color: '#111',
  },
});
