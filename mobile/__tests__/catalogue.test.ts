import { readFileSync } from 'fs';
import { join } from 'path';
import { catalogue, ramRequirementGbFor, recommendedQuantOf } from '../src/core/catalogue';

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

  it('lists exactly the models chosen for a 4-5 GB free-RAM phone', () => {
    expect(catalogue.models.map((m) => m.id).sort()).toEqual(
      [
        'gemma-4-e2b',
        'gemma-4-e4b',
        'phi-4-mini-3.8b',
        'qwen3.5-2b',
        'qwen3.5-4b',
        'qwen3.5-4b-opus-4.6-distill',
        'qwythos-9b-v2-compact',
      ].sort(),
    );
    expect(catalogue.models.some((m) => m.wifiOnly || m.highRam || !m.fitsTargetDevice)).toBe(false);
  });

  it('serves each projector from the model repo, with one named exception', () => {
    // bartowski's compact Qwythos ships no projector, so it borrows empero's.
    for (const m of catalogue.models) {
      if (!m.mmproj) continue;
      const repo = m.id === 'qwythos-9b-v2-compact' ? 'empero-ai/Qwythos-9B-v2-GGUF' : m.ggufRepoId;
      expect(m.mmproj.downloadUrl.startsWith(`https://huggingface.co/${repo}/resolve/`)).toBe(true);
    }
  });

  it('claims vision only with evidence and a projector', () => {
    for (const m of catalogue.models) {
      if (m.visionSupported) {
        expect(m.visionEvidence).toBeTruthy();
        expect(m.mmproj).toBeDefined();
      } else {
        expect(m.mmproj).toBeUndefined();
        expect(m.visionAbsenceNote).toBeTruthy();
      }
    }
  });

  it('fits every recommended quant in 5 GB for text chat', () => {
    for (const m of catalogue.models) {
      expect(ramRequirementGbFor(m, recommendedQuantOf(m))).toBeLessThanOrEqual(5);
    }
  });

  it('uses the Gemma 4 card sampling', () => {
    for (const id of ['gemma-4-e4b', 'gemma-4-e2b']) {
      const m = catalogue.models.find((x) => x.id === id)!;
      expect(m.samplingDefaults).toMatchObject({ temperature: 1.0, topP: 0.95, topK: 64 });
      expect(m.maxContextLength).toBe(131072);
    }
  });
});

describe('ramRequirementGbFor', () => {
  it('returns the catalogue figure for the recommended quant', () => {
    for (const m of catalogue.models) {
      expect(ramRequirementGbFor(m, recommendedQuantOf(m))).toBeCloseTo(m.ramRequirementGb, 9);
    }
  });

  it('lowers the figure by exactly the weight difference for a smaller quant', () => {
    const m = catalogue.models.find((x) => x.id === 'qwen3.5-4b')!;
    const q4 = recommendedQuantOf(m);
    const q3 = m.quants.find((q) => q.quant === 'Q3_K_M')!;
    expect(ramRequirementGbFor(m, q3)).toBeCloseTo(m.ramRequirementGb - (q4.sizeBytes - q3.sizeBytes) / 1e9, 9);
  });

  it('never claims less than the weights themselves', () => {
    for (const m of catalogue.models) {
      for (const q of m.quants) expect(ramRequirementGbFor(m, q)).toBeGreaterThanOrEqual(q.sizeBytes / 1e9);
    }
  });
});
