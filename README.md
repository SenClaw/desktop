# SenClaw Desktop

Native **Flutter** desktop app for SenClaw (macOS / Windows / Linux / web).
Talks to the daemon directly over HTTP/WebSocket and **supervises the
`senclaw` daemon as a child process** — spawns the bundled binary from
`Contents/Resources/senclaw`, streams its logs, and restarts it on demand
(see `lib/core/daemon/daemon_supervisor.dart`).

This repo is one of several siblings split out of the old SenClaw monorepo:
`../senclaw` (the daemon, Rust), `../web-app` (the React web console served by
the daemon), `../sen-mlx` `../sen-ocr` `../sen-sysone` `../sen-tts`
`../sen-whisper` (inference **runtimes** — see below). Building a full desktop
bundle needs `../senclaw` checked out next to this repo; day-to-day Flutter
work (`flutter run`, `flutter test`) does not.

On launch a **startup gate** (`lib/core/daemon/startup_gate.dart`) decides the
path: a daemon already listening on the UI port is adopted and the main UI
opens immediately; otherwise the app spawns the bundled daemon, shows a
"Starting daemon" screen until the HTTP API answers, then switches to the
main screen. Failures land on a retryable error screen with the daemon log
tail.

## Runtimes: the daemon links no inference code

GGUF/MLX chat, OCR, Speech-to-text, Text-to-speech and Decision (Laya) each run
as a separate program the daemon installs and launches as a child process —
the way LM Studio runs its engines. The contract is
[`senclaw/docs/runtime-protocol.md`](../senclaw/docs/runtime-protocol.md); this
app is one of its clients. Two screens under **Settings**:

- **Runtime** (`lib/features/settings/runtime_section.dart`,
  `runtime_catalog.dart`) — LM Studio-style: one selection per slot (GGUF, MLX,
  Decision, OCR, Speech to text, Text to speech), the update channel, an
  "Engines & Frameworks" browser (install/update/uninstall, install from a
  local folder or archive, view logs, stop a runtime's processes), and the
  live process list.
- **Local models** (`lib/features/settings/local_models_section.dart`) — the
  GGUF/MLX model files themselves: download from a Hugging Face repo,
  load/unload/delete, default engine settings (context length, temperature,
  top_k/top_p, …).

**Runtime-missing state**: OCR, TTS, Whisper and Decision (Laya) settings, plus
voice input/output, show a dedicated banner/snack
(`lib/widgets/runtime_missing_banner.dart`) instead of a raw error when the
daemon 503s a request because no runtime backs that slot yet — with a button
straight to Settings → Runtime. Detection lives in
`lib/core/transport/runtime_missing.dart`.

## Build & run

```bash
# Development (adopts a running daemon or spawns one)
make app-dev

# Production bundle: builds the daemon from ../senclaw (no inference code, so
# no feature flags) and bundles it into the .app (an Xcode build phase also
# re-embeds the freshest ../senclaw/target/release/senclaw on every
# `flutter build macos`)
make app-build

# Install into /Applications and launch (macOS) — NEVER run this against a
# machine whose real SenClaw install/data you care about; see the Makefile.
make app-install
```

Other targets: `make signing-cert` (one-time stable codesigning identity so
TCC grants survive reinstalls), `make app-build-windows` /
`make app-build-linux`, `make app-build-web` (the Flutter web target of this
console — unrelated to `../web-app`), `make app-clean-cache`. All of them
optionally bundle any packaged runtimes found under `../sen-*/dist/` into the
app's `runtimes/` resource directory, which the daemon scans as a second,
read-only install root.

Direct Flutter commands work too (`flutter run -d macos`,
`flutter build macos --release`).

## Layout

- `lib/core/` — daemon supervisor + startup gate, HTTP/WS transport
  (`transport/api_client.dart`, `transport/runtime_missing.dart`), config, i18n
- `lib/features/` — chat, dashboard, plugins, space, cowork, settings
  (including `runtime_section.dart`, `runtime_catalog.dart`,
  `local_models_section.dart`), cognitive memory, diagnostics, dock
  (terminal / files / todos)
- `lib/app/` — shell, router, tray + window management
- `lib/widgets/` — shared widgets, including the runtime-missing banner
- `macos/ windows/ linux/ web/` — platform runners
- `update_desktop/` — the small standalone Rust crate the in-app updater hands
  the atomic bundle swap to (its own `cargo test`, own target dir)

Ports default to `18788` (HTTP) / `18789` (WS); override with
`--dart-define=SENCLAW_UI_PORT=...` (see `lib/core/config/app_config.dart`).

## i18n

Every UI string ships in English and Vietnamese — see
[`docs/desktop-i18n.md`](../senclaw/docs/desktop-i18n.md) in the daemon repo
for the pattern (`context.tr('English string')`, Vietnamese maps under
`lib/core/i18n/vi/`, merged in `lib/core/i18n/l10n.dart`) and what must never
be wrapped (ids, URLs, prompts sent to agents, user content).
