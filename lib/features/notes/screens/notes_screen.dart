import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/claude_tokens.dart';
import '../../../core/widgets/empty_state.dart';

/// "My Notes" - the placeholder for the Phase 2 retrieval feature.
///
/// This screen exists in v1 for one reason: the schema and the navigation are
/// already in place, so adding retrieval later is an addition rather than a
/// migration plus a UI rebuild. The brief is explicit that it must say
/// "Coming soon" and must not pretend to work.
///
/// The document count is read from the database so that when the import path
/// lands, this screen starts showing real numbers without being rewritten.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final count = ref.watch(documentCountProvider);
    final secondary = tokens.muted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Notes', style: TextStyle(fontSize: 16)),
      ),
      body: Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: Icons.note_alt_outlined,
              title: 'Coming soon',
              message: 'My Notes will let you import your own PDFs and notes '
                  'and have the model answer from them - still entirely on '
                  'this device, still with no internet.',
              footnote: 'Planned for the next major version. The database '
                  'tables for documents and their embeddings are already in '
                  'place, so this will not disturb your existing '
                  'conversations.',
              action: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: tokens.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: tokens.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  count.when(
                    data: (value) => value == 0
                        ? '0 documents imported'
                        : '$value documents imported',
                    loading: () => 'Checking library...',
                    error: (error, stack) => 'Library unavailable',
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.primary,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Text(
              'Offline search across your own material needs an embedding '
              'model on the device as well as the chat model. That is a '
              'meaningful amount of extra storage, so it is being built as a '
              'deliberate opt-in rather than shipped half-working.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, height: 1.5, color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}
