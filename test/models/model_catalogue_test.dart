import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/models/model_catalogue.dart';

/// Validates the shipped catalogue against the rules the brief sets out.
///
/// This is the machine-checkable half of the delivery gate: no hallucinated
/// sizes or quants, correct download URLs, and no model claiming vision support
/// without recorded evidence. Anything asserted here is a claim the app makes to
/// the user, so it is asserted against the real asset rather than a fixture.
void main() {
  late ModelCatalogue catalogue;

  setUpAll(() {
    final file = File('assets/models_catalogue.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'assets/models_catalogue.json must exist and be committed',
    );
    catalogue = ModelCatalogue.fromJsonString(file.readAsStringSync());
  });

  test('the catalogue carries a schema version and a target device', () {
    expect(catalogue.schemaVersion, 1);
    expect(catalogue.targetDevice.name, contains('Galaxy S25'));
    expect(catalogue.targetDevice.usableRamGb, greaterThan(0));
  });

  test('all six approved models are present, with their approved repos', () {
    expect(catalogue.models, hasLength(6));

    final byId = {for (final model in catalogue.models) model.id: model};

    expect(byId.keys, containsAll([
      'qwen3.8-27b',
      'mimo-v2.6-9b',
      'qwythos-9b-v2',
      'qwythos-9b-mythos-5-1m',
      'qwen3.5-9b-opus-4.6-distill',
      'phi-4-mini-3.8b',
    ]));

    // D3: third-party GGUFs where no official GGUF exists.
    expect(byId['qwen3.8-27b']!.ggufRepoId, 'unsloth/Qwen3.8-27B-GGUF');
    expect(
      byId['mimo-v2.6-9b']!.ggufRepoId,
      'bartowski/MiMo-V2.6-Distill-Qwen-9B-GGUF',
      reason: 'MiMo must not come from ggml-org: its only quant there is Q8_0, '
          'which is too large for this device',
    );
    expect(
      byId['phi-4-mini-3.8b']!.ggufRepoId,
      'bartowski/microsoft_Phi-4-mini-instruct-GGUF',
      reason: 'bartowski prefixes the upstream org with an underscore. '
          '`bartowski/Phi-4-mini-instruct-GGUF` returns 404, so a typo here '
          'would make every download fail at the first request.',
    );
  });

  test('every model has at least one quantisation with a real checksum', () {
    final sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

    for (final model in catalogue.models) {
      expect(model.quants, isNotEmpty, reason: '${model.id} has no quants');

      for (final quant in model.quants) {
        expect(
          quant.fileName.endsWith('.gguf'),
          isTrue,
          reason: '${model.id} ${quant.quant} is not a .gguf',
        );
        expect(quant.sizeBytes, greaterThan(0));
        expect(
          quant.sha256,
          isNotNull,
          reason: '${model.id} ${quant.quant} has no checksum',
        );
        expect(
          sha256Pattern.hasMatch(quant.sha256!),
          isTrue,
          reason: '${model.id} ${quant.quant} checksum is not a SHA-256',
        );
      }
    }
  });

  test('the published sizeGb agrees with the byte count', () {
    for (final model in catalogue.models) {
      for (final quant in model.quants) {
        final derivedGb = quant.sizeBytes / 1e9;
        expect(
          quant.sizeGb,
          isNotNull,
          reason: '${model.id} ${quant.quant} has no published sizeGb',
        );
        expect(
          (quant.sizeGb! - derivedGb).abs(),
          lessThan(0.01),
          reason: '${model.id} ${quant.quant} sizeGb disagrees with sizeBytes',
        );
      }
    }
  });

  test('every download URL points at the model\'s own repository', () {
    for (final model in catalogue.models) {
      for (final quant in model.quants) {
        final expectedPrefix =
            'https://huggingface.co/${model.ggufRepoId}/resolve/main/';
        expect(
          quant.downloadUrl,
          startsWith(expectedPrefix),
          reason: '${model.id} ${quant.quant} URL is wrong',
        );
        expect(
          quant.downloadUrl,
          endsWith(quant.fileName),
          reason: '${model.id} ${quant.quant} URL does not name its file',
        );
      }

      final mmproj = model.mmproj;
      if (mmproj != null) {
        expect(
          mmproj.downloadUrl,
          startsWith(
            'https://huggingface.co/${model.ggufRepoId}/resolve/main/',
          ),
        );
        expect(mmproj.downloadUrl, endsWith(mmproj.fileName));
        expect(mmproj.sha256, isNotNull);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(mmproj.sha256!), isTrue);
      }
    }
  });

  test('the recommended quant always exists in the quant list', () {
    for (final model in catalogue.models) {
      expect(
        model.recommendedQuantInfo,
        isNotNull,
        reason: '${model.id} has no usable recommended quant',
      );
      expect(
        model.quants.any((q) => q.quant == model.recommendedQuant),
        isTrue,
        reason: '${model.id} recommends ${model.recommendedQuant}, which is '
            'not in its quant list',
      );
    }
  });

  group('the 27B is handled exactly as decided in D1', () {
    late CatalogueModel target;

    setUp(() {
      target = catalogue.byId('qwen3.8-27b')!;
    });

    test('it is flagged Wi-Fi only and High RAM', () {
      expect(target.wifiOnly, isTrue);
      expect(target.highRam, isTrue);
    });

    test('it does not claim to fit this device', () {
      expect(target.fitsTargetDevice, isFalse);
      expect(target.ramRequirementGb, greaterThan(catalogue.targetDevice.usableRamGb));
    });

    test('it carries an explicit will-not-load warning', () {
      expect(target.hasWarning, isTrue);
      expect(target.warning!.toUpperCase(), contains('WILL NOT LOAD'));
    });

    test('its recommended quant is the smallest published one, UD-IQ2_XXS', () {
      expect(target.recommendedQuant, 'UD-IQ2_XXS');

      final recommended = target.recommendedQuantInfo!;
      final smallest = target.quants
          .map((q) => q.sizeBytes)
          .reduce((a, b) => a < b ? a : b);
      expect(
        recommended.sizeBytes,
        smallest,
        reason: 'the recommended quant must be the smallest available, since '
            'this model will not fit regardless',
      );
    });

    test('no quant of it is marked as fitting this device', () {
      expect(target.quants.every((q) => !q.fitsTargetDevice), isTrue);
    });

    test('the 27B is the only Wi-Fi-only model in the catalogue', () {
      final wifiOnly = catalogue.models.where((m) => m.wifiOnly).toList();
      expect(wifiOnly, hasLength(1));
      expect(wifiOnly.single.id, 'qwen3.8-27b');
    });
  });

  group('vision support is only claimed with evidence', () {
    test('a model marked vision-capable records why', () {
      for (final model in catalogue.models.where((m) => m.visionSupported)) {
        expect(
          model.visionEvidence,
          isNotNull,
          reason: '${model.id} claims vision with no evidence',
        );
        expect(model.visionEvidence, isNotEmpty);
        expect(
          model.mmproj,
          isNotNull,
          reason: '${model.id} claims vision but ships no projector',
        );
      }
    });

    test('a text-only model records that too', () {
      final textOnly = catalogue.models.where((m) => !m.visionSupported);
      expect(textOnly, isNotEmpty);

      for (final model in textOnly) {
        expect(model.mmproj, isNull);
        expect(model.visionAbsenceNote, isNotNull);
        expect(model.visionAbsenceNote, isNotEmpty);
      }
    });

    test('the two text-only models are recorded as such', () {
      final model = catalogue.byId('qwen3.5-9b-opus-4.6-distill')!;
      expect(model.visionSupported, isFalse);
      expect(model.mmproj, isNull);
    });

    test('Phi-4-mini is text-only, and the entry says why', () {
      // The base repo is pipeline_tag=text-generation with no vision tag, no
      // preprocessor_config.json, and no mmproj in the GGUF repo. OCR mode has
      // to refuse this model, so the absence is asserted rather than assumed.
      final model = catalogue.byId('phi-4-mini-3.8b')!;
      expect(model.visionSupported, isFalse);
      expect(model.mmproj, isNull);
      expect(model.visionEvidence, isNull);
      expect(model.visionAbsenceNote, isNotNull);
      expect(model.visionAbsenceNote!.toLowerCase(), contains('text-only'));
    });

    test('exactly two of the six models are text-only', () {
      final textOnly = catalogue.models.where((m) => !m.visionSupported);
      expect(
        textOnly.map((m) => m.id).toList(),
        ['qwen3.5-9b-opus-4.6-distill', 'phi-4-mini-3.8b'],
      );
    });
  });

  group('the Phi-4-mini entry is the small, unconstrained one', () {
    late CatalogueModel target;

    setUp(() {
      target = catalogue.byId('phi-4-mini-3.8b')!;
    });

    test('it is not Wi-Fi only and not High RAM', () {
      expect(target.wifiOnly, isFalse);
      expect(target.highRam, isFalse);
      expect(target.hasWarning, isFalse);
    });

    test('every quant of it fits this device', () {
      // The only model in the catalogue for which that is true, which is the
      // whole reason it is here: an 8 GB phone can run it at any quant.
      expect(target.quants, hasLength(23));
      expect(target.quants.every((q) => q.fitsTargetDevice), isTrue);
      expect(
        target.quants.map((q) => q.sizeBytes).reduce((a, b) => a > b ? a : b),
        lessThan(5 * 1000 * 1000 * 1000),
      );
    });

    test('it is a quarter of the RAM of the next smallest model', () {
      final others = catalogue.models
          .where((m) => m.id != 'phi-4-mini-3.8b')
          .map((m) => m.ramRequirementGb);
      expect(target.ramRequirementGb, lessThan(others.reduce((a, b) => a < b ? a : b)));
    });

    test('its 128K window comes from the GGUF itself', () {
      expect(target.maxContextLength, 131072);
      expect(target.recommendedContextLength, 8192);
      expect(target.maxContextLength, greaterThan(target.recommendedContextLength));
    });

    test('the base repo is recorded, with its own revision', () {
      expect(target.hfModelId, 'microsoft/Phi-4-mini-instruct');
      expect(target.hfModelHasGguf, isFalse);
      expect(target.hfModelFileNote, contains('microsoft_Phi-4-mini-instruct'));
    });
  });

  group('context windows', () {
    test('the recommended context never exceeds the model maximum', () {
      for (final model in catalogue.models) {
        expect(
          model.recommendedContextLength,
          lessThanOrEqualTo(model.maxContextLength),
          reason: '${model.id} recommends more context than it supports',
        );
      }
    });

    test('the 4k Opus-4.6 distill is capped at 4096', () {
      final model = catalogue.byId('qwen3.5-9b-opus-4.6-distill')!;
      expect(model.maxContextLength, 4096);
      expect(model.recommendedContextLength, 4096);
    });
  });

  group('sampling defaults come from the model cards', () {
    test('Qwythos records its documented repeat penalty of 1.05', () {
      final model = catalogue.byId('qwythos-9b-v2')!;
      expect(model.samplingDefaults.repeatPenalty, 1.05);
    });

    test('the Mythos variant warns about low temperatures', () {
      // Its card documents repetition loops at or below 0.3.
      final model = catalogue.byId('qwythos-9b-mythos-5-1m')!;
      expect(model.samplingDefaults.temperature, greaterThan(0.3));
    });

    test('every model has a usable temperature and top-p', () {
      for (final model in catalogue.models) {
        expect(model.samplingDefaults.temperature, greaterThan(0));
        expect(model.samplingDefaults.topP, inInclusiveRange(0.1, 1.0));
      }
    });
  });

  test('storage accounting includes the projector', () {
    // Understating the transfer would make the storage warning wrong.
    for (final model in catalogue.models) {
      final quant = model.recommendedQuantInfo!;
      final withProjector =
          model.totalDownloadBytes(quant, includeMmproj: true);
      final withoutProjector =
          model.totalDownloadBytes(quant, includeMmproj: false);

      expect(withoutProjector, quant.sizeBytes);
      if (model.mmproj != null) {
        expect(withProjector, greaterThan(withoutProjector));
        expect(
          withProjector,
          quant.sizeBytes + model.mmproj!.sizeBytes,
        );
      } else {
        expect(withProjector, withoutProjector);
      }
    }
  });

  test('the 71 published quantisations are all accounted for', () {
    final total = catalogue.models.fold<int>(
      0,
      (sum, model) => sum + model.quants.length,
    );
    expect(total, 71);
  });

  test('a malformed entry fails loudly instead of half-loading', () {
    expect(
      () => ModelCatalogue.fromJson({
        'schemaVersion': 1,
        'targetDevice': {
          'name': 'x',
          'os': 'y',
          'ramOptionsGb': [8],
          'usableRamGb': 9,
        },
        'models': [
          {'id': 'broken'},
        ],
      }),
      throwsFormatException,
    );
  });
}
