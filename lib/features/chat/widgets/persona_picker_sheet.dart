import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/claude_tokens.dart';

/// Chooses the study persona whose system prompt is prepended to every turn in
/// this conversation.
///
/// The persona is a per-conversation setting rather than a global one, because
/// the same user may want a code reviewer for one thread and an exam coach for
/// another.
class PersonaPickerSheet extends ConsumerWidget {
  const PersonaPickerSheet({super.key, this.selectedId});

  final int? selectedId;

  /// Opens the sheet. Resolves to the chosen persona id, `-1` to clear it, or
  /// null if dismissed.
  static Future<int?> show(BuildContext context, {int? selectedId}) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => PersonaPickerSheet(selectedId: selectedId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final personas = ref.watch(personasProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Study persona',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Sets the system prompt for this conversation.',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.brightness == Brightness.dark
                    ? tokens.muted
                    : tokens.muted,
              ),
            ),
            const SizedBox(height: 12),
            personas.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => Text('Could not load personas: $error'),
              data: (rows) => Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length + 1,
                  itemBuilder: (context, index) {
                    if (index == rows.length) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.block_rounded, size: 18),
                        title: const Text('No persona',
                            style: TextStyle(fontSize: 13)),
                        subtitle: const Text(
                          'Use the default study-assistant prompt',
                          style: TextStyle(fontSize: 11),
                        ),
                        onTap: () => Navigator.of(context).pop(-1),
                      );
                    }
                    final persona = rows[index];
                    final isSelected = persona.id == selectedId;
                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor:
                          scheme.primary.withValues(alpha: 0.08),
                      leading: Text(
                        persona.emoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                      title: Text(
                        persona.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        _preview(persona.systemPrompt),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, height: 1.3),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded,
                              size: 16, color: tokens.primary)
                          : null,
                      onTap: () => Navigator.of(context).pop(persona.id),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// First sentence of the prompt, so the list explains what each persona does
  /// instead of only naming it.
  static String _preview(String prompt) {
    final flat = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    final stop = flat.indexOf('. ');
    if (stop == -1 || stop > 120) {
      return flat.length > 120 ? '${flat.substring(0, 117)}...' : flat;
    }
    return flat.substring(0, stop + 1);
  }
}
