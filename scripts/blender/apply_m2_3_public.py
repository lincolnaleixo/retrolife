#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ASSET_ID = "retrolife.snes.ntsc-u.cartridge.m2.3.blender.v1"


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def append_once(path: Path, marker: str, content: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker not in text:
        path.write_text(text.rstrip() + "\n\n" + content.strip() + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--source-license", required=True)
    parser.add_argument("--source-filename", required=True)
    args = parser.parse_args()
    stage = args.stage.resolve()
    work = args.work.resolve()
    source = args.source.resolve()

    for path in [work / ".codex-blender-source", work / ".codex-payload"]:
        shutil.rmtree(path, ignore_errors=True)
    for path in (work / ".github/workflows").glob("codex-*.yml"):
        path.unlink()

    blender_dir = work / "scripts/blender"
    blender_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(stage / "scripts/blender/build_m2_3_reference_review.py", blender_dir / "build_m2_3_cartridge.py")
    shutil.copyfile(stage / "scripts/blender/finalize_m2_3_package.py", blender_dir / "finalize_m2_3_package.py")
    shutil.copyfile(stage / "scripts/verify-m2-3-blender-cartridge.py", work / "scripts/verify-m2-3-blender-cartridge.py")

    source_dir = work / "frontend/godot-ui/assets/snes/m2_3/source"
    source_dir.mkdir(parents=True, exist_ok=True)
    target_source = source_dir / ("snes_ntsc_reference" + source.suffix.lower())
    shutil.copyfile(source, target_source)
    write(source_dir / "LICENSE.md", f"""# Third-party source license

The source mesh in this directory is used under **{args.source_license}** as declared by its public source page.

The original license and attribution remain in force. RetroLife does not relicense the third-party source mesh as CC0.
""")
    write(source_dir / "PROVENANCE.md", f"""# Public source provenance

- Work: **Super Nintendo Cartridge NTSC reference model**
- Creator: **neebick**
- Public source: https://www.thingiverse.com/thing:6364945
- Source license: **{args.source_license}**
- Original source filename: `{args.source_filename}`

The public headless Blender pipeline imports the source mesh, removes duplicate vertices, recalculates normals, maps the principal axes and normalizes the review envelope to 136 x 88 x 20 mm. It adds an original neutral RetroLife label placeholder, exports a Godot-ready GLB and creates review renders.

No commercial game label, ROM, BIOS, save, private repository file, device configuration, deployment infrastructure or internal workflow is included.

Physical caliper calibration and explicit owner visual approval remain open.
""")
    write(work / "frontend/godot-ui/assets/snes/m2_3/README.md", """# M2.3 Blender cartridge review asset

This directory contains a provisional NTSC-U/C cartridge review package generated headlessly with Blender.

- `source/`: attributed public reference mesh and its original license boundary
- `snes_ntsc_u_cartridge_m2_3.blend`: authored Blender scene
- `snes_ntsc_u_cartridge_m2_3.glb`: Godot-ready runtime asset

The source mesh is not relicensed by RetroLife. Review label artwork is original and deliberately generic. Physical calibration and final visual approval remain open.
""")

    write(work / "frontend/design/m2-3-snes-blender-cartridge.md", """# M2.3 Blender NTSC-U/C cartridge review package

## Decision

Earlier procedural and CAD attempts did not reach an acceptable physical likeness. M2.3 therefore moves the review asset to a headless Blender pipeline based on an attributed public NTSC-U/C reference model instead of continuing to guess the shell from flat diagrams.

The public source is **Super Nintendo Cartridge NTSC reference model** by **neebick**, published at Thingiverse thing 6364945 under the license recorded in `frontend/godot-ui/assets/snes/m2_3/source/LICENSE.md`.

The source license remains attached to the source and transformed mesh. RetroLife does not claim CC0 ownership over that third-party geometry.

## Headless build

```bash
blender --background --factory-startup \
  --python scripts/blender/build_m2_3_cartridge.py -- \
  --root "$PWD" \
  --source "$PWD/frontend/godot-ui/assets/snes/m2_3/source/snes_ntsc_reference.stl"
python3 scripts/blender/finalize_m2_3_package.py \
  --root "$PWD" \
  --source "$PWD/frontend/godot-ui/assets/snes/m2_3/source/snes_ntsc_reference.stl" \
  --source-license "CC BY"
python3 scripts/verify-m2-3-blender-cartridge.py
```

The GitHub workflow pins Blender 5.2.1 and verifies the official release checksum before executing the same headless build under Xvfb.

## Generated package

- authored `.blend` scene
- Godot-ready GLB
- eight orthographic and perspective PNG review renders
- mobile full-review board
- JSON manifest with source and generated-file hashes
- Godot wrapper scene and headless smoke test

The model is normalized to the public review envelope of **136 x 88 x 20 mm** with the bottom connector center as root pivot.

## Content boundary

The package includes no ROM, BIOS, save, emulator core, commercial game label, console geometry, private repository file, device configuration, deployment infrastructure or internal workflow. The visible review label is original neutral RetroLife artwork.

## Remaining gates

This is a visual review asset, not a dimensional replica claim. Physical caliper calibration, explicit owner approval and merge remain blocked.
""")

    write(work / "frontend/godot-ui/scenes/SnesNaCartridgeM2_3.tscn", f"""[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/snes/m2_3/snes_ntsc_u_cartridge_m2_3.glb" id="1_model"]

[node name="SnesNaCartridgeM2_3" type="Node3D"]
metadata/asset_id = "{ASSET_ID}"
metadata/source = "attributed-public-reference-normalized-in-blender"
metadata/license_boundary = "see assets/snes/m2_3/source/LICENSE.md"
metadata/physical_envelope_mm = Vector3(136, 88, 20)
metadata/blender_headless = true
metadata/commercial_label_art_embedded = false
metadata/private_repository_material_used = false
metadata/physical_calibration_complete = false
metadata/owner_visual_approval = false
metadata/may_merge = false

[node name="Model" parent="." instance=ExtResource("1_model")]
[node name="DockPivot" type="Marker3D" parent="."]
[node name="CenterAnchor" type="Marker3D" parent="."]
position = Vector3(0, 0, 0.044)
[node name="BrowseFocusedAnchor" type="Marker3D" parent="."]
position = Vector3(0, 0, 0.044)
rotation_degrees = Vector3(-5, -9, 0)
[node name="DockApproachAnchor" type="Marker3D" parent="."]
position = Vector3(0, 0, 0.044)
rotation_degrees = Vector3(-2, -2, 0)
""")
    write(work / "frontend/godot-ui/scripts/m2_3_snes_blender_smoke_test.gd", f"""extends SceneTree

const SCENE := preload("res://scenes/SnesNaCartridgeM2_3.tscn")
const EXPECTED_ASSET := "{ASSET_ID}"

func _initialize() -> void:
    var instance := SCENE.instantiate()
    root.add_child(instance)
    await process_frame
    var failures: Array[String] = []
    _require(instance.get_meta("asset_id", "") == EXPECTED_ASSET, "asset id", failures)
    _require(instance.get_meta("blender_headless", false), "headless Blender", failures)
    _require(not instance.get_meta("commercial_label_art_embedded", true), "commercial label", failures)
    _require(not instance.get_meta("private_repository_material_used", true), "private material", failures)
    _require(not instance.get_meta("physical_calibration_complete", true), "calibration honesty", failures)
    _require(not instance.get_meta("owner_visual_approval", true), "approval honesty", failures)
    _require(not instance.get_meta("may_merge", true), "merge gate", failures)
    _require(instance.get_node_or_null("Model") != null, "GLB model", failures)
    for marker_name in ["DockPivot", "CenterAnchor", "BrowseFocusedAnchor", "DockApproachAnchor"]:
        _require(instance.get_node_or_null(marker_name) != null, marker_name, failures)
    if failures.is_empty():
        print("RETROLIFE_M2_3_BLENDER_GODOT_OK asset=" + EXPECTED_ASSET)
        quit(0)
        return
    for failure in failures:
        push_error("RETROLIFE_M2_3_BLENDER_GODOT_FAILED: " + failure)
    quit(1)

func _require(condition: bool, label: String, failures: Array[String]) -> void:
    if not condition:
        failures.append(label)
""")

    permanent_workflow = """name: M2.3 Blender cartridge

on:
  pull_request:
    paths:
      - .github/workflows/m2-3-blender.yml
      - scripts/blender/**
      - scripts/verify-m2-3-blender-cartridge.py
      - frontend/design/m2-3-snes-blender-manifest.json
      - frontend/design/mobile/m2-3-snes-blender-*
      - frontend/godot-ui/assets/snes/m2_3/**
      - frontend/godot-ui/scenes/SnesNaCartridgeM2_3.tscn
      - frontend/godot-ui/scripts/m2_3_snes_blender_smoke_test.gd
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: m2-3-blender-${{ github.ref }}
  cancel-in-progress: true

env:
  BLENDER_VERSION: "5.2.1"
  GODOT_VERSION: "4.7"

jobs:
  blender-headless:
    name: Blender headless reproducibility
    runs-on: ubuntu-24.04
    timeout-minutes: 40
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
          fetch-depth: 1
          persist-credentials: false
      - name: Install dependencies
        run: |
          set -euo pipefail
          sudo apt-get update
          sudo apt-get install --yes --no-install-recommends libgl1-mesa-dri libglx-mesa0 python3-pil rsync xauth xvfb
          base="https://download.blender.org/release/Blender5.2"
          curl --fail --location --retry 5 "$base/blender-${BLENDER_VERSION}-linux-x64.tar.xz" --output "$RUNNER_TEMP/blender.tar.xz"
          curl --fail --location --retry 5 "$base/blender-${BLENDER_VERSION}.sha256" --output "$RUNNER_TEMP/blender.sha256"
          expected="$(grep -E "[[:space:]]blender-${BLENDER_VERSION}-linux-x64\\.tar\\.xz$" "$RUNNER_TEMP/blender.sha256" | head -n1 | awk '{print $1}')"
          test -n "$expected"
          echo "$expected  $RUNNER_TEMP/blender.tar.xz" | sha256sum --check --status
          mkdir -p "$RUNNER_TEMP/blender"
          tar -xJf "$RUNNER_TEMP/blender.tar.xz" -C "$RUNNER_TEMP/blender" --strip-components=1
          echo "BLENDER_BIN=$RUNNER_TEMP/blender/blender" >> "$GITHUB_ENV"
      - name: Verify committed package
        run: python3 scripts/verify-m2-3-blender-cartridge.py
      - name: Rebuild in isolation
        env:
          LIBGL_ALWAYS_SOFTWARE: "1"
        run: |
          set -euo pipefail
          rebuild="$RUNNER_TEMP/rebuild"
          mkdir -p "$rebuild"
          rsync -a --exclude=.git ./ "$rebuild/"
          rm -f "$rebuild/frontend/design/m2-3-snes-blender-manifest.json" "$rebuild"/frontend/design/mobile/m2-3-snes-blender-*.png "$rebuild/frontend/godot-ui/assets/snes/m2_3/snes_ntsc_u_cartridge_m2_3.blend" "$rebuild/frontend/godot-ui/assets/snes/m2_3/snes_ntsc_u_cartridge_m2_3.glb"
          source_mesh="$(find "$rebuild/frontend/godot-ui/assets/snes/m2_3/source" -maxdepth 1 -type f \( -name '*.stl' -o -name '*.obj' -o -name '*.ply' \) | head -n1)"
          license="$(python3 -c 'import json;print(json.load(open("frontend/design/m2-3-snes-blender-manifest.json"))["sourceMesh"]["license"])')"
          xvfb-run --auto-servernum --server-args='-screen 0 1920x1080x24 -nolisten tcp' "$BLENDER_BIN" --background --factory-startup --python "$rebuild/scripts/blender/build_m2_3_cartridge.py" -- --root "$rebuild" --source "$source_mesh" | tee "$RUNNER_TEMP/blender.log"
          python3 "$rebuild/scripts/blender/finalize_m2_3_package.py" --root "$rebuild" --source "$source_mesh" --source-license "$license"
          python3 "$rebuild/scripts/verify-m2-3-blender-cartridge.py"
          grep -Fq 'RETROLIFE_M2_3_BLENDER_OK' "$RUNNER_TEMP/blender.log"
      - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
        with:
          name: retrolife-m2-3-blender-${{ github.event.pull_request.head.sha || github.sha }}
          path: |
            ${{ runner.temp }}/rebuild/frontend/design/m2-3-snes-blender-manifest.json
            ${{ runner.temp }}/rebuild/frontend/design/mobile/m2-3-snes-blender-*.png
            ${{ runner.temp }}/rebuild/frontend/godot-ui/assets/snes/m2_3/snes_ntsc_u_cartridge_m2_3.blend
            ${{ runner.temp }}/rebuild/frontend/godot-ui/assets/snes/m2_3/snes_ntsc_u_cartridge_m2_3.glb
          retention-days: 7
          compression-level: 0

  godot-smoke:
    name: Godot import and Blender cartridge smoke
    runs-on: ubuntu-24.04
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
          fetch-depth: 1
          persist-credentials: false
      - name: Install Godot
        run: |
          set -euo pipefail
          curl --fail --location --retry 5 "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" --output "$RUNNER_TEMP/godot.zip"
          unzip -q "$RUNNER_TEMP/godot.zip" -d "$RUNNER_TEMP"
          chmod +x "$RUNNER_TEMP/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
          echo "GODOT_BIN=$RUNNER_TEMP/Godot_v${GODOT_VERSION}-stable_linux.x86_64" >> "$GITHUB_ENV"
      - name: Import and smoke
        run: |
          set -euo pipefail
          "$GODOT_BIN" --headless --path frontend/godot-ui --editor --quit-after 30
          "$GODOT_BIN" --headless --path frontend/godot-ui --script res://scripts/m2_3_snes_blender_smoke_test.gd | tee "$RUNNER_TEMP/smoke.log"
          grep -Fq 'RETROLIFE_M2_3_BLENDER_GODOT_OK' "$RUNNER_TEMP/smoke.log"
"""
    write(work / ".github/workflows/m2-3-blender.yml", permanent_workflow)

    append_once(work / "README.md", "## M2.3 Blender cartridge review", """## M2.3 Blender cartridge review

The current public cartridge review candidate is generated headlessly with Blender 5.2.1 from an attributed public NTSC-U/C reference mesh. It exports a Godot-ready GLB, an authored `.blend` file and mobile PNG review renders. The package contains no commercial game label or private repository material. Physical caliper calibration and explicit visual approval remain open, so the asset is not approved for merge or final geometry.
""")
    append_once(work / "frontend/design/README.md", "## M2.3 Blender cartridge review", """## M2.3 Blender cartridge review

The active review candidate is `retrolife.snes.ntsc-u.cartridge.m2.3.blender.v1`. Blender 5.2.1 imports an attributed public NTSC-U/C reference mesh, normalizes it to the 136 x 88 x 20 mm review envelope, adds only original neutral label artwork, exports the Godot GLB and renders eight review views. See `m2-3-snes-blender-cartridge.md` and `m2-3-snes-blender-manifest.json`.

Physical caliper calibration, explicit owner approval and merge remain blocked.
""")
    append_once(work / "THIRD_PARTY.md", "Thingiverse thing 6364945", f"""## Super Nintendo Cartridge NTSC reference model

- Creator: neebick
- Public source: Thingiverse thing 6364945
- Source page: https://www.thingiverse.com/thing:6364945
- License: {args.source_license}
- Use: attributed M2.3 cartridge reference mesh, normalized and rendered through the public Blender pipeline

The original license remains attached to the source and transformed geometry. No commercial game label is included.
""")

    ci = work / ".github/workflows/ci.yml"
    ci_text = ci.read_text(encoding="utf-8")
    if "verify-m2-3-blender-cartridge.py" not in ci_text:
        needle = "          python3 scripts/verify-m2-snes-reference.py\n"
        if needle not in ci_text:
            raise SystemExit("CI insertion point missing")
        ci.write_text(ci_text.replace(needle, needle + "          python3 scripts/verify-m2-3-blender-cartridge.py\n"), encoding="utf-8")

    prepush = work / "scripts/verify-before-push.sh"
    pre_text = prepush.read_text(encoding="utf-8")
    if "verify-m2-3-blender-cartridge.py" not in pre_text:
        block = """\n# M2.3 attributed Blender cartridge package.\n\"${PYTHON_BIN:-python3}\" scripts/verify-m2-3-blender-cartridge.py\nif [[ -n \"${GODOT_BIN:-}\" ]]; then\n  \"$GODOT_BIN\" --headless --path frontend/godot-ui --editor --quit-after 30\n  \"$GODOT_BIN\" --headless --path frontend/godot-ui --script res://scripts/m2_3_snes_blender_smoke_test.gd | tee \"${TMPDIR:-/tmp}/retrolife-m2-3-blender-smoke.log\"\n  grep -Fq 'RETROLIFE_M2_3_BLENDER_GODOT_OK' \"${TMPDIR:-/tmp}/retrolife-m2-3-blender-smoke.log\"\nfi\n"""
        lines = pre_text.splitlines(True)
        index = next((i for i, line in enumerate(lines) if "RETROLIFE_PRE_PUSH_OK" in line), len(lines))
        lines.insert(index, block)
        prepush.write_text("".join(lines), encoding="utf-8")

    print(f"RETROLIFE_M2_3_PUBLIC_ASSEMBLY_OK source={target_source.relative_to(work)}")


if __name__ == "__main__":
    main()
