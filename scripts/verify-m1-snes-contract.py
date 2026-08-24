#!/usr/bin/env python3
"""Validate the RetroLife M1 SNES visual and interaction contract."""

from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

SUCCESS_MARKER = "RETROLIFE_M1_SNES_CONTRACT_OK"

REQUIRED_STATES = {
    "browseIdle",
    "browseFocused",
    "commitPending",
    "docking",
    "docked",
    "launching",
    "launchReturn",
    "undocking",
    "recoverableError",
}

REQUIRED_FRAME_STATES = {
    "browse",
    "focused",
    "docking",
    "docked",
    "launch-return",
    "undocking",
}

REQUIRED_TRANSITIONS = {
    ("browseFocused", "confirm", "commitPending"),
    ("commitPending", "nextFrame", "docking"),
    ("docking", "animationCompleted", "docked"),
    ("docking", "cancel", "undocking"),
    ("docked", "cancel", "undocking"),
    ("docked", "launch", "launching"),
    ("launching", "launchCompleted", "launchReturn"),
    ("launching", "launchFailed", "recoverableError"),
    ("launching", "launchCancelled", "docked"),
    ("launchReturn", "settleCompleted", "docked"),
    ("undocking", "animationCompleted", "browseFocused"),
}


class ContractError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def get_path(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    require(root.resolve() in path.parents or path == root.resolve(), f"path escapes repository: {relative}")
    require(path.is_file(), f"required file is missing: {relative}")
    return path


def normalized_pair(value: Any, context: str) -> tuple[float, float]:
    require(isinstance(value, list) and len(value) == 2, f"{context} must be a two-item list")
    x = float(value[0])
    y = float(value[1])
    require(0.0 <= x <= 1.0 and 0.0 <= y <= 1.0, f"{context} must stay in normalized bounds")
    return x, y


def validate_contract(root: Path, contract: dict[str, Any]) -> None:
    require(contract.get("schemaVersion") == 1, "schemaVersion must be 1")
    require(contract.get("contractId") == "retrolife.macos.snes.m1.v1", "unexpected contractId")
    require(contract.get("status") in {"candidateForOwnerApproval", "ownerApproved"}, "unexpected status")

    scope = contract.get("scope", {})
    require(scope.get("systemIds") == ["snes"], "M1 production scope must be SNES only")
    require(scope.get("referenceRegion") == "northAmerica", "reference region must be North America")
    require(scope.get("mediaFamily") == "snes-na-cartridge", "unexpected SNES media family")
    require(scope.get("consoleVisibleInNormalFlow") is False, "normal flow must not display a console")
    require(scope.get("otherSystemsFinalProductionAllowed") is False, "other systems must remain blocked")
    require("SNS-006" in str(scope.get("physicalReference", "")), "physical reference must identify SNS-006 style")

    viewport = contract.get("viewport", {})
    reference = viewport.get("referenceLogicalSize", {})
    require(reference.get("width") == 1600 and reference.get("height") == 900, "reference viewport must be 1600x900")
    safe = viewport.get("safeAreaFractions", {})
    for name in ("left", "right", "top", "bottom"):
        value = float(safe.get(name, -1.0))
        require(0.0 < value < 0.15, f"safe area {name} is outside allowed bounds")

    cartridge = contract.get("cartridge", {})
    variant = cartridge.get("referenceVariant", {})
    require(variant.get("id") == "snes-na-sns-006", "unexpected cartridge reference variant")
    require(float(variant.get("geometryCalibrationTolerancePercentForM2", 0.0)) <= 2.0, "M2 geometry tolerance exceeds 2 percent")
    poses = cartridge.get("poses", {})
    for pose_name in ("browseNeighborLeft", "browseFocused", "browseNeighborRight", "dockApproach", "docked"):
        pose = poses.get(pose_name)
        require(isinstance(pose, dict), f"missing cartridge pose: {pose_name}")
        normalized_pair(pose.get("centerFraction"), f"{pose_name}.centerFraction")
        height = float(pose.get("visualHeightFraction", 0.0))
        require(0.15 <= height <= 0.55, f"{pose_name}.visualHeightFraction is unsafe")

    dock = contract.get("bottomDock", {})
    require(dock.get("visibleWithoutCommittedSelection") is False, "dock must be hidden before commit")
    normalized_pair(dock.get("centerFraction"), "bottomDock.centerFraction")
    normalized_pair(dock.get("slotCenterFraction"), "bottomDock.slotCenterFraction")
    width, height = normalized_pair(dock.get("sizeFraction"), "bottomDock.sizeFraction")
    require(0.30 <= width <= 0.65 and 0.06 <= height <= 0.18, "bottom dock size is outside contract bounds")
    occlusion = float(dock.get("restingOcclusionFraction", 0.0))
    require(0.20 <= occlusion <= 0.32, "dock occlusion must keep the cartridge recognizable")
    rules = "\n".join(str(item).lower() for item in dock.get("rules", []))
    require("not a console" in rules, "dock rules must explicitly reject a console")

    motion = contract.get("motion", {})
    normal = motion.get("normal", {})
    require(normal.get("dockingTotalMs") == 620, "docking duration must be 620 ms")
    require(normal.get("undockingTotalMs") == 540, "undocking duration must be 540 ms")
    require(normal.get("launchReturnSettleMs") == 240, "launch return settle must be 240 ms")
    keyframes = normal.get("dockingKeyframes", [])
    require(len(keyframes) == 5, "normal docking must contain five locked keyframes")
    times = [int(frame.get("timeMs", -1)) for frame in keyframes]
    require(times == sorted(times) and times[0] == 0 and times[-1] == 620, "docking keyframe timing is invalid")
    require("current normalized progress" in str(normal.get("reverseRule", "")).lower(), "reverse rule must preserve current progress")

    reduced = motion.get("reducedMotion", {})
    require(reduced.get("transitionMs") == 120, "reduced-motion transition must be 120 ms")
    require(reduced.get("translationEnabled") is False, "reduced motion must disable translation")
    require(reduced.get("rotationEnabled") is False, "reduced motion must disable rotation")
    require(reduced.get("scalePulseEnabled") is False, "reduced motion must disable scale pulse")
    require("same" in str(reduced.get("behavior", "")).lower() or "identical" in str(reduced.get("behavior", "")).lower(), "reduced motion must preserve equivalent state")

    machine = contract.get("stateMachine", {})
    states = {str(item.get("id")) for item in machine.get("states", [])}
    require(states == REQUIRED_STATES, f"state set mismatch: {sorted(states ^ REQUIRED_STATES)}")
    transitions = {
        (str(item.get("from")), str(item.get("event")), str(item.get("to")))
        for item in machine.get("transitions", [])
    }
    missing_transitions = REQUIRED_TRANSITIONS - transitions
    require(not missing_transitions, f"missing required transitions: {sorted(missing_transitions)}")

    docking_cancel = next(
        (
            item
            for item in machine.get("transitions", [])
            if item.get("from") == "docking" and item.get("event") == "cancel"
        ),
        None,
    )
    require(isinstance(docking_cancel, dict) and docking_cancel.get("reverseFromCurrentProgress") is True, "docking cancel must reverse current progress")
    invariants = "\n".join(str(item).lower() for item in machine.get("invariants", []))
    require("one launch request" in invariants, "duplicate launch invariant is missing")
    require("semantic focus" in invariants, "semantic focus invariant is missing")

    chrome = contract.get("chrome", {})
    focus_keys = chrome.get("focusKeys", {})
    require(focus_keys.get("browseGame") == "browse:game:{gameId}", "browse semantic focus key changed")
    require(focus_keys.get("dockPrimary") == "dock:primary", "dock primary focus key changed")

    golden_frames = contract.get("goldenFrames", [])
    require(len(golden_frames) == 6, "exactly six golden frame entries are required")
    golden_path = get_path(root, str(golden_frames[0].get("file")))
    require(all(str(item.get("file")) == str(golden_frames[0].get("file")) for item in golden_frames), "golden frames must reference one review board")
    golden_tree = ET.parse(golden_path)
    ns = {"svg": "http://www.w3.org/2000/svg"}
    golden_states = {
        element.attrib.get("data-state", "")
        for element in golden_tree.findall(".//svg:g", ns)
        if element.attrib.get("data-state")
    }
    require(golden_states == REQUIRED_FRAME_STATES, f"golden frame panel mismatch: {sorted(golden_states ^ REQUIRED_FRAME_STATES)}")

    storyboard = contract.get("storyboard", {})
    storyboard_path = get_path(root, str(storyboard.get("file")))
    storyboard_tree = ET.parse(storyboard_path)
    normal_panels = [
        element
        for element in storyboard_tree.findall(".//svg:g", ns)
        if "data-story-index" in element.attrib
    ]
    reduced_panels = [
        element
        for element in storyboard_tree.findall(".//svg:g", ns)
        if "data-reduced-index" in element.attrib
    ]
    require(len(normal_panels) == int(storyboard.get("normalMotionPanels", -1)) == 8, "storyboard must contain eight normal-motion panels")
    require(len(reduced_panels) == int(storyboard.get("reducedMotionPanels", -1)) == 3, "storyboard must contain three reduced-motion panels")

    handoff = contract.get("m2Handoff", {})
    locked = "\n".join(str(item).lower() for item in handoff.get("locked", []))
    require("reference region" in locked, "M2 handoff must lock the reference region")
    require("never displays a console" in locked, "M2 handoff must lock the no-console rule")
    revisions = "\n".join(str(item).lower() for item in handoff.get("requiresM1Revision", []))
    require("changing the reference region" in revisions, "region changes must reopen M1")
    require("showing a console" in revisions, "console changes must reopen M1")

    acceptance = contract.get("acceptance", {})
    require(acceptance.get("ownerApprovalRequired") is True, "owner approval must remain required")
    require(acceptance.get("ownerApprovalStatus") in {"pending", "approved"}, "invalid owner approval status")


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    contract_path = repo_root / "frontend/design/m1-snes-contract.json"
    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
        require(isinstance(contract, dict), "contract root must be an object")
        validate_contract(repo_root, contract)
    except (OSError, json.JSONDecodeError, ET.ParseError, ContractError, ValueError, TypeError) as error:
        print(f"RETROLIFE_M1_SNES_CONTRACT_FAILED: {error}", file=sys.stderr)
        return 1

    print(SUCCESS_MARKER)
    print("system=snes region=northAmerica console=false states=9 frames=6 normalPanels=8 reducedPanels=3")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
