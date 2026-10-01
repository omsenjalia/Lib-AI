import { readFileSync } from 'fs';
import { join } from 'path';

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { configureRelease } = require('../scripts/configure-android-release.cjs') as {
  configureRelease(source: string): string;
};

/**
 * The fixture is the signing and build-type block from a real
 * `expo prebuild` on SDK 57. If Expo changes its template, the nightly must
 * fail rather than publish a debug-signed release, and this test says so first.
 */
const template = readFileSync(join(__dirname, 'fixtures', 'expo57-build.gradle.txt'), 'utf8');

describe('release signing rewrite', () => {
  const out = configureRelease(template);

  it('adds a release signing config read from the environment', () => {
    expect(out).toContain('storeFile file(System.getenv("KEYSTORE_PATH"))');
    expect(out).toContain('storePassword System.getenv("KEYSTORE_PASSWORD")');
  });

  it('moves only the release build type onto the release key', () => {
    expect(out.match(/signingConfig signingConfigs\.debug/g)).toHaveLength(1);
    expect(out.match(/signingConfig signingConfigs\.release/g)).toHaveLength(1);
    expect(out.indexOf('signingConfigs.debug')).toBeLessThan(out.indexOf('signingConfig signingConfigs.release'));
  });

  it('never writes a release password into the file', () => {
    // Expo's debug block legitimately holds the public debug keystore's password.
    const release = out.slice(out.indexOf('release {'), out.indexOf('}', out.indexOf('release {')));
    expect(release).not.toMatch(/Password ['"]/);
    expect(release).toMatch(/Password System\.getenv/);
  });

  it('refuses a template it does not recognise', () => {
    expect(() => configureRelease(out)).toThrow(/refusing to publish a debug-signed release/);
    expect(() => configureRelease('android {}')).toThrow();
  });
});
