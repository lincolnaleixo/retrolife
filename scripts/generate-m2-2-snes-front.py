#!/usr/bin/env python3
"""Generate the public M2.2 v2 continuous-surface review package.

Geometry is rebuilt only from the committed M2.1 public reference. The rejected
M2.2 v1 plate meshes are not imported or adapted. Final approval remains gated
on physical calibration and owner visual review.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v2"
PRIOR_ASSET_ID = "retrolife.snes.na-cartridge.m2.2.front.v1"
SOURCE = "original-parametric-continuous-surface-rebuild"
GRID_COLUMNS = 88
GRID_STEP_MM = 1.0


@dataclass
class Mesh:
    vertices: list[tuple[float, float, float]] = field(default_factory=list)
    faces: list[tuple[int, int, int]] = field(default_factory=list)
    uvs: list[tuple[float, float]] = field(default_factory=list)

    @property
    def triangles(self) -> int:
        return len(self.faces)


def value(entry: dict) -> float:
    return float(entry["value"])


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def smoothstep(a: float, b: float, x: float) -> float:
    t = clamp((x - a) / (b - a), 0.0, 1.0) if a != b else float(x >= b)
    return t * t * (3.0 - 2.0 * t)


def rounded_box_sdf(x: float, y: float, cx: float, cy: float, hw: float, hh: float, r: float) -> float:
    qx, qy = abs(x - cx) - (hw - r), abs(y - cy) - (hh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def weight(distance: float, feather: float) -> float:
    return 1.0 - smoothstep(-feather, feather, distance)


def build_rows(height: float, central_width: float, top_drop: float) -> list[tuple[float, float]]:
    wing_top = height - top_drop
    controls = [
        (0.0, 64.0), (1.2, 66.5), (4.2, 68.0), (wing_top - 4.0, 68.0),
        (wing_top - 1.4, 66.8), (wing_top, 64.0), (wing_top, central_width * 0.5 + 2.5),
        (wing_top + 1.4, central_width * 0.5 + 0.9),
        (height - 2.2, central_width * 0.5 + 0.9), (height, central_width * 0.5 - 1.0),
    ]
    rows: list[tuple[float, float]] = []
    for (y0, x0), (y1, x1) in zip(controls, controls[1:]):
        if y0 == y1:
            if not rows or rows[-1] != (y0, x0): rows.append((y0, x0))
            rows.append((y1, x1)); continue
        steps = max(1, math.ceil((y1 - y0) / GRID_STEP_MM))
        for step in range(steps):
            t = step / steps
            row = (y0 + (y1 - y0) * t, x0 + (x1 - x0) * t)
            if not rows or rows[-1] != row: rows.append(row)
    rows.append(controls[-1])
    return rows


def front_z(x: float, y: float, reference: dict, front_depth: float) -> float:
    lm = reference["provisionalLandmarks"]
    width, height = value(reference["envelope"]["width"]), value(reference["envelope"]["height"])
    nx, ny = abs(x) / (width * 0.5), abs((y - height * 0.48) / (height * 0.52))
    z = front_depth - 0.28 + 0.34 * (1 - clamp(nx, 0, 1) ** 1.8) * (1 - clamp(ny, 0, 1) ** 2.2) - 0.18 * clamp(nx, 0, 1) ** 2

    label = lm["labelRecess"]
    d = rounded_box_sdf(x, y, 0.0, value(label["bottomY"]) + value(label["height"]) / 2,
                        value(label["width"]) / 2, value(label["height"]) / 2, value(label["cornerRadius"]))
    z = z * (1 - weight(d, 1.15)) + (front_depth - 0.92) * weight(d, 1.15)

    d = rounded_box_sdf(x, y, 0.0, 28.0, 36.0, 2.6, 2.6)
    z -= 0.82 * weight(d, 0.85)

    grip = lm["sideGripGrooves"]
    inner = value(lm["centralUpperBodyWidth"]) * 0.5 + 1.8
    groove_w = width * 0.5 - inner - 1.4
    for center_y in map(float, grip["centerY"]):
        for sign in (-1.0, 1.0):
            center_x = sign * ((inner + width * 0.5) * 0.5)
            d = rounded_box_sdf(x, y, center_x, center_y, groove_w / 2, value(grip["grooveHeight"]) / 2, value(grip["grooveHeight"]) * 0.45)
            z -= 0.52 * weight(d, 0.40)

    screws = lm["securityScrewCenters"]
    for sx in (-value(screws["xAbsolute"]), value(screws["xAbsolute"])):
        d = math.hypot(x - sx, y - value(screws["y"])) - value(screws["wellDiameter"]) / 2
        z -= 1.15 * weight(d, 0.75)
    return max(6.0, z)


def build_shell(reference: dict) -> tuple[Mesh, Mesh, dict]:
    env, lm = reference["envelope"], reference["provisionalLandmarks"]
    width, height, depth = value(env["width"]), value(env["height"]), value(env["depth"])
    front_depth = depth * 0.52
    rows = build_rows(height, value(lm["centralUpperBodyWidth"]), value(lm["sideWingTopDrop"]))
    cols, mesh = GRID_COLUMNS + 1, Mesh()
    for y, half in rows:
        for col in range(cols):
            x = -half + 2 * half * col / GRID_COLUMNS
            mesh.vertices.append((x / 1000, y / 1000, front_z(x, y, reference, front_depth) / 1000))
    seam = len(mesh.vertices)
    for y, half in rows:
        for col in range(cols):
            x = -half + 2 * half * col / GRID_COLUMNS
            mesh.vertices.append((x / 1000, y / 1000, 0.0))
    for row in range(len(rows) - 1):
        for col in range(GRID_COLUMNS):
            a, b = row * cols + col, row * cols + col + 1
            c, d = (row + 1) * cols + col, (row + 1) * cols + col + 1
            mesh.faces += [(a, c, d), (a, d, b), (a + seam, d + seam, c + seam), (a + seam, b + seam, d + seam)]
    boundary = list(range(cols))
    boundary += [row * cols + GRID_COLUMNS for row in range(1, len(rows))]
    boundary += [(len(rows) - 1) * cols + col for col in range(GRID_COLUMNS - 1, -1, -1)]
    boundary += [row * cols for row in range(len(rows) - 2, 0, -1)]
    for i, fa in enumerate(boundary):
        fb, sa, sb = boundary[(i + 1) % len(boundary)], fa + seam, boundary[(i + 1) % len(boundary)] + seam
        mesh.faces += [(fa, fb, sb), (fa, sb, sa)]

    label = lm["labelRecess"]
    lw, lh, ly = value(label["width"]), value(label["height"]), value(label["bottomY"])
    lz = (front_depth - 0.88) / 1000
    label_mesh = Mesh(
        vertices=[(-lw/2000, ly/1000, lz), (lw/2000, ly/1000, lz), (lw/2000, (ly+lh)/1000, lz), (-lw/2000, (ly+lh)/1000, lz)],
        faces=[(0,1,2),(0,2,3)], uvs=[(0,0),(1,0),(1,1),(0,1)]
    )
    meta = {"frontHalfDepthMm": front_depth, "engineeringBlockoutOnly": {
        "lowerGripChannel": {"widthMm":72.0,"heightMm":5.2,"centerYmm":28.0},
        "surfaceCrownMm":0.34,"surfaceEdgeEaseMm":0.18}}
    return mesh, label_mesh, meta


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def silhouette(scale: float, tx: float, ty: float) -> str:
    pts=[(-64,0),(64,0),(66.5,1.2),(68,4.2),(68,77.5),(66.8,80.1),(64,81.5),(44,81.5),(42.4,82.9),(42.4,85.8),(40.5,88),(-40.5,88),(-42.4,85.8),(-42.4,82.9),(-44,81.5),(-64,81.5),(-66.8,80.1),(-68,77.5),(-68,4.2),(-66.5,1.2)]
    return "M " + " L ".join(f"{tx+x*scale:.2f} {ty-y*scale:.2f}" for x,y in pts) + " Z"


def svg(title: str, body: str, subtitle: str) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900" viewBox="0 0 1600 900"><title>{title}</title><rect width="100%" height="100%" fill="#080a0f"/><text x="80" y="66" fill="#f4f6fb" font-family="system-ui" font-size="34" font-weight="700">{title}</text><text x="80" y="98" fill="#98a2b5" font-family="system-ui" font-size="17">{subtitle}</text>{body}</svg>\n'


def review_files(reference: dict, front_depth: float) -> dict[str,str]:
    shell = f'<path d="{silhouette(6,520,745)}" fill="#aeb2bb" stroke="#d8dbe2" stroke-width="3"/>'
    label='<rect x="271" y="232" width="498" height="231" rx="24" fill="#8f96a3"/>'
    clay=svg("M2.2 v2 continuous front-shell review",'<rect x="60" y="135" width="1480" height="700" rx="28" fill="#11151e"/>'+shell+label+'<text x="1030" y="270" fill="#f4f6fb" font-family="system-ui" font-size="22">one connected molded surface</text><text x="1030" y="315" fill="#a8b1c2" font-family="system-ui" font-size="18">integrated label recess, channel, grooves and screw wells</text>',"Provisional clean rebuild; physical calibration and owner approval remain open")
    overlay=svg("M2.2 v2 orthographic overlay",f'<path d="{silhouette(6,800,760)}" fill="#aeb2bb" fill-opacity=".3" stroke="#e4e7ee" stroke-width="3"/><rect x="392" y="232" width="816" height="528" fill="none" stroke="#d85cff" stroke-width="3" stroke-dasharray="13 9"/>',"Continuous silhouette against the public 136 x 88 mm M2.1 envelope")
    side=svg("M2.2 v2 top and side profile",f'<rect x="90" y="145" width="1420" height="650" rx="26" fill="#10141c"/><path d="M180 330H430L448 312H1152L1170 330H1420V392H180Z" fill="#aeb2bb"/><path d="M660 715V555Q664 535 684 528H742Q760 540 770 563V715Z" fill="#aeb2bb"/><text x="800" y="755" text-anchor="middle" fill="#a8b1c2" font-family="system-ui" font-size="17">front blockout depth {front_depth:.1f} mm</text>',"Continuous crown and seam-plane profile")
    comparison=svg("M2.2 v1 rejection / v2 rebuild",f'<rect x="70" y="145" width="700" height="650" rx="26" fill="#181217"/><text x="420" y="215" text-anchor="middle" fill="#ff91ae" font-family="system-ui" font-size="24">v1 rejected: stacked plates</text><rect x="830" y="145" width="700" height="650" rx="26" fill="#101817"/><text x="1180" y="215" text-anchor="middle" fill="#7ce8d8" font-family="system-ui" font-size="24">v2 connected surface</text><path d="{silhouette(4.5,1180,690)}" fill="#aeb2bb" stroke="#d8dbe2" stroke-width="3"/>',"v2 does not reuse the rejected v1 geometry")
    poses=''.join(f'<rect x="{x-210}" y="145" width="420" height="650" rx="22" fill="#10141c"/><path d="{silhouette(s,x,y)}" fill="#aeb2bb"/><text x="{x}" y="770" text-anchor="middle" fill="#f4f6fb" font-family="system-ui" font-size="20">{name}</text>' for x,y,s,name in [(310,650,3.6,"focused"),(800,690,3.1,"dock approach"),(1290,720,2.8,"docked")])
    return {
      "m2-2-snes-front-clay.svg":clay,"m2-2-snes-front-overlay.svg":overlay,
      "m2-2-snes-front-top-side-overlay.svg":side,"m2-2-snes-alpha-comparison.svg":comparison,
      "m2-2-snes-m1-poses.svg":svg("M2.2 v2 front shell in M1 poses",poses,"Locked public M1 composition; no console")}


GENERATED = [
 "frontend/design/m2-2-snes-front-shell.md","frontend/design/m2-2-snes-front-manifest.json",
 "frontend/design/m2-2-snes-front-clay.svg","frontend/design/m2-2-snes-front-overlay.svg",
 "frontend/design/m2-2-snes-front-top-side-overlay.svg","frontend/design/m2-2-snes-alpha-comparison.svg",
 "frontend/design/m2-2-snes-m1-poses.svg","frontend/godot-ui/assets/snes/m2_2/LICENSE-CC0.md",
 "frontend/godot-ui/assets/snes/m2_2/PROVENANCE.md","frontend/godot-ui/assets/snes/m2_2/README.md"]


def write(root: Path) -> None:
    design, asset = root/"frontend/design", root/"frontend/godot-ui/assets/snes/m2_2"
    design.mkdir(parents=True,exist_ok=True); asset.mkdir(parents=True,exist_ok=True)
    ref=json.loads((design/"m2-snes-reference-manifest.json").read_text())
    shell,label,meta=build_shell(ref); fd=meta["frontHalfDepthMm"]
    lm=ref["provisionalLandmarks"]
    manifest={"schemaVersion":2,"assetId":ASSET_ID,"priorAssetId":PRIOR_ASSET_ID,"priorGeometryAccepted":False,
      "license":"CC0-1.0","source":SOURCE,"runtimeRepresentation":"deterministic-godot-generated-mesh",
      "status":"provisional-continuous-surface-rebuild","referenceId":ref["referenceId"],"physicalCalibrationComplete":False,
      "alphaGeometryReused":False,"systemId":"snes","region":"NTSC-U/C","shellPart":"front",
      "physicalEnvelopeMm":[136.0,88.0,20.0],"frontHalfDepthMm":fd,"rootPivot":"bottom connector center","consoleVisible":False,
      "surfaceTopology":"single-connected-watertight-shell","labelUvBounds":[[0.0,0.0],[1.0,1.0]],"m3TextureSlot":"snes-front-label",
      "mayApproveFinalGeometry":False,"mayStartM2_3Blockout":False,"mayStartM3":False,
      "referenceLandmarks":{"centralUpperBodyWidthMm":value(lm["centralUpperBodyWidth"]),"sideWingWidthEachMm":value(lm["sideWingWidthEach"]),
        "sideGripGrooveCountEach":int(lm["sideGripGrooves"]["count"]),"labelRecessMm":[value(lm["labelRecess"]["width"]),value(lm["labelRecess"]["height"]),value(lm["labelRecess"]["bottomY"])],
        "securityScrewCentersMm":[value(lm["securityScrewCenters"]["xAbsolute"]),value(lm["securityScrewCenters"]["y"])]},
      "engineeringBlockoutOnly":meta["engineeringBlockoutOnly"],"components":{"continuous_shell":{"vertices":len(shell.vertices),"triangles":shell.triangles},"label_surface":{"vertices":len(label.vertices),"triangles":label.triangles}}}
    (design/"m2-2-snes-front-shell.md").write_text(f'''# M2.2 provisional NTSC-U SNES front shell v2\n\n`{PRIOR_ASSET_ID}` is rejected as plate-stacked production geometry. `{ASSET_ID}` is a clean continuous-surface rebuild from the public M2.1 contract; it does not import or adapt v1.\n\nThe shell is one connected watertight surface. Label recess, lower grip channel, five wing grooves and screw wells are depth changes in that surface. Godot regenerates the mesh deterministically at scene load rather than committing a multi-megabyte intermediate OBJ.\n\nPhysical calibration and explicit owner visual approval remain required. M2.3 and M3 stay blocked.\n''')
    for name,text in review_files(ref,fd).items(): (design/name).write_text(text)
    (asset/"LICENSE-CC0.md").write_text("# CC0 1.0 Universal\n\nThe RetroLife M2.2 v2 generator and review assets are dedicated to the public domain under CC0 1.0 Universal.\n")
    (asset/"PROVENANCE.md").write_text(f"# M2.2 v2 provenance\n\nOriginal RetroLife geometry from the public M2.1 manifest. `{PRIOR_ASSET_ID}` is not imported, copied, or used as a modeling source. No third-party mesh, embedded photograph, game art, ROM or console geometry is included.\n\nPhysical cartridge calibration is still required.\n")
    (asset/"README.md").write_text(f"# RetroLife M2.2 SNES front shell v2\n\nAsset: `{ASSET_ID}`. Rejected predecessor: `{PRIOR_ASSET_ID}`. Runtime representation: deterministic Godot-generated connected mesh. Physical calibration and owner approval remain open; M2.3/M3 are blocked.\n")
    manifest["generatedFiles"]={p:sha256(root/p) for p in GENERATED if not p.endswith("manifest.json")}
    (design/"m2-2-snes-front-manifest.json").write_text(json.dumps(manifest,indent=2,sort_keys=True)+"\n")
    print(f"RETROLIFE_M2_2_FRONT_GENERATED asset={ASSET_ID} shell_triangles={shell.triangles} continuous=true watertight=true runtime=godot")


def compare(expected: Path, actual: Path) -> list[str]:
    return [p for p in GENERATED if not (actual/p).is_file() or (expected/p).read_bytes() != (actual/p).read_bytes()]


def main() -> None:
    parser=argparse.ArgumentParser(); parser.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[1]); parser.add_argument("--check",action="store_true")
    args=parser.parse_args(); root=args.root.resolve()
    if not args.check: write(root); return
    with tempfile.TemporaryDirectory() as tmp:
        expected=Path(tmp); target=expected/"frontend/design/m2-snes-reference-manifest.json"; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes((root/"frontend/design/m2-snes-reference-manifest.json").read_bytes()); write(expected)
        diffs=compare(expected,root)
        if diffs: raise SystemExit("Generated M2.2 v2 files are stale:\n"+"\n".join(diffs))
    print("RETROLIFE_M2_2_FRONT_GENERATION_CHECK_OK")


if __name__ == "__main__": main()
