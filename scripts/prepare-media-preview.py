#!/usr/bin/env python3
"""Stage local development models in an isolated, disposable Godot project.

Does not modify the pinned release stage/lock, load the Rust extension, or read
the user's library. Run again after changing a model to refresh the preview.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent.parent
MODEL_IDS = ("snes-ntsc-u", "mega-drive", "playstation-1", "nintendo-64", "nes")
MODEL_CONSOLES = {"snes-ntsc-u": "snes", "mega-drive": "mega-drive", "playstation-1": "playstation-1", "nintendo-64": "nintendo-64", "nes": "nes"}
MARKER = ".retrolife-media-preview"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models-root", required=True, type=Path, help="Local retro-cartridge-models checkout")
    parser.add_argument("--output", type=Path, default=ROOT / ".cache/media-preview")
    parser.add_argument("--owner-examples", type=Path, help="Optional directory of locally generated game GLBs by model ID; missing examples use neutral models and no artwork is staged into the release app")
    args = parser.parse_args()
    source = args.models_root.resolve()
    output = args.output.resolve()
    if args.owner_examples and not args.owner_examples.is_dir():
        raise SystemExit("Owner examples must be an existing directory.")
    if output.exists() and (not output.is_dir() or not (output / MARKER).is_file()):
        raise SystemExit("Output exists and is not a disposable media preview; choose another directory.")
    spec = importlib.util.spec_from_file_location("asset_validation", ROOT / "scripts/prepare-cartridge-assets.py")
    validation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validation)
    models: dict[str, Path] = {}
    owner_example_ids: list[str] = []
    provenance = {}
    locks = {m['id']: m for m in json.loads((ROOT / 'assets/media-models.lock.json').read_text())['models']}
    for model_id in MODEL_IDS:
        path = source / "dist/development" / model_id / f"{model_id}.glb"
        if args.owner_examples and model_id != "snes-ntsc-u":
            example = args.owner_examples.resolve() / model_id / f"{model_id}.glb"
            if example.exists() or example.is_symlink():
                path = example
                owner_example_ids.append(model_id)
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 64 * 1024 * 1024:
            raise SystemExit(f"Missing or unsafe local development model: {model_id}")
        summary = validation.validate_glb(path)
        if model_id not in owner_example_ids and model_id in locks:
            validation.verify(path, locks[model_id]['files'][f'{model_id}.glb'])
        names = [name.lower() for name in summary["meshes"]]
        if not any("front" in name and "label" in name for name in names):
            raise SystemExit(f"Model has no named front label: {model_id}")
        models[model_id] = path
        provenance[model_id] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size}
    output.mkdir(parents=True, exist_ok=True)
    (output / MARKER).write_text("Disposable local development preview; not a release build.\n")
    for folder in ("scripts", "scenes", "shaders"):
        shutil.copytree(ROOT / "frontend/godot-ui" / folder, output / folder, dirs_exist_ok=True)
    for name in ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md"):
        shutil.copy2(ROOT / name, output / name)
    destination = output / "assets/cartridges"
    destination.mkdir(parents=True, exist_ok=True)
    for model_id, path in models.items():
        target = destination if model_id == "snes-ntsc-u" else destination / model_id
        target.mkdir(exist_ok=True)
        shutil.copy2(path, target / f"{model_id}.glb")
    owner_marker = output / 'owner-artwork-preview.json'
    if owner_example_ids:
        owner_marker.write_text(json.dumps({'localOnly': True, 'ownerExampleIds': owner_example_ids, 'models': provenance}, indent=2) + '\n')
    else:
        owner_marker.unlink(missing_ok=True)
    notices = destination / "source-notices"
    notices.mkdir(exist_ok=True)
    for name in ("LICENSE", "NOTICE.md", "CREDITS.md"):
        if (source / name).is_file():
            shutil.copy2(source / name, notices / name)
    for model_id in MODEL_IDS:
        model_notices = notices / model_id
        model_notices.mkdir(exist_ok=True)
        source_notices = source / "assets/templates" / MODEL_CONSOLES[model_id]
        if not source_notices.is_dir():
            source_notices = source / "assets" / model_id
        for name in ("LICENSE", "NOTICE.md", "CREDITS.md"):
            candidate = source_notices / name
            if candidate.is_file():
                shutil.copy2(candidate, model_notices / name)
    (destination / "development-models.json").write_text(json.dumps({"developmentOnly": True, "models": provenance}, indent=2) + "\n")
    (output / "project.godot").write_text('''config_version=5

[application]
config/name="RetroLife Media Preview"
run/main_scene="res://scenes/MediaPreview.tscn"
config/use_custom_user_dir=true
config/custom_user_dir_name="retrolife-media-preview"

[display]
window/size/viewport_width=1600
window/size/viewport_height=1000

[rendering]
renderer/rendering_method="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
''')
    print(f"Local preview staged: {output}")
    print("Release lock and release assets are unchanged. Remove the preview directory to undo staging.")


if __name__ == "__main__":
    main()
