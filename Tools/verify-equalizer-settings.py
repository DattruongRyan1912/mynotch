#!/usr/bin/env python3
"""
Headless UI Layout, Interaction & Accessibility Verifier for Equalizer Settings View
Verifies that EqualizerSettingsView, Presets Studio, Slider Controls, and Device Telemetry
render within standard macOS Settings window sizes (680x480, 860x600, 1100x800) and respond
to user interactions (presets, gains, preamp, true-peak ceiling, loudness, cloning).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def run_cmd(cmd, cwd=REPO_ROOT, check=True):
    print(f"\n[RUN] {cmd}")
    start = time.time()
    res = subprocess.run(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    duration = time.time() - start
    print(f"[STATUS] Exit {res.returncode} ({duration:.2f}s)")
    if check and res.returncode != 0:
        print(f"[ERROR OUTPUT]\n{res.stdout}")
        sys.exit(res.returncode)
    return res.returncode, res.stdout, duration

def parse_test_results(output):
    passed_matches = [m for m in re.findall(r"✔ Test (.*?) passed after ([\d\.]+) seconds", output) if not m[0].startswith("run with ")]
    failed_matches = re.findall(r"✘ Test (.*?) failed", output)
    total_run_match = re.search(r"Test run with (\d+) tests in (\d+) suites (passed|failed)", output)

    total_tests = int(total_run_match.group(1)) if total_run_match else len(passed_matches) + len(failed_matches)
    suites = int(total_run_match.group(2)) if total_run_match else 0
    status = total_run_match.group(3) if total_run_match else ("failed" if failed_matches else "passed")

    if total_tests == 0:
        raise ValueError("No tests were executed or parsed from output.")
    if len(failed_matches) > 0 or status != "passed":
        raise AssertionError(f"Test suite failed with {len(failed_matches)} failures: {failed_matches}")

    return {
        "status": status,
        "total_tests": total_tests,
        "suites": suites,
        "passed_count": len(passed_matches),
        "failed_count": len(failed_matches),
        "failures": failed_matches
    }

def main():
    parser = argparse.ArgumentParser(description="Verify MyNotch Equalizer Settings UI & Interactions")
    parser.add_argument("--app", default="/Applications/MyNotch.app", help="Path to installed MyNotch.app bundle")
    parser.add_argument("--output", default=os.path.join(REPO_ROOT, ".build", "equalizer-settings-audit", "native"), help="Output directory")
    args = parser.parse_args()

    print("=" * 60)
    print("MYNOTCH EQUALIZER SETTINGS HEADLESS UI & INTERACTION VERIFIER")
    print("=" * 60)

    report = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "target_app": os.path.abspath(args.app),
        "viewports_tested": [
            {"width": 680, "height": 480, "name": "Standard Compact Settings"},
            {"width": 860, "height": 600, "name": "Default Settings Window"},
            {"width": 1100, "height": 800, "name": "Expanded Studio Settings"}
        ],
        "suites": {}
    }

    # 1. Run Layout Tests
    print("\n>>> 1. Verifying Viewport Layout & Fitting Sizes (680pt, 860pt, 1100pt)...")
    code, out, dur = run_cmd("swift test --package-path Packages/Modules/Equalizer --filter EqualizerTabLayoutTests")
    layout_results = parse_test_results(out)
    layout_results["duration_seconds"] = dur
    report["suites"]["EqualizerTabLayoutTests"] = layout_results
    assert "equalizerSettingsViewFitsStandardSettingsWindowSizes() passed" in out, "Settings layout test failed"
    print("✅ EqualizerSettingsView fits across 680pt, 860pt, and 1100pt viewports without clipping.")

    # 2. Run UI Interaction Tests
    print("\n>>> 2. Verifying UI Interactions (Presets, Band Gains, Preamp, True-Peak Ceiling, Loudness, Profiles)...")
    code, out, dur = run_cmd("swift test --package-path Packages/Modules/Equalizer --filter EQSettingsInteractionTests")
    interaction_results = parse_test_results(out)
    interaction_results["duration_seconds"] = dur
    report["suites"]["EQSettingsInteractionTests"] = interaction_results
    print("✅ All EQSettingsInteractionTests passed cleanly.")

    # 3. Check App Codesign and Team ID (Strict Verification)
    print(f"\n>>> 3. Verifying Code Signature on {args.app} (--verify --deep --strict)...")
    verify_code, verify_out, _ = run_cmd(f"codesign --verify --deep --strict --verbose=2 '{args.app}'", check=False)
    code, sign_out, _ = run_cmd(f"codesign -dvv '{args.app}'", check=False)
    team_match = re.search(r"TeamIdentifier=([A-Z0-9]+)", sign_out)
    team_id = team_match.group(1) if team_match else None
    print(f"Detected TeamIdentifier: {team_id}")
    report["codesign"] = {
        "verify_exit_code": verify_code,
        "verify_output": verify_out.strip(),
        "team_id": team_id,
        "valid": verify_code == 0 and team_id == "B394MAY4QN",
        "details": sign_out.strip()
    }
    if verify_code != 0 or team_id != "B394MAY4QN":
        print(f"❌ Codesign validation failed on {args.app}: strict exit {verify_code}, team_id {team_id}")
        print(f"Strict Verify Output:\n{verify_out}")
        sys.exit(1)
    print("✅ Codesign deep strict verification passed (Team B394MAY4QN).")

    # 4. Check Running Process PID
    print("\n>>> 4. Checking Running MyNotch Process...")
    code, pid_out, _ = run_cmd(f"pgrep -f '{args.app}/Contents/MacOS/MyNotch'", check=False)
    pids = [p.strip() for p in pid_out.strip().splitlines() if p.strip()]
    report["running_process"] = {
        "pids": pids,
        "status": "RUNNING" if pids else "STOPPED"
    }
    print(f"Target Process PIDs: {pids}")
    if not pids:
        print(f"❌ No running MyNotch process found under {args.app}!")
        sys.exit(1)
    print(f"✅ Target MyNotch process running with PID(s): {pids}")

    # 5. Output Manifest
    output_dir = os.path.abspath(args.output)
    os.makedirs(output_dir, exist_ok=True)
    manifest_path = os.path.join(output_dir, "equalizer_settings_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"\nSaved manifest to {manifest_path}")

    # Mirror to docs/evidence
    evidence_dir = os.path.join(REPO_ROOT, "docs", "evidence")
    os.makedirs(evidence_dir, exist_ok=True)
    evidence_manifest = os.path.join(evidence_dir, "equalizer_settings_manifest.json")
    with open(evidence_manifest, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Mirrored manifest to {evidence_manifest}")

    print("\n" + "=" * 60)
    print("UI & LAYOUT VERIFICATION COMPLETE: ALL GATES PASSED")
    print(f"EqualizerTabLayoutTests: {layout_results['passed_count']} tests passed")
    print(f"EQSettingsInteractionTests: {interaction_results['passed_count']} tests passed")
    print(f"App Binary: {args.app} (Team: {team_id}, PIDs: {pids})")
    print("=" * 60)

if __name__ == "__main__":
    main()
