#!/usr/bin/env python3
"""
Verification Runner: True-Peak Limiter (Option 2) & Equalizer Management Interface
Verifies ITU-R BS.1770-5 Annex 2 Conformance, DSP Limiter invariants, zero allocation,
UI management tests, test audio vector SHA-256 hashes, and in-place release deployment.
"""

import argparse
import hashlib
import json
import math
import os
import re
import struct
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

def measure_pcm_true_peak(pcm_path):
    """Independently calculates 32x Lanczos sinc interpolated continuous true-peak from raw Float32 LE stereo PCM."""
    with open(pcm_path, "rb") as f:
        raw = f.read()
    count = len(raw) // 4
    samples = struct.unpack(f"<{count}f", raw)
    stereo_frames = count // 2
    ch0 = [samples[i * 2] for i in range(stereo_frames)]
    ch1 = [samples[i * 2 + 1] for i in range(stereo_frames)]
    
    radius = 16
    oversample = 32
    
    def lanczos_sinc(x, a=16.0):
        if abs(x) < 1e-9: return 1.0
        if abs(x) >= a: return 0.0
        px = math.pi * x
        return (math.sin(px) / px) * (math.sin(px / a) / (px / a))
        
    def measure_channel(chan):
        max_val = max(abs(s) for s in chan) if chan else 0.0
        n = len(chan)
        if n <= 1: return max_val
        for i in range(n - 1):
            for sub in range(oversample):
                t = i + sub / oversample
                interp = sum(chan[k] * lanczos_sinc(t - k) for k in range(max(0, i - radius), min(n, i + radius + 1)))
                abs_interp = abs(interp)
                if abs_interp > max_val:
                    max_val = abs_interp
        return max_val
        
    linear_peak = max(measure_channel(ch0), measure_channel(ch1))
    dbtp = 20.0 * math.log10(linear_peak) if linear_peak > 1e-9 else -180.0
    return linear_peak, dbtp

def measure_pcm_signal_delay(in_pcm_path, out_pcm_path):
    """Independently extracts true signal lookahead delay from PCM audio waveforms."""
    with open(in_pcm_path, "rb") as f:
        in_raw = f.read()
    with open(out_pcm_path, "rb") as f:
        out_raw = f.read()
    in_samples = [s for s in struct.unpack(f"<{len(in_raw)//4}f", in_raw)[0::2]]
    out_samples = [s for s in struct.unpack(f"<{len(out_raw)//4}f", out_raw)[0::2]]
    
    for d in range(min(256, len(out_samples) - 100)):
        matches = True
        for k in range(100):
            if abs(out_samples[d + k] - in_samples[k]) > 1e-6:
                matches = False
                break
        if matches:
            return d
    return -1

def generate_test_vectors():
    """Generates standard EBU Tech 3341 Table 1 Cases 15 to 23 test vectors and computes SHA-256 hashes."""
    sample_rate = 48000.0
    frame_count = 512
    vectors = {}

    def hash_floats(samples):
        b = bytearray()
        for s in samples:
            b.extend(struct.pack('<f', float(s)))
        return hashlib.sha256(b).hexdigest()

    # EBU Case 15: fs/4, amplitude 0.50 FFS, phase 0.0°
    freq_c15 = sample_rate / 4.0
    c15 = [0.50 * math.sin(2.0 * math.pi * freq_c15 * i / sample_rate) for i in range(frame_count)]
    vectors["EBU_Case_15_fsOver4_Phase0"] = {
        "description": "EBU Case 15: fs/4, 0.50 FFS, phase 0.0°, expected -6.0 dBTP (+0.2/-0.4 dBTP)",
        "sample_rate": 48000,
        "frames": len(c15),
        "sample_peak": max(abs(x) for x in c15),
        "expected_dbtp": -6.0,
        "sha256": hash_floats(c15)
    }

    # EBU Case 16: fs/4, amplitude 0.50 FFS, phase 45.0°
    c16 = [0.50 * math.sin(2.0 * math.pi * freq_c15 * i / sample_rate + math.pi / 4.0) for i in range(frame_count)]
    vectors["EBU_Case_16_fsOver4_Phase45"] = {
        "description": "EBU Case 16: fs/4, 0.50 FFS, phase 45.0°, expected -6.0 dBTP (+0.2/-0.4 dBTP)",
        "sample_rate": 48000,
        "frames": len(c16),
        "sample_peak": max(abs(x) for x in c16),
        "expected_dbtp": -6.0,
        "sha256": hash_floats(c16)
    }

    # EBU Case 17: fs/6, amplitude 0.50 FFS, phase 60.0°
    freq_c17 = sample_rate / 6.0
    c17 = [0.50 * math.sin(2.0 * math.pi * freq_c17 * i / sample_rate + math.pi / 3.0) for i in range(frame_count)]
    vectors["EBU_Case_17_fsOver6_Phase60"] = {
        "description": "EBU Case 17: fs/6, 0.50 FFS, phase 60.0°, expected -6.0 dBTP (+0.2/-0.4 dBTP)",
        "sample_rate": 48000,
        "frames": len(c17),
        "sample_peak": max(abs(x) for x in c17),
        "expected_dbtp": -6.0,
        "sha256": hash_floats(c17)
    }

    # EBU Case 18: fs/8, amplitude 0.50 FFS, phase 67.5°
    freq_c18 = sample_rate / 8.0
    phase_c18 = 67.5 * math.pi / 180.0
    c18 = [0.50 * math.sin(2.0 * math.pi * freq_c18 * i / sample_rate + phase_c18) for i in range(frame_count)]
    vectors["EBU_Case_18_fsOver8_Phase67p5"] = {
        "description": "EBU Case 18: fs/8, 0.50 FFS, phase 67.5°, expected -6.0 dBTP (+0.2/-0.4 dBTP)",
        "sample_rate": 48000,
        "frames": len(c18),
        "sample_peak": max(abs(x) for x in c18),
        "expected_dbtp": -6.0,
        "sha256": hash_floats(c18)
    }

    # EBU Case 19: fs/4, amplitude sqrt(2) FFS (~1.414), phase 45.0°
    c19 = [math.sqrt(2.0) * math.sin(2.0 * math.pi * freq_c15 * i / sample_rate + math.pi / 4.0) for i in range(frame_count)]
    vectors["EBU_Case_19_fsOver4_Overload_Plus3dBTP"] = {
        "description": "EBU Case 19: fs/4, 1.414 FFS, phase 45.0°, expected +3.0 dBTP (+0.2/-0.4 dBTP)",
        "sample_rate": 48000,
        "frames": len(c19),
        "sample_peak": max(abs(x) for x in c19),
        "expected_dbtp": 3.0,
        "sha256": hash_floats(c19)
    }

    # EBU Cases 20 to 23: 4x burst downsampled with offsets 0..3
    anti_alias_taps = [
        -0.0, 1.308e-05, 8.833e-05, 0.0002049, 0.00021481, -9.63e-05, -0.00083106, -0.00176236,
        -0.00224027, -0.00139782, 0.0013026, 0.00539106, 0.00902078, 0.00936847, 0.00395639,
        -0.00751033, -0.02171339, -0.03173139, -0.02902488, -0.00695982, 0.03553972, 0.09201923,
        0.14949816, 0.19246032, 0.2083795, 0.19246032, 0.14949816, 0.09201923, 0.03553972,
        -0.00695982, -0.02902488, -0.03173139, -0.02171339, -0.00751033, 0.00395639, 0.00936847,
        0.00902078, 0.00539106, 0.0013026, -0.00139782, -0.00224027, -0.00176236, -0.00083106,
        -9.63e-05, 0.00021481, 0.0002049, 8.833e-05, 1.308e-05, -0.0
    ]
    fs4 = sample_rate * 4.0
    total4x = max(frame_count * 4 + 256, 4 * 512)
    t0 = 4 * 128
    omega_bg = 2.0 * math.pi * (sample_rate / 6.0) / fs4
    omega_burst = 2.0 * math.pi * (sample_rate / 4.0) / fs4

    high_rate = []
    for i in range(total4x):
        if i < t0:
            high_rate.append(0.50 * math.sin(omega_bg * i))
        elif i < t0 + 16:
            phi0 = omega_bg * t0
            high_rate.append(1.00 * math.sin(phi0 + omega_burst * (i - t0)))
        else:
            phi0 = omega_bg * t0
            high_rate.append(0.50 * math.sin(phi0 + omega_bg * (i - (t0 + 16))))

    tap_count = len(anti_alias_taps)
    filtered4x = [0.0] * total4x
    for i in range(total4x):
        s = 0.0
        for k in range(tap_count):
            if i - k >= 0:
                s += anti_alias_taps[k] * high_rate[i - k]
        filtered4x[i] = s

    for offset in range(4):
        downsampled = []
        idx = offset
        while idx < total4x and len(downsampled) < frame_count:
            downsampled.append(filtered4x[idx])
            idx += 4

        case_num = 20 + offset
        vectors[f"EBU_Case_{case_num}_BurstDownsampled_Offset{offset}"] = {
            "description": f"EBU Case {case_num}: 4x burst downsampled with offset {offset}, expected 0.0 dBTP (+0.2/-0.4 dBTP)",
            "sample_rate": 48000,
            "frames": len(downsampled),
            "sample_peak": max(abs(x) for x in downsampled),
            "expected_dbtp": 0.0,
            "sha256": hash_floats(downsampled)
        }

    return vectors

def main():
    parser = argparse.ArgumentParser(description="Verify MyNotch True-Peak Limiter & Equalizer Settings")
    parser.add_argument("--app", default="/Applications/MyNotch.app", help="Path to installed MyNotch.app bundle")
    parser.add_argument("--manifest", default=os.path.join(REPO_ROOT, "docs", "evidence", "equalizer_true_peak_manifest.json"), help="Output manifest JSON path")
    parser.add_argument("--output", default=None, help="Optional text output path")
    args = parser.parse_args()

    print("=" * 60)
    print("MYNOTCH TRUE-PEAK LIMITER & EQ MANAGEMENT INTERFACE VERIFIER")
    print("=" * 60)
    
    report = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "architecture": "Option 2: ITU-R BS.1770-5 Annex 2 True-Peak Limiter (4x FIR) + Settings Studio",
        "specifications": {
            "itu_r_bs1770": "Annex 2 (4x polyphase FIR, 48 taps, passband ripple <= 0.1 dB)",
            "ebu_tech_3341": "Cases 15 to 23 conformance verified",
            "lookahead_latency": "108 frames at 48kHz (fixed latency FIFO delay line)",
            "allocation_guarantee": "Zero heap allocations on CoreAudio IO thread (processDoesNotAllocate)",
            "safe_unity_preservation": "Bit-exact passthrough for safe signals below threshold",
            "stereo_linking": "Linked gain envelope across all active audio channels"
        },
        "test_vectors": generate_test_vectors(),
        "suites": {}
    }
    
    # 1. Run EqualizerDSPTests
    print("\n>>> 1. Running EqualizerDSPTests (Limiter Conformance, Zero Allocation, PCM Export)...")
    code, out, dur = run_cmd("swift test --package-path Packages/Modules/Equalizer --filter EqualizerDSPTests")
    parsed = parse_test_results(out)
    parsed["duration_seconds"] = dur
    report["suites"]["EqualizerDSPTests"] = parsed
    
    # Check that processDoesNotAllocate and TruePeak tests passed
    assert "processDoesNotAllocate() passed" in out, "processDoesNotAllocate did not pass"
    assert "Oracle Calibration Suite" in out and "EBU Tech 3341" in out, "True-Peak Conformance & Oracle Calibration suites missing"
    assert "True-Peak Limiter Comprehensive Test Suite" in out, "True-Peak Limiter suite missing"
    assert "True-Peak Limiter PCM Vector Export & Zero-Overshoot Verification" in out, "TruePeakPCMExportTests suite missing"
    
    # 1b. Verify Generated PCM Files & Independent Hashes
    print("\n>>> 1b. Verifying Generated PCM Files, Hashes & Invariants...")
    pcm_manifest_path = os.path.join(REPO_ROOT, ".build", "equalizer-settings-audit", "equalizer_true_peak_manifest.json")
    assert os.path.exists(pcm_manifest_path), f"PCM manifest missing at {pcm_manifest_path}"
    with open(pcm_manifest_path, "r", encoding="utf-8") as f:
        pcm_manifest = json.load(f)
    
    pcm_cases = pcm_manifest.get("pcm_cases", {})
    assert len(pcm_cases) >= 12, f"Expected at least 12 PCM cases, found {len(pcm_cases)}"
    
    for case_id, case_data in pcm_cases.items():
        in_path = os.path.join(REPO_ROOT, case_data["input_pcm"])
        out_path = os.path.join(REPO_ROOT, case_data["output_pcm"])
        assert os.path.exists(in_path), f"Input PCM missing: {in_path}"
        assert os.path.exists(out_path), f"Output PCM missing: {out_path}"
        
        # Verify SHA-256 hashes independently in Python
        with open(in_path, "rb") as pf:
            calc_in_hash = hashlib.sha256(pf.read()).hexdigest()
        with open(out_path, "rb") as pf:
            calc_out_hash = hashlib.sha256(pf.read()).hexdigest()
            
        assert calc_in_hash == case_data["input_sha256"], f"Input hash mismatch on {case_id}"
        assert calc_out_hash == case_data["output_sha256"], f"Output hash mismatch on {case_id}"
        
        # Independent Python Measurement of True-Peak from raw PCM bytes
        py_linear, py_dbtp = measure_pcm_true_peak(out_path)
        py_overshoot = max(0.0, py_dbtp - (-0.5))
        assert py_overshoot <= 1e-6, f"Independent Python Lanczos measurement detected overshoot on {case_id}: {py_dbtp:.6f} dBTP (ceiling -0.5 dBTP)"
        case_data["python_measured_true_peak_dbtp"] = py_dbtp
        case_data["python_measured_overshoot_dbtp"] = py_overshoot
        
        # Independent delay extraction on safe signal
        if case_id == "Safe_Low_Amplitude_Minus20dBFS":
            measured_delay = measure_pcm_signal_delay(in_path, out_path)
            assert measured_delay == 108, f"Measured audio signal delay is {measured_delay} frames, expected 108"
            case_data["python_measured_delay_frames"] = measured_delay
            print(f"  [SIGNAL DELAY OK] Independently verified exact {measured_delay} frames lookahead delay from PCM audio waveforms")
        
        # Verify invariants: zero overshoot, zero allocations, 108 frames latency
        assert case_data["overshoot_dbtp"] <= 1e-6, f"Overshoot > 0 on {case_id}: {case_data['overshoot_dbtp']} dBTP"
        assert case_data["io_allocations"] == 0, f"Heap allocations on IO thread for {case_id}: {case_data['io_allocations']}"
        assert case_data["latency_frames"] == 108, f"Unexpected latency on {case_id}: {case_data['latency_frames']}"
        print(f"  [PCM OK] {case_id:40} in_tp={case_data['input_true_peak_dbtp']:+6.2f} dBTP, out_tp={case_data['output_true_peak_dbtp']:+6.2f} dBTP, py_tp={py_dbtp:+6.2f} dBTP, overshoot={py_overshoot:.6f} dB")
        
    report["pcm_cases"] = pcm_cases
    
    # 2. Run EqualizerAudioTests & EqualizerModuleTests
    print("\n>>> 2. Running EqualizerAudioTests & EqualizerModuleTests (Pipeline, Telemetry, UI Views)...")
    code, out, dur = run_cmd("swift test --package-path Packages/Modules/Equalizer --filter 'EqualizerAudioTests|EqualizerModuleTests'")
    parsed = parse_test_results(out)
    parsed["duration_seconds"] = dur
    report["suites"]["EqualizerAudioAndModuleTests"] = parsed
    
    # 3. Run MyNotchCore EqualizerStateTests
    print("\n>>> 3. Running EqualizerStateTests (Presets Studio, CRUD, System Lock)...")
    code, out, dur = run_cmd("swift test --package-path Packages/MyNotchCore --filter EqualizerStateTests")
    parsed = parse_test_results(out)
    parsed["duration_seconds"] = dur
    report["suites"]["EqualizerStateTests"] = parsed
    
    # 4. Run Media Module EQQuickControlTests
    print("\n>>> 4. Running Media Module EQQuickControlTests...")
    code, out, dur = run_cmd("swift test --package-path Packages/Modules/Media --filter EQQuickControlTests")
    parsed = parse_test_results(out)
    parsed["duration_seconds"] = dur
    report["suites"]["EQQuickControlTests"] = parsed
    
    # 5. Build and Deploy Release In-Place
    print("\n>>> 5. In-Place Release Deployment (bash Tools/deploy-release.sh)...")
    code, out, dur = run_cmd("bash Tools/deploy-release.sh")
    report["deployment"] = {
        "exit_code": code,
        "duration_seconds": dur,
        "verified": code == 0
    }
    
    # 6. Verify Running Application & PID
    print(f"\n>>> 6. Verifying Running Application & Signature on {args.app}...")
    code, pid_out, _ = run_cmd(f"pgrep -f '{args.app}/Contents/MacOS/MyNotch'", check=False)
    pids = [p.strip() for p in pid_out.strip().splitlines() if p.strip()]
    report["running_process"] = {
        "pids": pids,
        "status": "RUNNING" if pids else "STOPPED"
    }
    print(f"Verified Running PIDs: {pids}")
    assert len(pids) > 0, "No running MyNotch process found after deployment!"
    
    verify_code, verify_out, _ = run_cmd(f"codesign --verify --deep --strict --verbose=2 '{args.app}'", check=False)
    code, sign_out, _ = run_cmd(f"codesign -dvv '{args.app}'", check=False)
    team_match = re.search(r"TeamIdentifier=([A-Z0-9]+)", sign_out)
    team_id = team_match.group(1) if team_match else None
    report["signature"] = {
        "valid": verify_code == 0 and team_id == "B394MAY4QN",
        "verify_exit_code": verify_code,
        "verify_output": verify_out.strip(),
        "team_id": team_id,
        "output": sign_out.strip()
    }
    assert verify_code == 0 and team_id == "B394MAY4QN", f"Strict code signature verification failed on {args.app}:\n{verify_out}\n{sign_out}"
    
    # Summary
    print("\n" + "=" * 60)
    print("VERIFICATION COMPLETE: ALL GATES PASSED")
    print(f"EqualizerDSP: {report['suites']['EqualizerDSPTests']['passed_count']} tests passed")
    print(f"EqualizerAudio/Module: {report['suites']['EqualizerAudioAndModuleTests']['passed_count']} tests passed")
    print(f"EqualizerState: {report['suites']['EqualizerStateTests']['passed_count']} tests passed")
    print(f"EQQuickControl: {report['suites']['EQQuickControlTests']['passed_count']} tests passed")
    print(f"Deployed: {args.app} (Team: {team_id}, PID: {pids})")
    print("=" * 60)
    
    # Save JSON manifest
    manifest_path = os.path.abspath(args.manifest)
    os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Saved manifest to {manifest_path}")

    if args.output:
        out_path = os.path.abspath(args.output)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(json.dumps(report, indent=2))
        print(f"Saved report output to {out_path}")

if __name__ == "__main__":
    main()
