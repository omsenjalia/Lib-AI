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

  test('all seven approved models are present, with their approved repos',
      () {
    expect(catalogue.models, hasLength(7));

    final byId = {for (final model in catalogue.models) model.id: model};

    expect(byId.keys, containsAll([
      'phi-4-mini-3.8b',
      'qwythos-9b-v2-compact',
      'qwen3.5-4b',
      'qwen3.5-4b-opus-4.6-distill',
      'qwen3.5-2b',
      'gemma-4-e4b',
      'gemma-4-e2b',
    ]));

    // Third-party GGUFs where the upstream repo ships safetensors only.
    expect(
      byId['phi-4-mini-3.8b']!.ggufRepoId,
      'bartowski/microsoft_Phi-4-mini-instruct-GGUF',
      reason: 'bartowski prefixes the upstream org with an underscore. '
          '`bartowski/Phi-4-mini-instruct-GGUF` returns 404, so a typo here '
          'would make every download fail at the first request.',
    );
    expect(byId['gemma-4-e4b']!.ggufRepoId, 'unsloth/gemma-4-E4B-it-qat-GGUF');
    expect(byId['gemma-4-e2b']!.ggufRepoId, 'unsloth/gemma-4-E2B-it-qat-GGUF');
  });

  test('no shipped model is Wi-Fi only, High RAM, or marked as not fitting',
      () {
    // The 27B that carried these flags was removed on 2026-10-03. The Wi-Fi
    // gate itself is still enforced by the download manager.
    for (final model in catalogue.models) {
      expect(model.wifiOnly, isFalse, reason: model.id);
      expect(model.highRam, isFalse, reason: model.id);
      expect(model.fitsTargetDevice, isTrue, reason: model.id);
    }
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
        // One deliberate exception: bartowski's compact Qwythos quants ship no
        // projector, so the entry borrows empero's for the same weights.
        final projectorRepo = model.id == 'qwythos-9b-v2-compact'
            ? 'empero-ai/Qwythos-9B-v2-GGUF'
            : model.ggufRepoId;
        expect(
          mmproj.downloadUrl,
          startsWith('https://huggingface.co/$projectorRepo/resolve/main/'),
          reason: '${model.id} projector URL is wrong',
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

    test('exactly two of the seven models are text-only', () {
      final textOnly = catalogue.models.where((m) => !m.visionSupported);
      expect(
        textOnly.map((m) => m.id).toList(),
        ['phi-4-mini-3.8b', 'qwen3.5-4b-opus-4.6-distill'],
      );
    });

    test('the 4B Opus distil is text-only even though its repo has a projector',
        () {
      // The repo ships mmproj-BF16.gguf, but the card claims no vision. Listing
      // it would download 0.68 GB the app has no grounds to use.
      final model = catalogue.byId('qwen3.5-4b-opus-4.6-distill')!;
      expect(model.visionSupported, isFalse);
      expect(model.mmproj, isNull);
      expect(model.visionAbsenceNote, contains('mmproj-BF16.gguf'));
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

    test('it needs less RAM than any of the 9B-and-up models', () {
      final others = catalogue.models
          .where((m) => m.id != 'phi-4-mini-3.8b')
          .where((m) => m.sizeClass == '9B' || m.sizeClass == '27B')
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
  });

  group('sampling defaults come from the model cards', () {
    test('Qwythos records its documented repeat penalty of 1.05', () {
      final model = catalogue.byId('qwythos-9b-v2-compact')!;
      expect(model.samplingDefaults.repeatPenalty, 1.05);
    });

    test('Gemma 4 uses the card\'s standard configuration', () {
      // temperature 1.0, top_p 0.95, top_k 64 "across all use cases".
      for (final id in ['gemma-4-e4b', 'gemma-4-e2b']) {
        final sampling = catalogue.byId(id)!.samplingDefaults;
        expect(sampling.temperature, 1.0, reason: id);
        expect(sampling.topP, 0.95, reason: id);
        expect(sampling.topK, 64, reason: id);
      }
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

  test('the 89 published quantisations are all accounted for', () {
    final total = catalogue.models.fold<int>(
      0,
      (sum, model) => sum + model.quants.length,
    );
    expect(total, 89);
  });

  group('every entry fits a phone with 4-5 GB free', () {
    test('each recommended quant loads text-only in 5 GB', () {
      for (final model in catalogue.models) {
        final id = model.id;
        expect(
          model.ramRequirementGbFor(model.recommendedQuantInfo!),
          lessThanOrEqualTo(5.0),
          reason: '$id does not fit 5 GB at its recommended quant',
        );
      }
    });

    test('the 4B and 2B vision models fit 5 GB with the projector loaded', () {
      for (final id in ['qwen3.5-4b', 'qwen3.5-2b', 'gemma-4-e2b']) {
        final model = catalogue.byId(id)!;
        final withProjectorGb =
            model.ramRequirementGbFor(model.recommendedQuantInfo!) +
                model.mmproj!.sizeBytes / 1e9;
        expect(withProjectorGb, lessThanOrEqualTo(5.0), reason: id);
      }
    });

    test('the compact Qwythos quants are all smaller than empero\'s smallest',
        () {
      // empero's own repo starts at Q4_K_M, 5,629,108,896 bytes; the compact
      // entry exists only for what sits below that.
      final compact = catalogue.byId('qwythos-9b-v2-compact')!;
      expect(
        compact.quants.every((q) => q.sizeBytes < 5629108896),
        isTrue,
      );
    });
  });

  group('ramRequirementGbFor follows the installed quant', () {
    test('the recommended quant gets the catalogue figure unchanged', () {
      for (final model in catalogue.models) {
        expect(
          model.ramRequirementGbFor(model.recommendedQuantInfo!),
          closeTo(model.ramRequirementGb, 1e-9),
          reason: model.id,
        );
      }
    });

    test('a smaller quant needs less, by exactly the weight difference', () {
      final model = catalogue.byId('qwen3.5-4b')!;
      final q4 = model.recommendedQuantInfo!;
      final q2 = model.quants.firstWhere((q) => q.quant == 'Q3_K_M');
      final expected =
          model.ramRequirementGb - (q4.sizeBytes - q2.sizeBytes) / 1e9;
      expect(model.ramRequirementGbFor(q2), closeTo(expected, 1e-9));
      expect(model.ramRequirementGbFor(q2), lessThan(model.ramRequirementGb));
    });

    test('it never claims less than the weights themselves', () {
      for (final model in catalogue.models) {
        for (final quant in model.quants) {
          expect(
            model.ramRequirementGbFor(quant),
            greaterThanOrEqualTo(quant.sizeBytes / 1e9),
            reason: '${model.id} ${quant.quant}',
          );
        }
      }
    });
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
