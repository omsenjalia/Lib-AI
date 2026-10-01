// https://docs.expo.dev/guides/using-eslint/
const { defineConfig } = require('eslint/config');
const expoConfig = require('eslint-config-expo/flat');

module.exports = defineConfig([
  expoConfig,
  {
    ignores: ['dist/*'],
  },
  {
    rules: {
      // Metro resolves `files.native.ts` / `files.web.ts` by platform and there
      // is deliberately no plain `files.ts`. The import resolver cannot see
      // platform suffixes; `tsc` (moduleSuffixes) checks this import instead.
      'import/no-unresolved': ['error', { ignore: ['^@/core/services/files$'] }],
    },
  },
]);
