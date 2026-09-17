# Executing the plan

This guide turns [plan.md](../plan.md) into an execution procedure for a development agent ("the executor"). The plan stays the single roadmap; this document explains how to make progress on it safely and how to report evidence honestly.

## 1. Check the environment before starting

The executor needs, before touching the repository:

- An authenticated clone of `github.com/lincolnaleixo/retrolife` (working DNS and HTTPS to github.com).
- GitHub write access able to push branches and open or manage pull requests; the `gh` CLI with repository workflow is the expected path.
- The pinned Rust toolchain from `rust-toolchain.toml`, `Cargo.lock`, a native C/C++ toolchain (Xcode Command Line Tools on macOS), Python 3 and `git`.
- Godot 4.7.2 available as `godot` or through `GODOT=...`, with matching export templates when export or packaging work is involved.
- An Apple Silicon Mac for native packaging checks. Production signing happens only inside the protected `macos-release` environment; no executor ever handles signing credentials in a pull request.

If the environment cannot clone, build, run `scripts/check.sh` and open pull requests, **stop and report that immediately**. A read-only GitHub integration or an offline terminal cannot execute this plan. Do not apply patches by hand, do not claim files were changed when they were not, and do not mark any milestone or deliverable as done from inspection alone.

## 2. Hard guardrails

- **There are exactly two branches by design.** `main` is protected and receives changes only through pull requests. `updates` is the published Sparkle update feed (`appcast.xml`) served to already-installed applications; the release pipeline maintains it automatically. Never delete, rewrite, force-push or merge `updates` into `main`. Deleting it breaks in-app updates for every installed build. If an instruction says "keep only main", that instruction is wrong about this repository.
- Never push directly to `main`; the required `validate` check, linear history and conversation resolution are enforced.
- Never commit ROMs, saves, proprietary game artwork, credentials, private paths or personal data. The publication audit and secret scan run on every pull request.
- Use English for code, documentation, commits, UI and release notes.
- Update `CHANGELOG.md` in the same commit as every change.
- CI green is not product acceptance. Owner gates in section 5 stay unchecked until the owner records real results.
- Keep pinned dependencies pinned. Never weaken signing, updater verification, privacy rules or rights boundaries to make a check pass.

## 3. The standard loop

1. Pick the next unchecked deliverable in the current milestone of [plan.md](../plan.md). Work in milestone order (v0.2, then v0.3, and so on); the remaining v0.1.0 work is owner-side acceptance.
2. Create a small issue (or reuse a milestone issue) with the deliverable checklist so progress is visible.
3. Branch from updated `main` (`feat/...`, `fix/...`, `docs/...`) and implement one bounded deliverable.
4. Run `scripts/check.sh` locally, or the subset that applies, and add focused tests with the change.
5. Update `CHANGELOG.md` under `Unreleased` in the same commit.
6. Open a pull request against `main`, resolve review comments and wait for the required `validate` check to pass.
7. Squash-merge (auto-merge when enabled). The merge triggers the automatic beta release workflow, which builds, signs, notarizes and publishes the next beta and updates the appcast.
8. Verify the release run and the feed entry for the new beta, then check off the deliverable in `plan.md` with a link to its evidence in the same or a follow-up pull request.

Every merged change must keep `main` releasable: the automatic pipeline publishes a beta on every push to `main`.

## 4. Verification commands

| Command | Covers |
| --- | --- |
| `scripts/check.sh` | Formatting, Clippy, Rust tests, publication and dependency audits, asset tests, updater contracts, bridge build, Godot import and headless smokes |
| `scripts/build-core.sh` and `scripts/test-core.sh` | Pinned bsnes-jg core build and real-core integration |
| `python3 scripts/test-updates.py` | Release and update publication contracts |
| `python3 scripts/test-release-automation.py` | Versioning and release-pipeline contracts |
| `python3 scripts/test-cartridge-assets.py` | Cartridge asset staging and validation |
| `python3 scripts/test-release-packaging.py` | Disposable exported-app packaging regression |
| `python3 scripts/test-updater-native.py` | Real Sparkle upgrade and security scenarios on Apple Silicon |
| CI jobs (`validate`, `native-macos`, `cartridge-ui`, `updater-*`, `release-package`) | The same checks on GitHub runners; the required one is `validate` |

## 5. Division of labor: what only the owner can do

These gates require the owner's hardware, accounts and judgment. Prepare everything, remind clearly, and leave them unchecked until real results are recorded:

- Hands-on gameplay, audible audio, physical controllers and a sustained session on the target Mac.
- Battery-save restoration with real user games.
- Owner visual approval of the library, cartridge presentation and labels.
- Signed-to-signed in-app update verification and Gatekeeper checks on installed builds.
- The final release decision.

Record results in the acceptance issue (currently [issue #1](https://github.com/lincolnaleixo/retrolife/issues/1)) and update `plan.md` status lines only from real runs. "Compilation passes" is never acceptance.

## 6. Recommended first tasks

The owner's most recent review of the installed beta drives the first work:

1. v0.2 — 2K-class default window. `frontend/godot-ui/project.godot` currently opens at 1280x720 with a 720x540 minimum; raise the default and the floor to the plan's targets, keep the smokes passing and add window checks.
2. v0.2 — macOS menu-bar and shortcut parity plus appearance handling. The application menu currently contains only the updater item.
3. v0.3 — cartridge idle motion and free inspection, then the close-up and 2K visual evidence.
4. v0.3 — the label path: local override first, then the prepared Super Mario World package through the collection's catalog and manifest, under the rights and privacy rules in `plan.md`.
5. Continue through the remaining v0.2 and v0.3 deliverables, then later milestones in order.

## 7. When blocked

Report precisely: what was attempted, the exact command and error, what the environment lacks, and which decision is needed. Do not invent results and do not silently skip tests. If a deliverable depends on owner hardware, mark it blocked in its issue and continue with the next independent deliverable.
