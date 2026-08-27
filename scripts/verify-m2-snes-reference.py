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


def numeric(entry: object) -> float:
    if isinstance(entry, dict):
        return float(entry.get("value", -1))
    return float(entry)


for path in [MANIFEST, DOC, ORTHO, ALPHA]:
    if not path.is_file() or path.stat().st_size < 200:
        fail(f"missing or empty {path.relative_to(ROOT)}")

data = json.loads(MANIFEST.read_text(encoding="utf-8"))
if data.get("schemaVersion") != 2:
    fail("schemaVersion must be 2")
if data.get("referenceId") != "retrolife.m2.1.snes-ntsc-u.reference.v2":
    fail("unexpected reference ID")
if data.get("systemId") != "snes" or data.get("region") != "NTSC-U/C":
    fail("reference must remain SNES NTSC-U/C")
if data.get("shellFamily") != "SNS-006 early wide-shell family":
    fail("unexpected shell family")
if data.get("status") != "provisional-visual-and-envelope-baseline":
    fail("status must remain provisional until physical calibration")
physical = data.get("physicalCalibration", {})
if not physical.get("requiredBeforeM2_1Closure") or physical.get("completed"):
    fail("physical calibration boundary is not honest")
visual = data.get("visualCalibration", {})
if not visual.get("completed") or visual.get("physicalMeasurement"):
    fail("visual calibration must be recorded without claiming caliper measurement")

envelope = data.get("envelope", {})
expected_envelope = {"width": 136.0, "height": 88.0, "depth": 20.0}
for key, expected in expected_envelope.items():
    actual = numeric(envelope.get(key, {}))
    if abs(actual - expected) > 0.001:
        fail(f"{key} envelope changed from {expected}")

landmarks = data.get("provisionalLandmarks", {})
expected_values = {
    "frontShellDepth": 10.4,
    "centralUpperBodyWidth": 96.0,
    "centralTopWidth": 82.0,
    "sideWingWidthEach": 20.0,
    "sideWingTopY": 81.4,
}
for key, expected in expected_values.items():
    actual = numeric(landmarks.get(key, {}))
    if abs(actual - expected) > 0.001:
        fail(f"{key} changed from {expected}")
central = numeric(landmarks["centralUpperBodyWidth"])
wing = numeric(landmarks["sideWingWidthEach"])
if abs((central + 2 * wing) - 136.0) > 0.01:
    fail("central body plus side wings must equal total width")

label = landmarks.get("labelRecess", {})
if abs(numeric(label["width"]) - 91.5) > 0.001 or abs(numeric(label["height"]) - 39.0) > 0.001:
    fail("label recess does not match visual calibration")
channel = landmarks.get("lowerFrontGripChannel", {})
if abs(numeric(channel["width"]) - 93.0) > 0.001 or abs(numeric(channel["height"]) - 7.2) > 0.001:
    fail("lower grip channel does not match visual calibration")
if numeric(channel.get("bridgeCount", {})) != 3:
    fail("lower grip channel bridge count changed")

bands = landmarks.get("sideMouldedBands", {})
if bands.get("bandCount") != 5 or bands.get("divisionCount") != 4:
    fail("side moulded band relationship must remain five bands and four divisions")
if [float(item) for item in bands.get("divisionCenterY", [])] != [25.8, 42.0, 58.2, 74.4]:
    fail("side band division positions changed")
if "sideGripGrooves" in landmarks:
    fail("rejected five-groove interpretation is still active")

screws = landmarks.get("securityScrewCenters", {})
if abs(numeric(screws["xAbsolute"]) - 56.0) > 0.001 or abs(numeric(screws["y"]) - 6.8) > 0.001:
    fail("screw relationship changed")
if numeric(landmarks["connectorCavity"]["mouthWidth"]) < 84:
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

orthographic = ORTHO.read_text(encoding="utf-8")
for marker in ["Front", "Rear", "Top", "Bottom", "Right side", "136.0 ±1.0 mm", "91.5 × 39.0", "four divisions"]:
    if marker not in orthographic:
        fail(f"orthographic sheet missing {marker}")
alpha_svg = ALPHA.read_text(encoding="utf-8")
for marker in ["Side wings", "Grip bands", "Label recess", "Connector"]:
    if marker not in alpha_svg:
        fail(f"alpha deviation sheet missing {marker}")

documentation = DOC.read_text(encoding="utf-8")
for marker in ["96.0 mm", "91.5 × 39.0 mm", "Four recessed side divisions", "digital caliper"]:
    if marker not in documentation:
        fail(f"reference documentation missing {marker}")

print(
    "RETROLIFE_M2_1_REFERENCE_OK "
    "status=provisional visualCalibration=true physicalCaliper=false "
    "envelope=136x88x20 sideBands=5 divisions=4 "
    "m2_2_cad=true finalApproval=false m3=false"
)
