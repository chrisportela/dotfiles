import React from 'react';
import { render, fireEvent } from '@testing-library/react-native';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { HomeScreen } from '../src/screens/HomeScreen';
import { DetailsScreen } from '../src/screens/DetailsScreen';
import type { HomeStackParamList } from '../src/screens/HomeScreen';

const Stack = createNativeStackNavigator<HomeStackParamList>();

function TestNavigator() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen name="Home" component={HomeScreen} />
        <Stack.Screen name="Details" component={DetailsScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}

describe('HomeScreen', () => {
  it('renders welcome text and Open Details button', () => {
    const { getByText } = render(<TestNavigator />);
    expect(getByText('Welcome')).toBeTruthy();
    expect(getByText('Open Details')).toBeTruthy();
  });

  it('navigates to Details when Open Details is pressed', () => {
    const { getByText } = render(<TestNavigator />);
    fireEvent.press(getByText('Open Details'));
    expect(getByText('Item ID: 42')).toBeTruthy();
  });
});
