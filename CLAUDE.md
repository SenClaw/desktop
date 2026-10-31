# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project overview

SenClaw Desktop is the Flutter console (macOS / Windows / Linux / web) for
[SenClaw](../senclaw). It supervises the `senclaw` daemon as a child process
(`lib/core/daemon/daemon_supervisor.dart`) and talks to it over HTTP/WS —
never links daemon code. It embeds a WKWebView/WebView2 on macOS & Windows
(`flutter_inappwebview`) for the Browser pane, Space Apps and widgets; Linux
has no embedded webview and falls back to an "open in browser" card.
`../senclaw` (daemon, Rust),
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

## Launch at login

`lib/core/startup/` is the only place that registers the app with the OS
(`LaunchAtLogin`: macOS `SMAppService.mainApp` through the `senclaw/app`
channel in `AppDelegate.swift`, Windows `HKCU\...\Run` via `win32_registry`,
Linux `~/.config/autostart`). Settings → General → Startup
(`LaunchAtLoginField`) is its only UI.

- **A login start must show no window.** Windows/Linux entries carry
  `--autostart` (`kAutostartArg`); a macOS login item cannot carry arguments,
  so `AppDelegate.detectLaunchedAtLogin` reads the launch Apple event (it also
  honours `--autostart`, which is how to test: `open -n X.app --args
  --autostart`). `launchedAtLogin()` (`launch_origin.dart`) turns either into
  `startedHiddenProvider`; `main.dart` then skips `show()` and `app.dart`
  starts with `_mainShown = false`. The native runners keep the window hidden
  for that launch (macOS `MainFlutterWindow.order`, Windows
  `FlutterWindow::OnCreate`, Linux `first_frame_cb`) — change one, change all.
- **macOS 13 is the floor** (`SMAppService`); older systems report
  `unsupported` and the row is hidden. `requiresApproval` means the user
  switched the item off in System Settings — only they can switch it back on,
  so the UI links there instead of retrying.
- `win32_registry` is `dart:ffi`: it is imported only through
  `launch_at_login_windows_stub.dart`'s conditional import so the web build
  still compiles.
- Never register a test build as a login item on the user's machine; tests use
  a fake `LaunchAtLogin` (`launchAtLoginProvider.overrideWithValue`).

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
- **Background processes (`lib/features/background/bg_processes.dart`)** are what an agent
  left running — a dev server — as `GET /api/bg-tasks` reports them: `BgProcessStrip` above
  the composer (this chat's, with Stop / Log / port chips), `BgProcessesPanel` at the top of
  the Background screen (every chat's), a badge on the Background nav-rail item
  (`bgRunningCountProvider`). One `bgProcessesProvider` polls every 3 s for all three. They
  are not the scheduled tasks of `BackgroundScreen`. A test that mounts `AppShell` must
  override `bgProcessesProvider` (the rail watches it), as `projects_layout_test.dart` does.
- **Browser pane (`lib/features/browser/`)** hosts the open internet, so three things are not to be undone.
  Every URL it loads or hands to the OS goes through `browserUrlFrom` / `openWebUrlExternally`
  (`lib/widgets/browser_url.dart`): http and https only, because a popup reaches `NSWorkspace.open` /
  `ShellExecuteW` and would otherwise start `ms-msdt:` or `smb:` handlers. `onCreateWindow` answers
  `true`: false has the plugin load the request in the pane. `embeddedWebView` shares that rule (plus
  `mailto:` and `tel:`, through `openLinkExternally`), because it hosts remote video pages from model
  replies. And no loopback page opens by itself (`isLoopbackUrl`): one passes the daemon's local-Origin
  check and can read provider keys, so a dev server opens from a click on its chip and a `web` artifact
  from the header's Open, while a remote artifact still shows at once. `DockTabBody` keeps the Terminal mounted across tab changes, because
  unmounting it closes the socket and the daemon kills the shell.
- **File pane (`lib/features/file_pane/`)** is what a file row of a `ToolGroupCard` opens: the
  file beside the chat, read through `GET /api/workspace/file` (the daemon route the dock's Files
  tab uses; 512 KB cap). `FilePaneSplit` positions the chat instead of reparenting it, so a
  half-typed message survives the pane opening, expanding and covering it in a narrow window. The
  pane and `RightDock` share the room beside the chat: an open file hides the dock with
  `Visibility(maintainState)` (its Terminal tab is a live shell), and the dock toggle swaps them.
  State is per chat and in memory (`filePaneProvider`). Two things not to undo:
  `parseMarkdown` cuts long sections because `gpt_markdown` froze the UI for a minute on 256 KB
  of one section (3 s on 512 KB cut up, debug build; a section it cannot cut opens as text), and
  search in the rendered view reads the laid-out `RenderParagraph`s and paints over them, because
  the package has no way to style a run of plain text. The mini window has no pane
  (`subWindowIdProvider`), so its rows open their detail as before.
- **`InlineDispatchCard` (`lib/features/chat/widgets/message_widgets.dart`)**
  renders a DAG's goal/status/per-task state inline in chat and carries the
  retry buttons (`POST /api/dispatch/parents/:id/retry`,
  `.../tasks/:id/retry`) — the only path back to a failed DAG or task from the
  UI. A retry refusal (400 body) is shown verbatim; do not replace it with a
  generic "retry failed".

## Projects

A project is a folder root that sessions and kanban boards work in, with a
context and facts of its own (`lib/features/projects/`, client of
`/api/projects*`, specified in `../senclaw/docs/openapi-daemon.yaml`).

- **A session is put in a project when it is created, and never moved.**
  `GroupsNotifier.createChat(projectId:)` puts it on `register:group`; the
  daemon refuses `update:group` that changes or drops it. So there is no "move
  to project" menu, and New Session locks the folder to the project's root
  (`_FolderPill` with `onTap: null`). Only chat and code sessions can join —
  cowork, schedule and workflow never get the picker. A refused registration
  comes back as a WS `error` (`registerRefusalProvider`) and `ChatScreen` goes
  back to the form.
- **No push event for projects.** Screens refresh after this window's own
  action and when the window gets focus back (`projectsFocusRefreshProvider`,
  watched by `ProjectsScreen` and `SessionList`); a second window's edit shows
  at the next refresh.
- **A context write that lost a race is a 409 with the current text.**
  `ApiException.body` carries the decoded error body; the Context tab shows the
  daemon's copy beside the edit and the person picks. Never retry the PUT
  silently with the new version.
- **Deleting a project outright is slow** (a 20 000-fact bank took ~23 s).
  `ProjectsApi.purge` runs inside `ApiClient.withTimeout(kProjectPurgeTimeout)`,
  a zone value on purpose: every test fake `implements ApiClient`, so a new
  named parameter on `delete` would break all of them. A timeout there is not a
  failure — the daemon carries on; the dialog says so and the screens reload.
- **The session list has two grouping axes that sound alike.** `GroupMode.agent`
  buckets by the agent's folder (stored as `'project'`, what that axis was
  called before projects existed — installs have it), `GroupMode.project` by
  the real project (`'projects'`), the sessions with none last.
- **A project's facts are the bank `project:<id>`**, listed in Knowledge →
  Facts by the project's name (`bankLabel`) and managed in the project's own
  Facts tab (`FactRow` is shared). Personal facts said in a project chat stay in
  that bank for now; the tab says so.
- Vietnamese is `lib/core/i18n/vi/projects.dart`; `test/projects_i18n_test.dart`
  fails on any string of `lib/features/projects/` without an entry, and
  `test/projects_layout_test.dart` renders the screens, the shell rail and the
  session list in both languages with a real font.

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
