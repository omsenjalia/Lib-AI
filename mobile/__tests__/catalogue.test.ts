import { readFileSync } from 'fs';
import { join } from 'path';
import { catalogue, recommendedQuantOf } from '../src/core/catalogue';

// The generator (tool/generate_models_catalogue.py) writes the root copy. The
// app bundles its own copy; this test is what stops the two drifting apart.
describe('bundled catalogue', () => {
  it('is byte-identical to the generated root catalogue', () => {
    const root = readFileSync(join(__dirname, '..', '..', 'assets', 'models_catalogue.json'), 'utf8');
    const app = readFileSync(join(__dirname, '..', 'assets', 'models_catalogue.json'), 'utf8');
    expect(app).toBe(root);
  });

  it('parses every model with a recommended quant that exists', () => {
    expect(catalogue.models.length).toBeGreaterThan(0);
    for (const m of catalogue.models) {
      expect(m.quants.some((q) => q.quant === m.recommendedQuant)).toBe(true);
      expect(recommendedQuantOf(m).quant).toBe(m.recommendedQuant);
    }
  });

  it('has real sizes, SHA-256 checksums, and URLs inside the model repo', () => {
    for (const m of catalogue.models) {
      for (const q of m.quants) {
        expect(q.sizeBytes).toBeGreaterThan(100_000_000);
        expect(q.sha256).toMatch(/^[0-9a-f]{64}$/);
        expect(q.downloadUrl.startsWith(`https://huggingface.co/${m.ggufRepoId}/resolve/`)).toBe(true);
      }
      if (m.mmproj) expect(m.mmproj.sha256).toMatch(/^[0-9a-f]{64}$/);
    }
  });

  it('keeps the 27B behind the Wi-Fi gate and flagged as not fitting', () => {
    const big = catalogue.models.find((m) => m.id === 'qwen3.8-27b')!;
    expect(big.wifiOnly).toBe(true);
    expect(big.highRam).toBe(true);
    expect(big.fitsTargetDevice).toBe(false);
  });

  it('claims vision only with evidence', () => {
    for (const m of catalogue.models) if (m.visionSupported) expect(m.visionEvidence).toBeTruthy();
  });
});
