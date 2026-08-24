#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "frontend/design/m2-snes-reference-manifest.json"
DOC = ROOT / "frontend/design/m2-snes-reference.md"
ORTHO = ROOT / "frontend/design/m2-snes-orthographic-reference.svg"
ALPHA = ROOT / "frontend/design/m2-snes-alpha-deviation.svg"


def fail(message: str) -> None:
    raise SystemExit(f"RETROLIFE_M2_1_REFERENCE_FAILED: {message}")


for path in [MANIFEST, DOC, ORTHO, ALPHA]:
    if not path.is_file() or path.stat().st_size < 200:
        fail(f"missing or empty {path.relative_to(ROOT)}")

data = json.loads(MANIFEST.read_text())
if data.get("schemaVersion") != 1:
    fail("schemaVersion must be 1")
if data.get("systemId") != "snes" or data.get("region") != "NTSC-U/C":
    fail("reference must remain SNES NTSC-U/C")
if data.get("shellFamily") != "SNS-006 early wide-shell family":
    fail("unexpected shell family")
if data.get("status") != "provisional-orthographic-baseline":
    fail("status must remain provisional until physical calibration")
physical = data.get("physicalCalibration", {})
if not physical.get("requiredBeforeM2_1Closure") or physical.get("completed"):
    fail("physical calibration boundary is not honest")

envelope = data.get("envelope", {})
expected = {"width": 136.0, "height": 88.0, "depth": 20.0}
for key, value in expected.items():
    actual = float(envelope.get(key, {}).get("value", -1))
    if abs(actual - value) > 0.001:
        fail(f"{key} envelope changed from {value}")

landmarks = data.get("provisionalLandmarks", {})
central = float(landmarks["centralUpperBodyWidth"]["value"])
wing = float(landmarks["sideWingWidthEach"]["value"])
if abs((central + 2 * wing) - 136.0) > 0.01:
    fail("central body plus side wings must equal total width")
label = landmarks["labelRecess"]
if float(label["width"]["value"]) < 80 or float(label["height"]["value"]) < 36:
    fail("label recess reverted toward the rejected alpha")
grooves = landmarks["sideGripGrooves"]
if grooves.get("count") != 5 or len(grooves.get("centerY", [])) != 5:
    fail("side grip groove count must remain five")
if landmarks["connectorCavity"]["mouthWidth"]["value"] < 84:
    fail("connector mouth is too narrow")

pcb = data.get("pcbClearance", {})
if pcb.get("pcbThickness") != 1.2 or pcb.get("goldFingerChamferDegrees") != 30.0:
    fail("open PCB constraints changed")
alpha = data.get("alphaDeviation", {})
if alpha.get("finalGeometryAccepted") is not False or alpha.get("classification") != "M2-alpha-blockout":
    fail("alpha must remain rejected")
gate = data.get("modelingGate", {})
if not gate.get("mayStartM2_2Blockout") or gate.get("mayApproveFinalM2_2Geometry") or gate.get("mayStartM3"):
    fail("modeling gate is inconsistent")

ortho = ORTHO.read_text()
for marker in ["Front", "Rear", "Top", "Bottom", "Right side", "136.0 ±1.0 mm"]:
    if marker not in ortho:
        fail(f"orthographic sheet missing {marker}")
alpha_svg = ALPHA.read_text()
for marker in ["Side wings", "Grip bands", "Label recess", "Connector"]:
    if marker not in alpha_svg:
        fail(f"alpha deviation sheet missing {marker}")

print(
    "RETROLIFE_M2_1_REFERENCE_OK "
    "status=provisional physicalCaliper=false "
    "envelope=136x88x20 grooves=5 "
    "m2_2_blockout=true finalApproval=false m3=false"
)
