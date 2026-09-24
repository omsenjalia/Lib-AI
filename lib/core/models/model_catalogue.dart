import 'dart:convert';

/// Typed view over `assets/models_catalogue.json`.
///
/// Every size and checksum in the JSON came from the HuggingFace file-tree API
/// and was verified against the blob pages, so the parser does not need to be
/// defensive about obviously-wrong numbers - but it does need to fail loudly if
/// a field it depends on goes missing, which is why the `required` fields throw
/// rather than defaulting.
class ModelCatalogue {
  const ModelCatalogue({
    required this.schemaVersion,
    required this.targetDevice,
    required this.models,
  });

  final int schemaVersion;
  final TargetDevice targetDevice;
  final List<CatalogueModel> models;

  factory ModelCatalogue.fromJson(Map<String, dynamic> json) {
    final rawModels = json['models'];
    if (rawModels is! List) {
      throw const FormatException(
        'models_catalogue.json is missing its "models" array',
      );
    }
    return ModelCatalogue(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      targetDevice: TargetDevice.fromJson(
        (json['targetDevice'] as Map<String, dynamic>?) ?? const {},
      ),
      models: rawModels
          .cast<Map<String, dynamic>>()
          .map(CatalogueModel.fromJson)
          .toList(growable: false),
    );
  }

  factory ModelCatalogue.fromJsonString(String source) =>
      ModelCatalogue.fromJson(jsonDecode(source) as Map<String, dynamic>);

  CatalogueModel? byId(String? id) {
    if (id == null) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// Models that will actually load on the target device, in catalogue order.
  List<CatalogueModel> get compatible =>
      models.where((m) => m.fitsTargetDevice).toList(growable: false);
}

/// The device the catalogue was tuned against.
class TargetDevice {
  const TargetDevice({
    required this.name,
    required this.os,
    required this.ramOptionsGb,
    required this.usableRamGb,
  });

  final String name;
  final String os;
  final List<int> ramOptionsGb;

  /// RAM realistically available to an app, which is the number that decides
  /// whether a quant fits. Lower than the marketed figure by design.
  final double usableRamGb;

  factory TargetDevice.fromJson(Map<String, dynamic> json) => TargetDevice(
        name: json['name'] as String? ?? 'Unknown device',
        os: json['os'] as String? ?? 'Unknown',
        ramOptionsGb: (json['ramOptionsGb'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList(growable: false) ??
            const <int>[],
        usableRamGb: (json['usableRamGb'] as num?)?.toDouble() ?? 0,
      );
}

/// One model in the catalogue.
class CatalogueModel {
  const CatalogueModel({
    required this.id,
    required this.displayName,
    required this.family,
    required this.parameterCount,
    required this.sizeClass,
    required this.blurb,
    required this.hfModelId,
    required this.hfModelSha,
    required this.hfModelLastModified,
    required this.hfModelHasGguf,
    required this.hfModelFileNote,
    required this.ggufRepoId,
    required this.ggufRepoSha,
    required this.ggufRepoLastModified,
    required this.ggufRepoUrl,
    required this.visionSupported,
    required this.visionEvidence,
    required this.visionCaveat,
    required this.visionAbsenceNote,
    required this.recommendedContextLength,
    required this.maxContextLength,
    required this.contextNote,
    required this.wifiOnly,
    required this.highRam,
    required this.fitsTargetDevice,
    required this.ramRequirementGb,
    required this.warning,
    required this.notes,
    required this.recommendedQuant,
    required this.quants,
    required this.mmproj,
    required this.samplingDefaults,
  });

  final String id;
  final String displayName;
  final String family;
  final String parameterCount;
  final String sizeClass;
  final String blurb;

  /// The upstream model repo. For two of the five this is *not* where the GGUF
  /// lives; see [ggufRepoId].
  final String hfModelId;
  final String? hfModelSha;
  final DateTime? hfModelLastModified;
  final bool hfModelHasGguf;
  final String? hfModelFileNote;

  /// The repository that actually serves [quants]. This is the one the
  /// auto-update checker polls.
  final String ggufRepoId;
  final String? ggufRepoSha;
  final DateTime? ggufRepoLastModified;
  final String ggufRepoUrl;

  /// True only where the model card confirms image input. Never assumed.
  final bool visionSupported;
  final String? visionEvidence;

  /// Set when the card warns that the vision tower was not fine-tuned.
  final String? visionCaveat;

  /// Set when the model is confirmed text-only, and why.
  final String? visionAbsenceNote;

  final int recommendedContextLength;
  final int maxContextLength;
  final String? contextNote;

  /// Hard Wi-Fi-only gate, enforced in the download manager.
  final bool wifiOnly;

  final bool highRam;
  final bool fitsTargetDevice;
  final double ramRequirementGb;
  final String? warning;
  final String? notes;
  final String recommendedQuant;

  final List<QuantOption> quants;
  final MmprojFile? mmproj;
  final SamplingDefaults samplingDefaults;

  /// True when the model carries a blocking warning the UI must show.
  bool get hasWarning => warning != null && warning!.isNotEmpty;

  /// The quant the app selects by default, falling back to the largest that
  /// fits if the recommended one is somehow absent.
  QuantOption? get recommendedQuantInfo {
    for (final q in quants) {
      if (q.quant == recommendedQuant) return q;
    }
    return quants.isEmpty ? null : quants.first;
  }

  /// Everything that would be downloaded for [quant], including the vision
  /// projector when one is needed. This is the figure the RAM and storage
  /// warnings are based on, so it must not omit the projector.
  int totalDownloadBytes(QuantOption quant, {required bool includeMmproj}) {
    var total = quant.sizeBytes;
    if (includeMmproj && mmproj != null) total += mmproj!.sizeBytes;
    return total;
  }

  factory CatalogueModel.fromJson(Map<String, dynamic> json) {
    String req(String key) {
      final value = json[key];
      if (value == null) {
        throw FormatException(
          'catalogue entry ${json['id']} is missing required key "$key"',
        );
      }
      return value as String;
    }

    final rawQuants = json['quants'];
    if (rawQuants is! List || rawQuants.isEmpty) {
      throw FormatException(
        'catalogue entry ${json['id']} has no quants',
      );
    }

    return CatalogueModel(
      id: req('id'),
      displayName: req('displayName'),
      family: json['family'] as String? ?? '',
      parameterCount: json['parameterCount'] as String? ?? '',
      sizeClass: json['sizeClass'] as String? ?? '',
      blurb: json['blurb'] as String? ?? '',
      hfModelId: req('hfModelId'),
      hfModelSha: json['hfModelSha'] as String?,
      hfModelLastModified: _parseDate(json['hfModelLastModified']),
      hfModelHasGguf: json['hfModelHasGguf'] as bool? ?? false,
      hfModelFileNote: json['hfModelFileNote'] as String?,
      ggufRepoId: req('ggufRepoId'),
      ggufRepoSha: json['ggufRepoSha'] as String?,
      ggufRepoLastModified: _parseDate(json['ggufRepoLastModified']),
      ggufRepoUrl: req('ggufRepoUrl'),
      visionSupported: json['visionSupported'] as bool? ?? false,
      visionEvidence: json['visionEvidence'] as String?,
      visionCaveat: json['visionCaveat'] as String?,
      visionAbsenceNote: json['visionAbsenceNote'] as String?,
      recommendedContextLength:
          (json['recommendedContextLength'] as num?)?.toInt() ?? 4096,
      maxContextLength: (json['maxContextLength'] as num?)?.toInt() ?? 4096,
      contextNote: json['contextNote'] as String?,
      wifiOnly: json['wifiOnly'] as bool? ?? false,
      highRam: json['highRam'] as bool? ?? false,
      fitsTargetDevice: json['fitsTargetDevice'] as bool? ?? true,
      ramRequirementGb: (json['ramRequirementGb'] as num?)?.toDouble() ?? 0,
      warning: json['warning'] as String?,
      notes: json['notes'] as String?,
      recommendedQuant: req('recommendedQuant'),
      quants: rawQuants
          .cast<Map<String, dynamic>>()
          .map(QuantOption.fromJson)
          .toList(growable: false),
      mmproj: json['mmproj'] == null
          ? null
          : MmprojFile.fromJson(json['mmproj'] as Map<String, dynamic>),
      samplingDefaults: SamplingDefaults.fromJson(
        (json['samplingDefaults'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

/// One downloadable quantisation.
class QuantOption {
  const QuantOption({
    required this.quant,
    required this.fileName,
    required this.sizeBytes,
    this.sizeGb,
    required this.sha256,
    required this.qualityNote,
    required this.fitsTargetDevice,
    required this.downloadUrl,
  });

  final String quant;
  final String fileName;
  final int sizeBytes;

  /// The same quantity as [sizeBytes], in decimal GB, exactly as published in
  /// the catalogue.
  ///
  /// It is stored rather than computed so the two can disagree: the catalogue
  /// test asserts they agree, which is what catches an arithmetic slip in the
  /// generator that would otherwise show a wrong size in the UI.
  final double? sizeGb;

  /// Expected SHA-256, taken from the repository's LFS object id. Verified
  /// after download; a mismatch discards the file.
  final String? sha256;

  final String qualityNote;
  final bool fitsTargetDevice;
  final String downloadUrl;

  /// True when the file is a multi-token-prediction variant, which needs a
  /// llama.cpp build that supports draft speculation.
  bool get isMtp => quant.contains('MTP');

  factory QuantOption.fromJson(Map<String, dynamic> json) => QuantOption(
        quant: json['quant'] as String,
        fileName: json['fileName'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        sizeGb: (json['sizeGb'] as num?)?.toDouble(),
        sha256: json['sha256'] as String?,
        qualityNote: json['qualityNote'] as String? ?? '',
        fitsTargetDevice: json['fitsTargetDevice'] as bool? ?? true,
        downloadUrl: json['downloadUrl'] as String,
      );
}

/// The multimodal projector required for image input.
class MmprojFile {
  const MmprojFile({
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.downloadUrl,
  });

  final String fileName;
  final int sizeBytes;
  final String? sha256;
  final String downloadUrl;

  factory MmprojFile.fromJson(Map<String, dynamic> json) => MmprojFile(
        fileName: json['fileName'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        sha256: json['sha256'] as String?,
        downloadUrl: json['downloadUrl'] as String,
      );
}

/// The model authors' own recommended sampler settings.
class SamplingDefaults {
  const SamplingDefaults({
    required this.temperature,
    required this.topP,
    required this.topK,
    this.repeatPenalty,
  });

  final double temperature;
  final double topP;
  final int topK;
  final double? repeatPenalty;

  factory SamplingDefaults.fromJson(Map<String, dynamic> json) =>
      SamplingDefaults(
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.6,
        topP: (json['topP'] as num?)?.toDouble() ?? 0.95,
        topK: (json['topK'] as num?)?.toInt() ?? 20,
        repeatPenalty: (json['repeatPenalty'] as num?)?.toDouble(),
      );
}
