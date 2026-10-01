// Metro configuration.
//
// `wasm` is registered so expo-sqlite's web build can load its SQLite binary
// for the browser preview. Native builds never touch it.
const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);
config.resolver.assetExts.push('wasm');

module.exports = config;
