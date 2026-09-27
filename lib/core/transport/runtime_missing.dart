// The shape every legacy `/api/ocr|tts|whisper|decision/*` route and the
// `/api/runtimes/models/*` proxy answer with when no runtime can serve the
// request (runtime-protocol.md §5.2): a 503 with `code` naming exactly which
// of the three ways a slot can be unusable. Screens and voice features show a
// dedicated banner/snack for this instead of a generic error — see
// `lib/widgets/runtime_missing_banner.dart` for the UI half.

import 'dart:convert';

import 'api_client.dart';

const runtimeMissingCodes = {
  'runtime_not_installed',
  'runtime_not_selected',
  'runtime_start_failed',
};

/// A daemon 503 naming a missing, unselected or unstartable runtime for a
/// slot. Distinct from [ApiException] so a call site that speaks to the
/// daemon directly (audio_service.dart uses raw `http`, not [ApiClient], for
/// multipart upload) can throw the same shape [ApiException] carries.
class RuntimeMissingException implements Exception {
  const RuntimeMissingException(this.code, this.message, {this.slot});
  final String code;
  final String message;
  final String? slot;
  @override
  String toString() => message;
}

/// Recognizes the runtime-missing shape out of anything a call site might
/// have caught — an [ApiException] from [ApiClient], or an already-decoded
/// [RuntimeMissingException]. Returns `null` for every other error so callers
/// can fall back to their generic handling unchanged.
RuntimeMissingException? runtimeMissingFrom(Object error) {
  if (error is RuntimeMissingException) return error;
  if (error is ApiException &&
      error.status == 503 &&
      error.code != null &&
      runtimeMissingCodes.contains(error.code)) {
    return RuntimeMissingException(error.code!, error.message,
        slot: error.slot);
  }
  return null;
}

/// Decodes a raw HTTP error body for the runtime-missing shape — for call
/// sites that speak to the daemon directly instead of through [ApiClient]
/// (audio_service.dart's multipart transcribe/synthesize requests).
RuntimeMissingException? decodeRuntimeMissingBody(int status, String body) {
  if (status != 503) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && runtimeMissingCodes.contains(decoded['code'])) {
      return RuntimeMissingException(
        decoded['code'] as String,
        '${decoded['error'] ?? body}',
        slot: decoded['slot'] as String?,
      );
    }
  } catch (_) {
    // Not JSON, or not this shape — let the caller's generic handling apply.
  }
  return null;
}
