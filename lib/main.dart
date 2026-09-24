import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Entry point.
///
/// There is no `async` work before `runApp`: the database opens lazily on the
/// first read (in a background isolate, via `NativeDatabase.createInBackground`)
/// and settings load after the first frame. Blocking here on either of those is
/// the most common way a Flutter app adds hundreds of milliseconds to its cold
/// start for no benefit.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LibraryAiApp()));
}
