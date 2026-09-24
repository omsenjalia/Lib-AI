import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/storage_paths.dart';
import '../../../core/theme/claude_tokens.dart';

/// The message input.
///
/// It floats directly on the canvas: no surface fill, no top border and no
/// shadow. The reference communicates the composer's separation from the
/// transcript with the pill's own fill and nothing else, and the earlier
/// elevated panel with a hairline top border was the single largest visual
/// difference from it.
///
/// Three behaviours worth stating, because each is a small piece of the app's
/// contract with the user:
///
///  * While the model is answering, the send button becomes a stop button. A
///    generation can take a while on this device, and an input that silently
///    ignores taps is how a user concludes the app has frozen.
///  * OCR mode is offered but refused when the active model cannot see. The
///    button explains why rather than being hidden, so the feature is
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
    this.header,
    this.onFirstKeystroke,
    this.focusNode,
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

  /// Optional widget shown above the input, e.g. the attached-image preview.
  final Widget? header;

  /// Fired once, on the first character typed into an empty field — the home
  /// screen uses it to retire its suggestion chips.
  final VoidCallback? onFirstKeystroke;

  final FocusNode? focusNode;

  @override
  State<MessageComposer> createState() => MessageComposerState();
}

class MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// Path of an image captured for the *next* message, cleared once sent.
  String? _pendingImagePath;
  bool _isCapturing = false;
  bool _announcedFirstKeystroke = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Lets the home screen's suggestion chips fill the field.
  void setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focusNode.requestFocus();
    _announceFirstKeystroke();
    setState(() {});
  }

  bool get _hasImage => _pendingImagePath != null;

  bool get _canSend =>
      widget.enabled &&
      !widget.isGenerating &&
      (_controller.text.trim().isNotEmpty || _hasImage);

  void _announceFirstKeystroke() {
    if (_announcedFirstKeystroke) return;
    _announcedFirstKeystroke = true;
    widget.onFirstKeystroke?.call();
  }

  void _send() {
    if (!_canSend) return;
    final text = _controller.text;
    final image = _pendingImagePath;
    _controller.clear();
    // The chips have already retired by now in practice; this keeps a sent
    // message from reviving them when the field empties.
    _announcedFirstKeystroke = true;
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
        SnackBar(content: Text('Could not open the camera: $error')),
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (!widget.enabled) return _disabled(context);

    // The system inset plus the 8 dp the tokens ask for when the keyboard is
    // down, and the 8 dp alone when it is up: `viewPadding` is not reduced by
    // the keyboard, so using it unconditionally would leave a gesture-bar-sized
    // gap under a field that is already sitting on the keyboard.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomInset =
        keyboardOpen ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ClaudeSpacing.sm,
        ClaudeSpacing.xs,
        ClaudeSpacing.sm,
        bottomInset + ClaudeSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasImage) _imagePreview(context),
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
              const SizedBox(width: ClaudeSpacing.xxs),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: tokens.surfaceSoft,
                    borderRadius:
                        BorderRadius.circular(ClaudeRadius.pill),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? tokens.primary
                          : tokens.hairline,
                    ),
                  ),
                  constraints:
                      const BoxConstraints(minHeight: ClaudeSpacing.minTouchTarget),
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaudeSpacing.md,
                    vertical: 4,
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: widget.focusNode ?? _focusNode,
                    minLines: 1,
                    // Grows to five lines, then scrolls inside the field.
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    style: ClaudeType.chatBody(
                      ChatFontFamily.lato,
                    ).copyWith(color: tokens.ink),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      hintText: _hasImage
                          ? 'Ask something about the photo'
                          : 'Message Library AI',
                      hintStyle: ClaudeType.body.copyWith(color: tokens.muted),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) _announceFirstKeystroke();
                      setState(() {});
                    },
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: ClaudeSpacing.xxs),
              _SendButton(
                isGenerating: widget.isGenerating,
                enabled: _canSend,
                onSend: _send,
                onStop: widget.onStop,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 64 dp thumbnail with an ×-dismiss, sliding down into place.
  Widget _imagePreview(BuildContext context) {
    final tokens = context.tokens;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: -0.4, end: 0),
      duration: ClaudeMotion.fast,
      curve: ClaudeMotion.easeOut,
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, value * 24),
        child: Opacity(opacity: (1 + value * 2.5).clamp(0.0, 1.0), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: ClaudeSpacing.xs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(ClaudeRadius.lg),
                child: Image.file(
                  File(_pendingImagePath!),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    color: tokens.surfaceCard,
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 18,
                      color: tokens.muted,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Material(
                  color: tokens.codeSurface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _pendingImagePath = null),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: tokens.onCode,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          'Switch model from the name in the top bar, or download one of the '
          'vision-capable models in Model Library.',
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
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaudeSpacing.md,
        ClaudeSpacing.md,
        ClaudeSpacing.md,
        ClaudeSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: tokens.muted),
          const SizedBox(width: ClaudeSpacing.sm),
          Expanded(
            child: Text(
              widget.disabledReason ?? 'Chat is unavailable.',
              style: ClaudeType.caption.copyWith(color: tokens.muted),
            ),
          ),
        ],
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
    final tokens = context.tokens;

    return Tooltip(
      message: enabled
          ? 'Take a photo (OCR mode)'
          : 'This model cannot see images',
      child: IconButton(
        onPressed: busy ? null : (enabled ? onPressed : onExplained),
        iconSize: 24,
        color: enabled
            ? tokens.muted
            : tokens.muted.withValues(alpha: 0.6),
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.photo_camera_outlined),
      ),
    );
  }
}

/// 32 dp disc: accent with an up-arrow when there is something to send, a
/// hairline fill when there is not.
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
    final tokens = context.tokens;

    final (Color background, Color foreground, IconData icon, VoidCallback?
        onTap, String tooltip) = isGenerating
        ? (
            tokens.ink,
            tokens.canvas,
            Icons.stop_rounded,
            onStop,
            'Stop generating',
          )
        : enabled
            ? (
                tokens.primary,
                tokens.onPrimary,
                Icons.arrow_upward_rounded,
                onSend,
                'Send',
              )
            : (
                tokens.surfaceStrong,
                tokens.muted,
                Icons.arrow_upward_rounded,
                null,
                'Type a message first',
              );

    return Tooltip(
      message: tooltip,
      // The disc is 32 dp because that is what the reference draws; the touch
      // target around it is the full 48.
      child: SizedBox(
        width: ClaudeSpacing.minTouchTarget,
        height: ClaudeSpacing.minTouchTarget,
        child: Center(
          child: Material(
            color: background,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(icon, size: 17, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
