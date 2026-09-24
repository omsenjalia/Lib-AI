import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/storage_paths.dart';
import '../../../core/theme/app_colors.dart';

/// The message input.
///
/// Three behaviours worth stating, because each is a small piece of the app's
/// contract with the user:
///
///  * While the model is answering, the send button becomes a stop button. A
///    generation can take a while on this device, and an input that silently
///    ignores taps is how a user concludes the app has frozen.
///  * OCR mode is offered but refused when the active model cannot see. The
///    button is disabled with a reason rather than hidden, so the feature is
///    discoverable without being a lie.
///  * The camera opens through the system intent, which is why the app declares
///    no CAMERA permission.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.onSend,
    required this.onStop,
    required this.isGenerating,
    required this.visionAvailable,
    this.enabled = true,
    this.disabledReason,
    this.trailing,
    this.header,
  });

  /// Called with the typed text and, in OCR mode, the path to a saved image.
  final void Function(String text, String? imagePath) onSend;

  final VoidCallback onStop;
  final bool isGenerating;

  /// True only when the active model is multimodal *and* its projector is on
  /// disk.
  final bool visionAvailable;

  final bool enabled;

  /// Shown in place of the input when [enabled] is false, e.g. "No model
  /// installed yet".
  final String? disabledReason;

  /// Optional widget shown under the input, e.g. the model switcher row.
  final Widget? trailing;

  /// Optional widget shown above the input, e.g. the context meter.
  final Widget? header;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// Path of an image captured for the *next* message, cleared once sent.
  String? _pendingImagePath;
  bool _isCapturing = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSend =>
      widget.enabled &&
      !widget.isGenerating &&
      (_controller.text.trim().isNotEmpty || _pendingImagePath != null);

  void _send() {
    if (!_canSend) return;
    final text = _controller.text;
    final image = _pendingImagePath;
    _controller.clear();
    setState(() => _pendingImagePath = null);
    widget.onSend(text, image);
    _focusNode.requestFocus();
  }

  Future<void> _captureImage() async {
    if (!widget.visionAvailable || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        // Downscale on the way in: a 12 MP photo would be base64-inlined into
        // the prompt and cost both memory and context for no extra legibility.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (shot == null) return;

      // Copy out of the camera cache before referencing it from a message.
      final saved = await StoragePaths.persistAttachment(File(shot.path));
      if (!mounted) return;
      setState(() => _pendingImagePath = saved.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Could not open the camera: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    if (!widget.enabled) {
      return _disabled(context);
    }

    return Container(
      decoration: BoxDecoration(
        color: isLight ? AppColors.lightSurface : AppColors.surface,
        border: Border(
          top: BorderSide(
            color: isLight ? AppColors.lightOutline : AppColors.outline,
            width: 0.7,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.header != null) ...[
              widget.header!,
              const SizedBox(height: 8),
            ],
            if (_pendingImagePath != null) _imagePreview(context),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _AttachButton(
                  enabled: widget.visionAvailable,
                  busy: _isCapturing,
                  onPressed: _captureImage,
                  onExplained: widget.visionAvailable
                      ? null
                      : () => _explainVision(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isLight
                          ? AppColors.lightSurfaceHigh
                          : AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? AppColors.accent.withValues(alpha: 0.7)
                            : (isLight
                                ? AppColors.lightOutline
                                : AppColors.outline),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(fontSize: 14, color: scheme.onSurface),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        hintText: _pendingImagePath != null
                            ? 'Add a question about the image (optional)'
                            : 'Ask about anything you are studying',
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: isLight
                              ? AppColors.lightTextSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SendButton(
                  isGenerating: widget.isGenerating,
                  enabled: _canSend,
                  onSend: _send,
                  onStop: widget.onStop,
                ),
              ],
            ),
            if (widget.trailing != null) ...[
              const SizedBox(height: 6),
              widget.trailing!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _imagePreview(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(_pendingImagePath!),
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                color: AppColors.error.withValues(alpha: 0.15),
                child: const Icon(Icons.broken_image_outlined, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Photo attached. It is sent to the model as an image and never '
              'uploaded anywhere.',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _pendingImagePath = null),
            iconSize: 16,
            tooltip: 'Remove photo',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  void _explainVision(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This model cannot see images'),
        content: const Text(
          'OCR mode sends the photo to the model itself, so it only works with '
          'a vision-capable model that has its projector downloaded.\n\n'
          'Switch model from the selector below the input, or download one of '
          'the vision-capable models in Model Library.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _disabled(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.surface
            : AppColors.lightSurface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.outline
                : AppColors.lightOutline,
            width: 0.7,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.disabledReason ?? 'Chat is unavailable.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({
    required this.enabled,
    required this.busy,
    required this.onPressed,
    this.onExplained,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  /// Called instead of [onPressed] when the feature is unavailable, so the
  /// button can explain itself rather than doing nothing.
  final VoidCallback? onExplained;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    return IconButton(
      onPressed: busy ? null : (enabled ? onPressed : onExplained),
      tooltip: enabled
          ? 'Take a photo (OCR mode)'
          : 'This model cannot see images',
      iconSize: 20,
      color: enabled ? scheme.primary : secondary.withValues(alpha: 0.6),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(enabled ? Icons.photo_camera_outlined : Icons.no_photography_outlined),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isGenerating,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  final bool isGenerating;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isGenerating) {
      return Tooltip(
        message: 'Stop generating',
        child: Material(
          color: scheme.error,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onStop,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.stop_rounded, size: 20, color: scheme.onError),
            ),
          ),
        ),
      );
    }

    return Material(
      color: enabled
          ? scheme.primary
          : scheme.primary.withValues(alpha: 0.25),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onSend : null,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 20,
            color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
