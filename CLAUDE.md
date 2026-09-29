# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project overview

SenClaw Desktop is the Flutter console (macOS / Windows / Linux / web) for
[SenClaw](../senclaw). It supervises the `senclaw` daemon as a child process
(`lib/core/daemon/daemon_supervisor.dart`) and talks to it over HTTP/WS —
never embeds a webview, never links daemon code. `../senclaw` (daemon, Rust),
`../web-app` (React web console) and `../sen-*` (inference runtimes) are
sibling repos split out of the old monorepo; this repo owns only `lib/`,
`macos/ windows/ linux/ web/` (platform runners) and `update_desktop/` (the
small standalone Rust crate the in-app updater hands the atomic bundle swap
to — own `Cargo.lock`, own `cargo test`, never depends on the daemon).

## Build & run

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos          # dev, adopts a running daemon or spawns one
make app-build                # release bundle — needs ../senclaw checked out
```

**Run against a dev daemon, never the user's real one.** A real SenClaw daemon
listens on `18788`/`18789` with real data under `~/.senclaw` — never point a
build at it for testing, never run `make app-install` casually, never write
into `~/.senclaw` or `/Applications`. Point a manual run at a scratch daemon:

```bash
HOME=/path/to/scratch SENCLAW_UI_PORT=28788 SENCLAW_WS_PORT=28789 \
  cargo run --manifest-path ../senclaw/Cargo.toml &
flutter run -d macos --dart-define=SENCLAW_UI_PORT=28788 --dart-define=SENCLAW_WS_PORT=28789
```

Stop whatever you started; never kill a process you did not start.

## Architecture

- **State**: `flutter_riverpod`. A screen's data comes from a `FutureProvider`
  (or `.family`) reading `apiClientProvider`; a mutation goes through the same
  `ApiClient` and then `ref.invalidate(...)`s the provider. Long-lived local
  state (poll timers, pending-action maps) lives in a `ConsumerStatefulWidget`'s
  `State`, not in a provider — see `runtime_section.dart` /
  `local_models_section.dart` / `decision_section.dart` for the pattern
  (a `Timer.periodic` that starts only while something is actually
  active/downloading, cancelled in `dispose`).
- **Routing**: `go_router` (`lib/app/router.dart`). Settings is one route
  (`/settings`); which section shows is `settingsSectionProvider`
  (`StateProvider<String>`), not part of the URL — `lib/app/shell.dart`'s
  `openUpdatesPage` / `openRuntimeSettings` are the pattern for "land on a
  specific settings section from anywhere" (set the provider, then
  `context.go('/settings')`).
  Never invent a third way to reach a settings section.
- **Transport**: `lib/core/transport/api_client.dart` — the single seam
  between direct-localhost (desktop) and a future relay-backed client
  (`ApiException` carries `status`/`message`/`code`/`slot`, the last two from
  the daemon's `{"error","code"?,"slot"?}` shape). Widget tests fake it with
  `class _FakeApi implements ApiClient { ... }` and
  `apiClientProvider.overrideWithValue(api)` — see any `test/*_section_test.dart`
  for the shape (a fake that switches on path and records calls in a list).
- **Feature folders**: `lib/features/<area>/`. Settings sections split one
  file per concern (`decision_*.dart`, `runtime_*.dart`,
  `local_models_section.dart`) rather than growing `settings_screen.dart`
  further — it is already large; add new sections as new files and register
  them in its `_sections` list + `switch`.

## Runtimes: the daemon links no inference code

GGUF/MLX chat, OCR, Speech-to-text, Text-to-speech, Decision (Laya) and the
browser engine's Chrome driver (`sen-browser`, slot `browser`) all run as
separate programs the daemon installs and launches — contract in
[`../senclaw/docs/runtime-protocol.md`](../senclaw/docs/runtime-protocol.md).
Settings → **Runtime** (`runtime_section.dart`, `runtime_catalog.dart`) and
Settings → **Local models** (`local_models_section.dart`) are this app's
clients of that contract; do not add a third place that manages engines or
model files. Settings → **Browser** (`browser_section.dart`) configures the
browser engine itself (settings, the Chrome extension's pairing, actions a task
paused on for the person — Approve/Decline) and links to Runtime for the
engine's package; it never installs anything.

**Runtime-missing is a first-class UI state, not an error to swallow.** A 503
with `code` `runtime_not_installed` / `runtime_not_selected` /
`runtime_start_failed` is the daemon's normal answer for "nothing serves this
yet" — every legacy `/api/ocr|tts|whisper|decision/*` route and the local-model
proxy can return it. Detect it with `runtimeMissingFrom(error)`
(`lib/core/transport/runtime_missing.dart`) and show
`RuntimeMissingBanner`/`showRuntimeMissingSnack`
(`lib/widgets/runtime_missing_banner.dart`), never a generic error dump — both
land the user on Settings → Runtime via `openRuntimeSettings`. `AudioService`
(`lib/features/chat/audio_service.dart`) exposes the same detection for TTS
through a `ValueNotifier<RuntimeMissingException?> runtimeMissing` because its
`_synthesize` deliberately never throws (one bad sentence must not kill the
whole read-aloud) — read that notifier rather than adding a second failure
path.

Rules:

- **Never guess a slot's engine list from the platform.** Render exactly what
  `GET /api/runtimes` `slots[].candidates` says; a stale `selected` whose
  package was uninstalled still needs a visible row (see `_SlotRow`'s
  candidate-list patch — `DropdownButton` throws if `value` matches no item).
- **The "Engines & Frameworks" list is the catalog merged with `installed`,
  not the catalog alone.** A `source: "local"` sideload (`install-local`) may
  have no entry in the index at all; `CatalogEntry.fromInstalled` synthesizes
  one so it still shows up.
- **`local-models` settings round-trip the shared engine settings.json
  untouched.** It is snake_case and shared with the runtimes (same rule as the
  daemon's own `local_model_core::settings::Settings`) — a form must send back
  every key it didn't render a control for exactly as received
  (`LocalModelsSettingsCard._engineRest`), never re-key or drop it.

## Chat attachments and long-running work

- **Image long edge caps at `kMaxImageEdge` (1568px,
  `lib/features/chat/image_attachment.dart`)** before upload — matches the
  Anthropic API's own resize and keeps a phone photo under the per-image
  request limit; a decode failure passes the original bytes through rather
  than dropping the attachment.
- **Documents cap at `kMaxDocBytes` (32 MB, same file)** — matches the
  daemon's `MAX_DOC_BYTES` (`src/agent/documents.rs` in `../senclaw`). Keep
  both caps in sync if the daemon's ever changes.
- **`WatchStrip` (`lib/features/chat/watch_strip.dart`)** is the only UI for a
  chat's in-flight `schedule_watch`es — polled (`GET /api/watches?chatJid=`,
  15s), never pushed; a watch is silent by design (each check costs no
  tokens), so this is the only way a user tells "waiting" from "forgotten" and
  the only Stop button. Do not build a second watch UI.
- **`InlineDispatchCard` (`lib/features/chat/widgets/message_widgets.dart`)**
  renders a DAG's goal/status/per-task state inline in chat and carries the
  retry buttons (`POST /api/dispatch/parents/:id/retry`,
  `.../tasks/:id/retry`) — the only path back to a failed DAG or task from the
  UI. A retry refusal (400 body) is shown verbatim; do not replace it with a
  generic "retry failed".

## i18n

Every user-facing string ships in English (the lookup key) and Vietnamese.
Pattern and what must never be wrapped (ids, URLs, prompts sent to agents,
user content):
[`../senclaw/docs/desktop-i18n.md`](../senclaw/docs/desktop-i18n.md).
In short:

```dart
Text(context.tr('Add channel'))
Text(context.trArgs('Version {v}', {'v': svc.version}))
```

Vietnamese lives in one `const Map<String, String>` per feature area under
`lib/core/i18n/vi/`, merged in `lib/core/i18n/l10n.dart`. Before adding a key,
grep `lib/core/i18n/vi/*.dart` for it first — the map is flat and global, so a
key already defined elsewhere (`'Save'`, `'Loaded'`, `'Local models'`, …) must
not be redefined with a different value in a new file; the last spread in
`l10n.dart` silently wins and every other screen using that key inherits it.
A label whose exact text comes from the daemon at runtime (a runtime's own
`slots[].label`) is passed through `context.tr()` for consistency but
deliberately gets no fabricated Vietnamese entry — the daemon's contract, not
this app, owns that string. `test/vietnamese_layout_test.dart` catches sidebar
overflow from longer Vietnamese labels, but only with a **real font loaded**
(`_loadRealFont` in that file) — `flutter_test`'s default glyph-box renderer
reports phantom overflow otherwise; copy that helper into any new test that
pumps the full `SettingsScreen`.

## Testing

`flutter test` — widget tests fake the daemon with an in-memory `ApiClient`
(see Transport above); no test should reach a real daemon. Overflow-sensitive
screens (Settings sidebar, dashboard) get an explicit "does not overflow"
assertion (`tester.takeException()` is `null`) since Flutter otherwise only
prints the overflow banner without failing the test.
