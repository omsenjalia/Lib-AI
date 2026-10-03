import { readFileSync } from 'fs';
import { join } from 'path';
import { catalogue, installedRequirementGb, orphanedInstallations, ramRequirementGbFor, recommendedQuantOf } from '../src/core/catalogue';
import type { ModelInstallation } from '../src/core/db/types';
import { loadFit, memoryHeadroom } from '../src/core/utils/memoryBudget';

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

describe('installedRequirementGb', () => {
  it('follows the installed quant and falls back to the recommended one', () => {
    const m = catalogue.models.find((x) => x.id === 'qwen3.5-4b')!;
    const q3 = m.quants.find((q) => q.quant === 'Q3_K_M')!;
    expect(installedRequirementGb(m, { quant: 'Q3_K_M' })).toBeCloseTo(ramRequirementGbFor(m, q3), 9);
    expect(installedRequirementGb(m, undefined)).toBeCloseTo(m.ramRequirementGb, 9);
    expect(installedRequirementGb(m, { quant: 'not-a-quant' })).toBeCloseTo(m.ramRequirementGb, 9);
  });
});

describe('orphanedInstallations', () => {
  const install = (modelId: string): ModelInstallation => ({
    modelId,
    quant: 'Q4_K_M',
    fileName: 'm.gguf',
    localPath: '/x',
    mmprojPath: null,
    sizeBytes: 1,
    sha256: 'a',
    repoSha: null,
    totalBytes: 5e9,
    downloadedAt: 0,
  });

  it('lists installs the catalogue dropped, and only those', () => {
    const installs = { 'qwen3.8-27b': install('qwen3.8-27b'), 'qwen3.5-4b': install('qwen3.5-4b'), 'mimo-v2.6-9b': install('mimo-v2.6-9b') };
    const ids = catalogue.models.map((m) => m.id);
    expect(orphanedInstallations(installs, ids).map((i) => i.modelId)).toEqual(['mimo-v2.6-9b', 'qwen3.8-27b']);
    expect(orphanedInstallations({}, ids)).toEqual([]);
  });
});

describe('loadFit', () => {
  it('says the resident model is loaded whatever the numbers', () => {
    expect(loadFit({ required: 9e9, available: 1e9, resident: true })).toEqual({ kind: 'resident' });
  });

  it('applies the same headroom as the load preflight', () => {
    expect(loadFit({ required: 4e9, available: 4e9 * memoryHeadroom, resident: false })).toEqual({ kind: 'fits' });
    const short = loadFit({ required: 4e9, available: 4e9, resident: false });
    expect(short).toEqual({ kind: 'short', required: Math.ceil(4e9 * memoryHeadroom), available: 4e9 });
  });
});
