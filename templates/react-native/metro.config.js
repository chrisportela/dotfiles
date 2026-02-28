const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

const defaultConfig = getDefaultConfig(__dirname);

const config = {
  watchFolders: [__dirname],
};

module.exports = mergeConfig(defaultConfig, config);
