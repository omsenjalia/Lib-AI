import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../constants/app_constants.dart';
import '../models/model_catalogue.dart';

/// Loads the shipped model catalogue.
///
/// The catalogue is a bundled asset, not a network resource. The app therefore
/// has a complete, accurate model list on a device that has never been online -
/// which is the whole premise of the product.
class CatalogueRepository {
  CatalogueRepository({this.assetPath = AppConstants.catalogueAssetPath});

  final String assetPath;

  ModelCatalogue? _cached;

  /// Parsed catalogue, loaded once and memoised. The asset is small (~44 KB).
  Future<ModelCatalogue> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final source = await rootBundle.loadString(assetPath);
    // Decode via a Map rather than letting `loadString` hand back an
    // already-decoded object, so a malformed asset produces a clear
    // FormatException instead of a runtime type error.
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final catalogue = ModelCatalogue.fromJson(decoded);
    _cached = catalogue;
    return catalogue;
  }
}
