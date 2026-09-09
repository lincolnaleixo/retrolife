# Development rules

- Use English for code, documentation, UI, issues, and release notes.
- `rules.md` is the single source of development instructions. Harness entrypoints point here; never maintain duplicate rules.
- Update `CHANGELOG.md` with every modification, in the same commit. Group related work under Unreleased; do not invent released versions.
- `plan.md` is the only roadmap. Issues contain linked bounded work and evidence, not a competing roadmap.
- Keep Rust domain/emulation logic independent of Godot. Godot owns presentation, input mapping, and audio playback.
- Never commit credentials, private hostnames/paths, ROMs, saves, personal photographs, proprietary artwork, or private submodules.
- Original code is AGPL-3.0-only. Preserve all third-party notices; never relicense game artwork under the application license.
- Build only pinned dependencies. Run formatting, Clippy, tests, Godot checks, and the publication audit before merging.
- Do not execute pull-request code on the signing machine or expose signing credentials to CI.
- Immutable version tags identify releases. Fix a release by publishing a new version.
- Archive code is historical reference only: do not include it in the workspace, Godot imports, or release artifacts.
- Do not claim completion from compilation alone. Record what was exercised and any remaining platform or release blockers.
