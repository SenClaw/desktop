// Shared UI for the runtime-missing state (runtime-protocol.md §5.2): OCR,
// TTS, Whisper and Decision (Laya) settings show [RuntimeMissingBanner] in
// place of their model list when the daemon 503s because no runtime backs
// their slot; voice features (audio_service.dart, voice_chat_overlay.dart)
// show [showRuntimeMissingSnack] instead, since they have no settings body to
// replace. Both send the user to the same place via [openRuntimeSettings].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/shell.dart' show openRuntimeSettings;
import '../core/i18n/l10n.dart';
import '../core/transport/runtime_missing.dart';
import '../theme/tokens.dart';

/// Replaces a settings section's model list when its slot's runtime is
/// missing, unselected, or failed to start. The daemon's own message is
/// shown verbatim (it already names the slot and the reason); this only adds
/// the shared framing and the way out.
class RuntimeMissingBanner extends ConsumerWidget {
  const RuntimeMissingBanner({super.key, required this.error});
  final RuntimeMissingException error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.s16),
      decoration: BoxDecoration(
        color: AppTokens.warning.withValues(alpha: 0.08),
        border: Border.all(color: AppTokens.warning.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.extension_off_outlined,
                  size: 18, color: AppTokens.warning),
              const SizedBox(width: AppTokens.s8),
              Expanded(
                child: Text(context.tr('No runtime is installed for this'),
                    style: TextStyle(
                        color: c.textPrimary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s8),
          SelectableText(error.message,
              style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
          const SizedBox(height: AppTokens.s12),
          OutlinedButton.icon(
            onPressed: () => openRuntimeSettings(context, ref),
            icon: const Icon(Icons.settings_outlined, size: 16),
            label: Text(context.tr('Open Runtime settings')),
          ),
        ],
      ),
    );
  }
}

/// For a feature with no settings body to replace (voice input/output): a
/// snackbar carrying the same message and the same way out.
void showRuntimeMissingSnack(
  BuildContext context,
  WidgetRef ref,
  RuntimeMissingException error,
) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(error.message),
    duration: const Duration(seconds: 6),
    action: SnackBarAction(
      label: context.tr('Open Runtime settings'),
      onPressed: () => openRuntimeSettings(context, ref),
    ),
  ));
}
