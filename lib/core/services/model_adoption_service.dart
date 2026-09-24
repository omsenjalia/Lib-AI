import 'package:drift/drift.dart';

import '../data/database.dart';
import '../models/model_catalogue.dart';
import 'storage_paths.dart';

/// Finds catalogue-known model files in the active models directory and
/// re-adopts only those that pass a streaming SHA-256 check.
///
/// This is intentionally a local operation: reinstall recovery never contacts
/// Hugging Face and never downloads model bytes.
class ModelAdoptionService {
  const ModelAdoptionService({
    required AppDatabase database,
    required StoragePaths storagePaths,
  })  : _database = database,
        _storagePaths = storagePaths;

  final AppDatabase _database;
  final StoragePaths _storagePaths;

  Future<ModelAdoptionReport> adopt(ModelCatalogue catalogue) async {
    final documents = await _storagePaths.scanManagedModelFiles();
    final byName = <String, List<ModelStorageDocument>>{};
    for (final document in documents) {
      byName.putIfAbsent(document.name, () => []).add(document);
    }

    final adopted = <AdoptedModel>[];
    final failures = <ModelAdoptionFailure>[];

    for (final model in catalogue.models) {
      final quantOptions = [...model.quants];
      quantOptions.sort((left, right) {
        final leftRecommended = left.quant == model.recommendedQuant;
        final rightRecommended = right.quant == model.recommendedQuant;
        if (leftRecommended == rightRecommended) return 0;
        return leftRecommended ? -1 : 1;
      });

      QuantOption? selectedQuant;
      ModelStorageDocument? selectedDocument;
      final failedFiles = <ModelAdoptionFailure>[];
      for (final quant in quantOptions) {
        final candidates = byName[quant.fileName];
        if (candidates == null || candidates.isEmpty) continue;
        if (quant.sha256 == null || quant.sha256!.isEmpty) {
          failedFiles.add(
            ModelAdoptionFailure(
              modelId: model.id,
              modelName: model.displayName,
              fileName: quant.fileName,
              reason: 'The bundled catalogue has no checksum for this file.',
            ),
          );
          continue;
        }

        for (final candidate in candidates) {
          try {
            final actual = await _storagePaths.sha256Of(candidate.locator);
            if (actual.toLowerCase() == quant.sha256!.toLowerCase()) {
              selectedQuant = quant;
              selectedDocument = candidate;
              break;
            }
            failedFiles.add(
              ModelAdoptionFailure(
                modelId: model.id,
                modelName: model.displayName,
                fileName: quant.fileName,
                reason: 'The SHA-256 checksum did not match.',
              ),
            );
          } catch (_) {
            failedFiles.add(
              ModelAdoptionFailure(
                modelId: model.id,
                modelName: model.displayName,
                fileName: quant.fileName,
                reason: 'The model file could not be read for verification.',
              ),
            );
          }
        }
        if (selectedQuant != null) break;
      }

      if (selectedQuant == null || selectedDocument == null) {
        failures.addAll(failedFiles);
        continue;
      }

      String? mmprojLocator;
      var totalBytes = selectedDocument.length;
      final mmproj = model.mmproj;
      if (mmproj != null) {
        final candidates = byName[mmproj.fileName] ?? const [];
        for (final candidate in candidates) {
          if (mmproj.sha256 == null || mmproj.sha256!.isEmpty) {
            failures.add(
              ModelAdoptionFailure(
                modelId: model.id,
                modelName: model.displayName,
                fileName: mmproj.fileName,
                reason: 'The bundled catalogue has no checksum for this projector.',
              ),
            );
            break;
          }
          try {
            final actual = await _storagePaths.sha256Of(candidate.locator);
            if (actual.toLowerCase() == mmproj.sha256!.toLowerCase()) {
              mmprojLocator = candidate.locator;
              totalBytes += candidate.length;
            } else {
              failures.add(
                ModelAdoptionFailure(
                  modelId: model.id,
                  modelName: model.displayName,
                  fileName: mmproj.fileName,
                  reason: 'The SHA-256 checksum did not match.',
                ),
              );
            }
          } catch (_) {
            failures.add(
              ModelAdoptionFailure(
                modelId: model.id,
                modelName: model.displayName,
                fileName: mmproj.fileName,
                reason: 'The projector file could not be read for verification.',
              ),
            );
          }
          if (mmprojLocator != null) break;
        }
      }

      await _database.upsertInstallation(
        ModelInstallationsCompanion.insert(
          modelId: model.id,
          quant: selectedQuant.quant,
          fileName: selectedQuant.fileName,
          localPath: selectedDocument.locator,
          mmprojPath: Value(mmprojLocator),
          sizeBytes: selectedQuant.sizeBytes,
          sha256: Value(selectedQuant.sha256),
          repoSha: Value(model.ggufRepoSha),
          repoLastModified: Value(model.ggufRepoLastModified),
          totalBytes: totalBytes,
        ),
      );
      await _database.upsertUpdateCheck(
        ModelUpdateChecksCompanion.insert(
          modelId: model.id,
          lastCheckedAt: DateTime.now(),
          remoteSha: Value(model.ggufRepoSha),
          remoteLastModified: Value(model.ggufRepoLastModified),
          updateAvailable: const Value(false),
        ),
      );
      adopted.add(
        AdoptedModel(
          modelId: model.id,
          modelName: model.displayName,
          quant: selectedQuant.quant,
          fileName: selectedQuant.fileName,
          usedSaf: selectedDocument.locator.startsWith('content://'),
        ),
      );
    }

    return ModelAdoptionReport(adopted: adopted, failures: failures);
  }
}

class ModelAdoptionReport {
  const ModelAdoptionReport({required this.adopted, required this.failures});

  final List<AdoptedModel> adopted;
  final List<ModelAdoptionFailure> failures;
}

class AdoptedModel {
  const AdoptedModel({
    required this.modelId,
    required this.modelName,
    required this.quant,
    required this.fileName,
    required this.usedSaf,
  });

  final String modelId;
  final String modelName;
  final String quant;
  final String fileName;
  final bool usedSaf;
}

class ModelAdoptionFailure {
  const ModelAdoptionFailure({
    required this.modelId,
    required this.modelName,
    required this.fileName,
    required this.reason,
  });

  final String modelId;
  final String modelName;
  final String fileName;
  final String reason;
}
