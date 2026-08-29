#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "frontend/design/m2-snes-reference-manifest.json"
DOC = ROOT / "frontend/design/m2-snes-reference.md"
ORTHO = ROOT / "frontend/design/m2-snes-orthographic-reference.svg"
ALPHA = ROOT / "frontend/design/m2-snes-alpha-deviation.svg"
REFERENCE_ID = "retrolife.m2.1.snes-ntsc-u.reference.v3"
PRIOR_REFERENCE_ID = "retrolife.m2.1.snes-ntsc-u.reference.v2"


def fail(message: str) -> None:
    raise SystemExit(f"RETROLIFE_M2_1_REFERENCE_FAILED: {message}")


def numeric(entry: object) -> float:
    if isinstance(entry, dict):
        return float(entry.get("value", -1))
    return float(entry)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


for path in [MANIFEST, DOC, ORTHO, ALPHA]:
    require(path.is_file() and path.stat().st_size >= 200, f"missing or empty {path.relative_to(ROOT)}")

data = json.loads(MANIFEST.read_text(encoding="utf-8"))
require(data.get("schemaVersion") == 3, "schemaVersion must be 3")
require(data.get("referenceId") == REFERENCE_ID, "unexpected reference ID")
require(data.get("priorReferenceId") == PRIOR_REFERENCE_ID, "prior reference linkage")
require(data.get("systemId") == "snes" and data.get("region") == "NTSC-U/C", "reference must remain SNES NTSC-U/C")
require(data.get("shellFamily") == "SNS-006 early wide-shell family", "unexpected shell family")
require(data.get("status") == "provisional-visual-recalibration-v3", "status must remain provisional")

physical = data.get("physicalCalibration", {})
require(physical.get("requiredBeforeM2_1Closure") is True, "physical calibration must remain required")
require(physical.get("completed") is False, "physical calibration must not be claimed")
require("digital caliper" in str(physical.get("requiredInstrument", "")).lower(), "physical instrument contract")

visual = data.get("visualCalibration", {})
require(visual.get("completed") is True and visual.get("revision") == 3, "visual calibration revision")
require(visual.get("physicalMeasurement") is False, "visual calibration must not claim caliper data")
require("photo" in str(visual.get("method", "")).lower(), "photo-normalized method")
expected_ratios = {
    "centralBodyToOverallWidth": round(92.0 / 136.0, 6),
    "labelToOverallWidth": round(84.5 / 136.0, 6),
    "wingTopDropToOverallHeight": round(5.0 / 88.0, 6),
    "gripToOverallWidth": round(87.0 / 136.0, 6),
}
require(visual.get("ratioChecks") == expected_ratios, "normalized visual ratios")

expected_envelope = {"width": 136.0, "height": 88.0, "depth": 20.0}
for key, expected in expected_envelope.items():
    actual = numeric(data.get("envelope", {}).get(key, {}))
    require(abs(actual - expected) <= 0.001, f"{key} envelope changed from {expected}")

landmarks = data.get("provisionalLandmarks", {})
expected_values = {
    "frontShellDepth": 10.0,
    "centralUpperBodyWidth": 92.0,
    "centralTopWidth": 84.0,
    "sideWingWidthEach": 22.0,
    "sideWingTopY": 83.0,
    "sideWingTopDrop": 5.0,
    "outerCornerRadius": 2.6,
}
for key, expected in expected_values.items():
    actual = numeric(landmarks.get(key, {}))
    require(abs(actual - expected) <= 0.001, f"{key} changed from {expected}")
central = numeric(landmarks["centralUpperBodyWidth"])
wing = numeric(landmarks["sideWingWidthEach"])
require(abs((central + 2 * wing) - 136.0) <= 0.01, "central body plus side wings must equal total width")

label = landmarks.get("labelRecess", {})
for key, expected in {"width": 84.5, "height": 38.0, "bottomY": 45.0, "cornerRadius": 2.0, "depth": 0.42}.items():
    require(abs(numeric(label.get(key, {})) - expected) <= 0.001, f"label {key}")

channel = landmarks.get("lowerFrontGripChannel", {})
for key, expected in {"width": 87.0, "height": 6.3, "centerY": 29.8, "depth": 0.78, "bridgeCount": 1, "bridgeWidth": 18.0}.items():
    require(abs(numeric(channel.get(key, {})) - expected) <= 0.001, f"grip {key}")

bands = landmarks.get("sideMouldedBands", {})
require(bands.get("bandCount") == 5 and bands.get("divisionCount") == 4, "side band count relationship")
require([float(item) for item in bands.get("divisionCenterY", [])] == [24.3, 38.8, 53.3, 67.8], "side band positions")
require(abs(numeric(bands.get("divisionHeight", {})) - 0.72) <= 0.001, "side band division height")
require("sideGripGrooves" not in landmarks, "rejected five-groove interpretation is active")

screws = landmarks.get("securityScrewCenters", {})
for key, expected in {"xAbsolute": 56.7, "y": 7.4, "wellDiameter": 5.2}.items():
    require(abs(numeric(screws.get(key, {})) - expected) <= 0.001, f"screw {key}")
require(numeric(landmarks["connectorCavity"]["mouthWidth"]) >= 84.0, "connector mouth is too narrow")

sources = data.get("sourceHierarchy", [])
source_ids = {entry.get("id") for entry in sources}
for source_id in ["overall-envelope", "patent-USD343833S", "gamestop-smw-front-photo", "evan-amos-public-domain-photo", "wikimedia-ntsc-bottom", "mousebitelabs-pcb"]:
    require(source_id in source_ids, f"source hierarchy missing {source_id}")
for entry in sources:
    if entry.get("type") in {"authentic cartridge photography", "public-domain photograph", "open photograph"}:
        require(entry.get("mediaEmbedded") is not True, f"embedded source media {entry.get('id')}")

pcb = data.get("pcbClearance", {})
require(pcb.get("pcbThickness") == 1.2 and pcb.get("goldFingerChamferDegrees") == 30.0, "open PCB constraints changed")
alpha = data.get("alphaDeviation", {})
require(alpha.get("finalGeometryAccepted") is False and alpha.get("classification") == "M2-alpha-blockout", "alpha must remain rejected")
gate = data.get("modelingGate", {})
require(gate.get("mayStartM2_2Blockout") is True, "M2.2 work gate")
require(gate.get("mayApproveFinalM2_2Geometry") is False and gate.get("mayStartM3") is False, "final geometry gates")
require(any("v5" in condition and "v4" in condition for condition in gate.get("conditions", [])), "v5 rebuild condition")

orthographic = ORTHO.read_text(encoding="utf-8")
for marker in ["M2.1 v3", "Front", "Rear", "Top", "Bottom", "Right side", "136.0 ±1.0 mm", "84.5 × 38.0", "four divisions", "92 mm"]:
    require(marker in orthographic, f"orthographic sheet missing {marker}")
alpha_svg = ALPHA.read_text(encoding="utf-8")
for marker in ["M2.1 v3", "Side wings", "Grip bands", "Label recess", "Connector", "v1 through v4"]:
    require(marker in alpha_svg, f"alpha deviation sheet missing {marker}")

documentation = DOC.read_text(encoding="utf-8")
for marker in ["Reference v3", "92.0 mm", "84.5 × 38.0 mm", "18.0 mm", "Four narrow recessed divisions", "digital caliper"]:
    require(marker in documentation, f"reference documentation missing {marker}")

print(
    "RETROLIFE_M2_1_REFERENCE_OK "
    "status=provisional visualCalibration=v3 physicalCaliper=false "
    "envelope=136x88x20 sideBands=5 divisions=4 "
    "m2_2_cad=true finalApproval=false m3=false"
)
