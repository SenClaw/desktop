# ===== Desktop app packaging =====
# This Flutter project (desktop/) SUPERVISES the senclaw daemon as a child
# process (spawns the bundled `senclaw` binary, streams its logs, restarts it
# on demand — lib/core/daemon/daemon_supervisor.dart). Unlike the old monorepo
# Makefile this one lived in, senclaw/ and web-app/ are now SIBLING repos
# (../senclaw, ../web-app — see the umbrella layout in the migration plan),
# so every daemon build below runs against ../senclaw's own Cargo workspace.
#
# The daemon links no inference code (runtime-protocol.md): GGUF/MLX/OCR/TTS/
# Whisper/Decision all run as separate runtimes the daemon installs and
# launches itself, so there is no DAEMON_FEATURES list to keep in sync here —
# a plain `cargo build --release --bin senclaw` is the whole daemon.
SENCLAW_DIR := ../senclaw
WEB_APP_DIR := ../web-app

.PHONY: app-dev app-build app-install signing-cert app-build-windows app-build-linux app-build-web app-clean-cache

app-dev:
	flutter run -d macos

# Build the release .app and bundle the daemon binary into its Resources, so
# the supervisor finds it at Contents/Resources/senclaw. The Xcode "Embed
# senclaw daemon" build phase (macos/Runner.xcodeproj) also re-copies the
# freshest ../senclaw/target/release/senclaw on every `flutter build macos` —
# this target exists for a from-scratch build and for re-signing afterward.
app-build:
	cd $(SENCLAW_DIR) && cargo build --release --bin senclaw
	flutter build macos --release
	cp $(SENCLAW_DIR)/target/release/senclaw \
	    "build/macos/Build/Products/Release/SenClaw Desktop.app/Contents/Resources/senclaw"
	@$(MAKE) --no-print-directory _bundle-runtimes-macos
	@echo "[app-build] bundled daemon into 'SenClaw Desktop.app/Contents/Resources/senclaw'"
	@# Re-sign the modified bundle. With the stable "SenClaw Dev" identity
	@# (create once via `make signing-cert`) the signature stays constant, so
	@# TCC grants (Screen Recording…) survive reinstalls instead of silently
	@# breaking every `make app-install`.
	scripts/macos_sign_app.sh "build/macos/Build/Products/Release/SenClaw Desktop.app"

# One-time: create + trust the stable self-signed "SenClaw Dev" codesigning
# certificate so app-build stops using ad-hoc signatures.
signing-cert:
	scripts/macos_make_signing_cert.sh

# Install the freshly-built .app into /Applications and launch it.
#
# NEVER run this against a machine whose real SenClaw daemon/data you care
# about without checking first — it replaces /Applications/SenClaw Desktop.app
# outright and kills whatever is holding port 18788.
app-install:
	@test -d "build/macos/Build/Products/Release/SenClaw Desktop.app" \
	    || (echo "no .app — run 'make app-build' first" && exit 1)
	@pkill -f "SenClaw Desktop.app/Contents/MacOS/SenClaw Desktop" 2>/dev/null || true
	@# The daemon is a CHILD of the app, not the app — killing only the app
	@# orphans it, and it keeps holding port 18788. The freshly installed app
	@# then finds a healthy port, adopts the orphan, and runs the OLD binary:
	@# the install looks like it worked and silently changes nothing.
	@pkill -f "SenClaw Desktop.app/Contents/Resources/senclaw" 2>/dev/null || true
	@sleep 2
	@lsof -nP -iTCP:18788 -sTCP:LISTEN >/dev/null 2>&1 \
	    && echo "[app-install] WARNING: something still holds port 18788 — the new app may adopt it" \
	    || true
	rm -rf "/Applications/SenClaw Desktop.app"
	cp -R "build/macos/Build/Products/Release/SenClaw Desktop.app" "/Applications/SenClaw Desktop.app"
	open "/Applications/SenClaw Desktop.app"

# Windows / Linux desktop builds (run on the matching host).
# Both bundle the release `senclaw` binary ALONGSIDE the app executable, which
# is the first path the supervisor's _resolveBinary() checks (exeDir/senclaw
# [.exe]), so the packaged app self-hosts the daemon with no SENCLAW_BIN
# needed. No MLX/Metal features exist on the daemon side at all anymore, so
# these need no feature flags either.
app-build-windows:
	cd $(SENCLAW_DIR) && cargo build --release --bin senclaw
	flutter build windows --release
	@dir=$$(ls -d build/windows/*/runner/Release 2>/dev/null | head -1); \
	    test -n "$$dir" || (echo "no flutter windows Release dir" && exit 1); \
	    cp $(SENCLAW_DIR)/target/release/senclaw.exe "$$dir/senclaw.exe"; \
	    echo "[app-build-windows] bundled daemon into $$dir/senclaw.exe"
	@$(MAKE) --no-print-directory _bundle-runtimes-windows

app-build-linux:
	cd $(SENCLAW_DIR) && cargo build --release --bin senclaw
	flutter build linux --release
	@dir=$$(ls -d build/linux/*/release/bundle 2>/dev/null | head -1); \
	    test -n "$$dir" || (echo "no flutter linux bundle dir" && exit 1); \
	    cp $(SENCLAW_DIR)/target/release/senclaw "$$dir/senclaw"; \
	    echo "[app-build-linux] bundled daemon into $$dir/senclaw"
	@$(MAKE) --no-print-directory _bundle-runtimes-linux

# Web build of the Flutter console itself (served by the daemon's static dir,
# or any static host) — NOT the React web-app (../web-app), which is a
# separate CI job (.github/workflows/desktop.yml) with its own dist artifact.
app-build-web:
	flutter build web --release

app-clean-cache:
	@echo "[clean] removing target/debug and incremental caches"
	@rm -rf $(SENCLAW_DIR)/target/debug $(SENCLAW_DIR)/target/release/incremental \
	    $(SENCLAW_DIR)/target/release/build/*-*/incremental 2>/dev/null || true
	@du -sh $(SENCLAW_DIR)/target 2>/dev/null || true

# ===== Bundled runtimes (optional) =====
# The daemon scans <exe_dir>/runtimes for bundled packages — one directory per
# `<id>/<version>/senclaw-runtime.json`, exactly its own install layout (a
# second, read-only root alongside the user's ~/.senclaw/runtimes — see
# runtime-protocol.md §2.1/§2.3). Bundling here is opt-in and best-effort: it
# only extracts what a sibling `sen-*` repo has already built with
# `make package` (producing sen-*/dist/*.tar.gz or *.zip), reading the id and
# version out of each archive's own manifest rather than guessing from its
# filename. A repo not present or not yet packaged is silently skipped, never
# a build failure. Needs `jq` (already a build-time dependency of the old
# desktop CI's release-manifest step).
_bundle-runtimes-macos:
	@dst="build/macos/Build/Products/Release/SenClaw Desktop.app/Contents/Resources/runtimes"; \
	    $(MAKE) --no-print-directory _extract-runtime-dists DST="$$dst"

_bundle-runtimes-windows:
	@dir=$$(ls -d build/windows/*/runner/Release 2>/dev/null | head -1); \
	    test -n "$$dir" || exit 0; \
	    $(MAKE) --no-print-directory _extract-runtime-dists DST="$$dir/runtimes"

_bundle-runtimes-linux:
	@dir=$$(ls -d build/linux/*/release/bundle 2>/dev/null | head -1); \
	    test -n "$$dir" || exit 0; \
	    $(MAKE) --no-print-directory _extract-runtime-dists DST="$$dir/runtimes"

# DST is passed in by the three targets above.
_extract-runtime-dists:
	@test -n "$(DST)" || (echo "_extract-runtime-dists: DST not set" && exit 1)
	@found=0; \
	    for dist in ../sen-*/dist; do \
	        [ -d "$$dist" ] || continue; \
	        for f in "$$dist"/*.tar.gz "$$dist"/*.zip; do \
	            [ -f "$$f" ] || continue; \
	            tmp=$$(mktemp -d); \
	            case "$$f" in \
	                *.tar.gz) tar -xzf "$$f" -C "$$tmp" ;; \
	                *.zip) unzip -q "$$f" -d "$$tmp" ;; \
	            esac; \
	            manifest=$$(find "$$tmp" -maxdepth 2 -name senclaw-runtime.json | head -1); \
	            if [ -z "$$manifest" ]; then \
	                echo "[bundle-runtimes] WARNING: $$f has no senclaw-runtime.json at its top level — skipping"; \
	                rm -rf "$$tmp"; continue; \
	            fi; \
	            pkgdir=$$(dirname "$$manifest"); \
	            id=$$(jq -r .id "$$manifest"); \
	            version=$$(jq -r .version "$$manifest"); \
	            mkdir -p "$(DST)/$$id"; \
	            rm -rf "$(DST)/$$id/$$version"; \
	            cp -R "$$pkgdir" "$(DST)/$$id/$$version"; \
	            echo "[bundle-runtimes] bundled $$id $$version from $$f"; \
	            rm -rf "$$tmp"; \
	            found=1; \
	        done; \
	    done; \
	    [ "$$found" = 1 ] || echo "[bundle-runtimes] no ../sen-*/dist archives found — skipping (not an error)"
