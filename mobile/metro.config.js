const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');
const config = getDefaultConfig(__dirname);
// Bound native CI/Gradle bundling as well as CLI export; Expo otherwise uses half
// the host CPU count and can exhaust memory alongside the Kotlin/C++ workers.
config.maxWorkers = 2;
config.watchFolders = [path.resolve(__dirname, '..', 'rm-mobile-supabase')];
module.exports = config;
