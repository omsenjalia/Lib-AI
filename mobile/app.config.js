// app.json holds the configuration; this only lets CI stamp a build.
//
//   APP_VERSION           e.g. 2.0.0-nightly.20261001 (shown in Settings > About)
//   ANDROID_VERSION_CODE  must only ever increase; the nightly uses epoch
//                         minutes, which is far above the Flutter build's codes,
//                         so the React Native app installs over it as an upgrade
module.exports = ({ config }) => ({
  ...config,
  version: process.env.APP_VERSION || config.version,
  android: {
    ...config.android,
    versionCode: Number(process.env.ANDROID_VERSION_CODE) || config.android?.versionCode,
  },
});
