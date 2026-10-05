# AGENTS.md: pumperly-ios

Instructions for coding agents working in this repository. `CLAUDE.md` imports this file.

## What this is

The iPhone app for [Pumperly](https://pumperly.com), the open-source fuel and EV route planner. It shows the web app in a native SwiftUI shell and adds a home screen widget, "Cheapest nearby". The web app lives in [GeiserX/Pumperly](https://github.com/GeiserX/Pumperly); the Android shell it mirrors is [GeiserX/Pumperly-android](https://github.com/GeiserX/Pumperly-android).

## Repository rules

- License: GPL-3.0-only, the same as the Android app.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org). Versions follow semver.
- Every change reaches `main` through a pull request with green CI. Never force push, never rewrite pushed history.
- No AI attribution anywhere: no `Co-Authored-By` trailers, no "Generated with" lines. The `commit-msg` hook in `.beads/hooks` removes such trailers.
- Never commit a secret, a signing certificate, a provisioning profile or an App Store Connect key.

## Build and test

All builds and tests run on macOS with Xcode. `project.yml` is the single source of truth (targets, settings, version, build number); the `.xcodeproj` is generated and never committed, so a change to targets or settings goes in `project.yml`.

```bash
xcodegen generate
xcodebuild test -project Pumperly.xcodeproj -scheme Pumperly \
  -destination "platform=iOS Simulator,id=$(scripts/pick-simulator.sh)" -parallel-testing-enabled NO
```

CI (`.github/workflows/ci.yml`) runs the same on `macos-latest` for every pull request and push to main, then builds the Release configuration unsigned. `release.yml` uploads to TestFlight on a `v*` tag; its secrets are listed in the README.

## Architecture

```
Pumperly/            app target (com.pumperly.app)
  Shell/             WKWebView shell: ShellModel, NavigationPolicy, ShellError, GeolocationBridge, ErrorView
  Settings/          the widget fuel screen
PumperlyWidget/      WidgetKit extension (com.pumperly.app.widget): provider and one-shot location
Shared/              compiled into both targets: AppConfig, FuelType, SharedSettings (App Group),
                     StationsAPI, TimelineMapping, widget views, strings and colours
PumperlyTests/       unit tests, with fixtures copied from the live API
PumperlyUITests/     UI tests; the shell test loads a bundled HTML page with no network
```

The Android app ([GeiserX/Pumperly-android](https://github.com/GeiserX/Pumperly-android)) is the reference for every shell behaviour. Keep them in step.

## Rules the code depends on

- Only `https` URLs on `AppConfig.allowedHosts` load in the app (`NavigationPolicy`). Everything else opens outside it; `javascript:`, `file:`, `data:` and `blob:` are cancelled. Never add a host without a reason in the PR.
- Location goes only to a top-level https pumperly.com page. The injected script denies other frames, and `GeolocationBridge` checks the frame's origin again natively. Keep both checks.
- Certificate errors are never bypassed: no `didReceive challenge` override.
- The user agent ends with `PumperlyiOS/<version>` (WebKit's `applicationNameForUserAgent`). The site may rely on it.
- The widget reads only the App Group `group.com.pumperly.app`. Coordinates are rounded to 3 decimals before they leave the device.
- Debug-only launch hooks (`PUMPERLY_UITEST_*`, `PUMPERLY_START_URL`) sit behind `#if DEBUG`; Release builds never contain them.
- Every user-facing string exists in English and Spanish (`Shared/Resources/*.lproj`, `InfoPlist.strings`); Spanish keeps its accents. A unit test checks the error and fuel strings.
- When the app starts reading or sending new data, update both `PrivacyInfo.xcprivacy` files.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:970c3bf2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

## Where the tracker syncs

This repo is public, so its tracker syncs only to the private Dolt remote named by `sync.remote` in `.beads/config.yaml`. The block above says sync uses "your git remote". Here that never means this GitHub repo. Don't add it as a Dolt remote and don't push `refs/dolt/*` to it.
