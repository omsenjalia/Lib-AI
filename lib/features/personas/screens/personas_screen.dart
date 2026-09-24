import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';

/// The persona library: the six study personas that ship with the app, plus
/// anything the user writes themselves.
///
/// Personas are rows in SQLite, not constants, which is what lets a user edit
/// a built-in's prompt. The `isBuiltIn` flag is not a permission - it only
/// decides whether the row can be deleted, so that "General Tutor" cannot be
/// removed and then be missing from the chat screen's picker.
class PersonasScreen extends ConsumerWidget {
  const PersonasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Personas', style: TextStyle(fontSize: 16)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF1A1A2E),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New persona'),
      ),
      body: personas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load personas: $error'),
          ),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.school_outlined,
              title: 'No personas',
              message: 'Create one to set the tone for your study sessions.',
            );
          }

          final builtIn = rows.where((p) => p.isBuiltIn).toList();
          final custom = rows.where((p) => !p.isBuiltIn).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              _sectionLabel(context, 'Built in'),
              for (final persona in builtIn)
                _tile(context, ref, persona, deleteAllowed: false),
              if (custom.isNotEmpty) ...[
                const SizedBox(height: 14),
                _sectionLabel(context, 'Your personas'),
                for (final persona in custom)
                  _tile(context, ref, persona, deleteAllowed: true),
              ],
              const SizedBox(height: 18),
              _explainer(context),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: secondary,
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    Persona persona, {
    required bool deleteAllowed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final secondary =
        isLight ? AppColors.lightTextSecondary : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isLight ? AppColors.lightSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLight ? AppColors.lightOutline : AppColors.outline,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(persona.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    persona.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit prompt',
                  onPressed: () => _edit(context, ref, persona),
                  iconSize: 17,
                  icon: const Icon(Icons.edit_outlined),
                ),
                if (deleteAllowed)
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => _delete(context, ref, persona),
                    iconSize: 17,
                    color: AppColors.error,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                persona.systemPrompt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, height: 1.45, color: secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _explainer(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Text(
        'A persona is a system prompt. Unlike a general prompt, it is sent '
        'before every turn, so it costs context window on every message. The '
        'built-in prompts ask for LaTeX maths and fenced code, which is what '
        'lets the chat panel render equations and syntax-highlight code.',
        style: TextStyle(fontSize: 11, height: 1.5, color: secondary),
      ),
    );
  }

  // ------------------------------------------------------------------ actions

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Persona? persona,
  ) async {
    final result = await showModalBottomSheet<_PersonaDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PersonaEditorSheet(persona: persona),
    );
    if (result == null) return;

    final database = ref.read(databaseProvider);
    if (persona == null) {
      await database.insertPersona(
        name: result.name,
        systemPrompt: result.prompt,
        emoji: result.emoji,
      );
    } else {
      await database.updatePersona(
        id: persona.id,
        name: result.name,
        systemPrompt: result.prompt,
        emoji: result.emoji,
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Persona persona,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete "${persona.name}"?',
      message: 'Conversations that used this persona keep their messages; '
          'they simply stop using the prompt.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await ref.read(databaseProvider).deletePersona(persona.id);
  }
}

/// The values collected by the editor sheet.
class _PersonaDraft {
  const _PersonaDraft({
    required this.name,
    required this.prompt,
    required this.emoji,
  });

  final String name;
  final String prompt;
  final String emoji;
}

class _PersonaEditorSheet extends StatefulWidget {
  const _PersonaEditorSheet({this.persona});

  final Persona? persona;

  @override
  State<_PersonaEditorSheet> createState() => _PersonaEditorSheetState();
}

class _PersonaEditorSheetState extends State<_PersonaEditorSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.persona?.name ?? '');
  late final TextEditingController _promptController =
      TextEditingController(text: widget.persona?.systemPrompt ?? '');
  late String _emoji = widget.persona?.emoji ?? '\u{1F4DA}';

  static const List<String> _emojis = [
    '\u{1F4DA}',
    '\u{1F4BB}',
    '\u{1F9EE}',
    '\u{1F4CB}',
    '\u{1F50D}',
    '\u{270D}',
    '\u{1F9EA}',
    '\u{1F4D0}',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.persona != null;
    final name = _nameController.text.trim();
    final prompt = _promptController.text.trim();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'Edit persona' : 'New persona',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(_emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      counterText: '',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                for (final emoji in _emojis)
                  GestureDetector(
                    onTap: () => setState(() => _emoji = emoji),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _emoji == emoji
                              ? AppColors.accent
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(emoji,
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _promptController,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'System prompt',
                hintText: 'Describe how the model should answer.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Sent before every turn, so it uses context window on every '
                'message. If you want LaTeX rendered, ask for maths between '
                r'$...$'
                ' or '
                r'$$...$$'
                '.',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.45,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.textSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (name.isEmpty || prompt.isEmpty)
                      ? null
                      : () => Navigator.of(context).pop(
                            _PersonaDraft(
                              name: name,
                              prompt: prompt,
                              emoji: _emoji,
                            ),
                          ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFF1A1A2E),
                  ),
                  child: Text(isEditing ? 'Save' : 'Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
