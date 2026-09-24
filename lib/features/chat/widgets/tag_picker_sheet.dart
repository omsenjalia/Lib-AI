import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/tag_chip.dart';

/// Chooses the subject tag for the open conversation, or creates a new one.
///
/// The nine built-in tags are seeded on first launch; anything the user adds
/// lives alongside them in the same table, so there is no separate "custom"
/// code path here.
class TagPickerSheet extends ConsumerStatefulWidget {
  const TagPickerSheet({super.key, this.selectedId});

  /// Currently applied tag, highlighted in the list.
  final int? selectedId;

  /// Opens the sheet. Resolves to the chosen tag id, `-1` to clear the tag, or
  /// null if the sheet was dismissed.
  static Future<int?> show(BuildContext context, {int? selectedId}) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => TagPickerSheet(selectedId: selectedId),
    );
  }

  @override
  ConsumerState<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<TagPickerSheet> {
  final _newTagController = TextEditingController();
  bool _isCreating = false;

  /// Colours offered for a new tag. These are the same hues as the built-ins,
  /// so a user-created tag never looks out of place.
  static const List<int> _palette = [
    0xFF7FA6D9,
    0xFF9C8FD9,
    0xFF6FB3A8,
    0xFFE8A838,
    0xFFD98F7F,
    0xFF8FB86F,
    0xFFD9B87F,
    0xFFB88FD9,
    0xFF8A8A9A,
  ];

  int _selectedColor = _palette.first;

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tags = ref.watch(subjectTagsProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subject',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Conversations are grouped by subject in the sidebar.',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.brightness == Brightness.dark
                    ? AppColors.textSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 12),
            tags.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => Text('Could not load tags: $error'),
              data: (rows) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in rows)
                    TagChip(
                      name: tag.name,
                      colorValue: tag.colorValue,
                      selected: tag.id == widget.selectedId,
                      onTap: () => Navigator.of(context).pop(tag.id),
                    ),
                  if (widget.selectedId != null)
                    ActionChip(
                      avatar: const Icon(Icons.clear_rounded, size: 14),
                      label: const Text('None', style: TextStyle(fontSize: 11.5)),
                      onPressed: () => Navigator.of(context).pop(-1),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Divider(
              color: scheme.brightness == Brightness.dark
                  ? AppColors.outline
                  : AppColors.lightOutline,
            ),
            if (!_isCreating)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _isCreating = true),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('New subject'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _newTagController,
                    autofocus: true,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Subject name',
                      counterText: '',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final color in _palette)
                        GestureDetector(
                          onTap: () => setState(() => _selectedColor = color),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _selectedColor == color
                                    ? scheme.onSurface
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _isCreating = false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _create,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: const Color(0xFF1A1A2E),
                        ),
                        child: const Text('Add subject'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    final id = await ref
        .read(databaseProvider)
        .insertSubjectTag(name, _selectedColor);
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }
}
