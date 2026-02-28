import React from 'react';
import { render } from '@testing-library/react-native';
import App from '../App';

describe('App', () => {
  it('renders without crashing', () => {
    const { getByText } = render(<App />);
    // Tab bar shows "Home" and "Settings"
    expect(getByText('Settings')).toBeTruthy();
  });
});
