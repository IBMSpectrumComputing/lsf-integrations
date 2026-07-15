#!/usr/bin/env python3
"""
compare_and_perf_test.py

Runs a single sample against the live predictor and uses the results for two
purposes at once (to avoid hitting the API twice):

1. COMPARISON: classifies each job under two threshold configurations - the
   original generic defaults vs. conservative ratios derived from real
   accuracy data - and reports how many jobs would be classified/handled
   differently under each.

2. PERFORMANCE: records per-call latency (the same calls used for #1) and
   reports timing percentiles, to confirm real-world latency stays
   comfortably within the esub script's CURL_TIMEOUT setting.

Usage:
    python3 compare_and_perf_test.py \
        --csv /path/to/Sample_Prediction.csv \
        --api-url https://randyy2.dev.fyre.ibm.com:5050 \
        --profile Sample_Prediction \
        --model sample_model_max_mem \
        --cacert /tmp/lsf_cognitive_v1/config/https/cacert_lsf.pem \
        --token "<your JWT>" \
        --sample-size 300
"""

import argparse
import csv
import json
import random
import ssl
import statistics
import sys
import time
import urllib.request
import urllib.error


# --- Named threshold configurations -----------------------------------------

CONFIGS = {
    "original_defaults": {
        "moderate_low_ratio": 0.2,
        "moderate_low_min_mb": 200,
        "extreme_low_ratio": 0.5,
        "extreme_low_min_mb": 500,
        "moderate_high_ratio": 0.5,
        "moderate_high_min_mb": 300,
        "extreme_high_ratio": 2.0,
        "extreme_high_min_mb": 750,
    },
    "conservative_calibrated": {
        # Derived from real 500-sample accuracy validation on Sample_Prediction:
        # overall p50=17.2%, p75=73.0%
        "moderate_low_ratio": 0.17,
        "moderate_low_min_mb": 200,
        "extreme_low_ratio": 0.73,
        "extreme_low_min_mb": 500,
        "moderate_high_ratio": 0.17,
        "moderate_high_min_mb": 300,
        "extreme_high_ratio": 0.73,
        "extreme_high_min_mb": 750,
    },
}


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--csv", required=True)
    p.add_argument("--api-url", required=True)
    p.add_argument("--profile", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--cacert", required=True)
    p.add_argument("--token", required=True)
    p.add_argument("--sample-size", type=int, default=300)
    p.add_argument("--run-time-default", type=int, default=60)
    p.add_argument("--seed", type=int, default=None)
    return p.parse_args()


def load_csv_rows(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def call_predictor_timed(api_url, profile, model, cacert, token, row, run_time_default):
    """Returns (predicted_value_or_None, elapsed_seconds)"""
    ctx = ssl.create_default_context(cafile=cacert)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    run_time = row.get("run_time", run_time_default)
    try:
        run_time = int(float(run_time))
    except (ValueError, TypeError):
        run_time = run_time_default

    payload = {
        "model": model,
        "input_data": {
            "fields": ["run_time", "project_name", "job_name", "queue_name", "user_name"],
            "values": [[
                run_time,
                row.get("project_name", ""),
                row.get("job_name", ""),
                row.get("queue_name", ""),
                row.get("user_name", ""),
            ]]
        }
    }

    req = urllib.request.Request(
        f"{api_url}/api/predictions/{profile}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-type": "application/json", "Authorization": token},
        method="POST",
    )

    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            elapsed = time.monotonic() - start
            return body.get("data", {}).get("y", [None])[0], elapsed
    except (urllib.error.URLError, urllib.error.HTTPError, KeyError, json.JSONDecodeError) as e:
        elapsed = time.monotonic() - start
        print(f"  [warn] prediction call failed: {e}", file=sys.stderr)
        return None, elapsed


def hybrid_gap(predicted, ratio, min_mb):
    ratio_val = predicted * ratio
    return ratio_val if ratio_val > min_mb else min_mb


def classify(predicted, requested, cfg):
    """Returns one of: extreme_low, moderate_low, ok, moderate_high, extreme_high"""
    moderate_low_gap = hybrid_gap(predicted, cfg["moderate_low_ratio"], cfg["moderate_low_min_mb"])
    extreme_low_gap = hybrid_gap(predicted, cfg["extreme_low_ratio"], cfg["extreme_low_min_mb"])
    moderate_high_gap = hybrid_gap(predicted, cfg["moderate_high_ratio"], cfg["moderate_high_min_mb"])
    extreme_high_gap = hybrid_gap(predicted, cfg["extreme_high_ratio"], cfg["extreme_high_min_mb"])

    extreme_low = max(predicted - extreme_low_gap, 0)
    moderate_low = max(predicted - moderate_low_gap, 0)
    moderate_high = predicted + moderate_high_gap
    extreme_high = predicted + extreme_high_gap

    if requested < extreme_low:
        return "extreme_low"
    elif requested < moderate_low:
        return "moderate_low"
    elif requested > extreme_high:
        return "extreme_high"
    elif requested > moderate_high:
        return "moderate_high"
    else:
        return "ok"


def percentile(data_sorted, pct):
    if not data_sorted:
        return None
    k = (len(data_sorted) - 1) * (pct / 100.0)
    f = int(k)
    c = min(f + 1, len(data_sorted) - 1)
    if f == c:
        return data_sorted[f]
    return data_sorted[f] + (data_sorted[c] - data_sorted[f]) * (k - f)


def main():
    args = parse_args()
    if args.seed is not None:
        random.seed(args.seed)

    print(f"Loading ground-truth data from {args.csv} ...")
    rows = load_csv_rows(args.csv)
    print(f"Loaded {len(rows)} rows.")

    sample_size = min(args.sample_size, len(rows))
    sample = random.sample(rows, sample_size)
    print(f"Sampling {sample_size} rows...\n")

    latencies = []
    classifications = []  # list of dicts
    failures = 0

    for i, row in enumerate(sample, 1):
        actual = row.get("max_mem")
        try:
            actual = float(actual)
        except (ValueError, TypeError):
            continue

        # Use the job's OWN historical actual usage as a stand-in for "what the
        # user originally requested" - this simulates a realistic mix of
        # under/over/reasonable requests relative to what the predictor says,
        # since we don't have real user-specified -M values for this dataset.
        # We perturb it across the sample to get a spread of scenarios.
        requested = actual * random.choice([0.3, 0.6, 1.0, 1.5, 4.0])

        predicted, elapsed = call_predictor_timed(
            args.api_url, args.profile, args.model, args.cacert, args.token,
            row, args.run_time_default
        )
        latencies.append(elapsed)

        if predicted is None:
            failures += 1
            continue
        try:
            predicted = float(predicted)
        except (ValueError, TypeError):
            failures += 1
            continue

        class_original = classify(predicted, requested, CONFIGS["original_defaults"])
        class_conservative = classify(predicted, requested, CONFIGS["conservative_calibrated"])

        classifications.append({
            "requested": requested,
            "predicted": predicted,
            "actual": actual,
            "original": class_original,
            "conservative": class_conservative,
        })

        if i % 50 == 0:
            print(f"  ...{i}/{sample_size} processed")

    print(f"\nCompleted: {len(classifications)} successful, {failures} failed calls.\n")

    # ---------------- PERFORMANCE RESULTS ----------------
    lat_sorted = sorted(latencies)
    print("=" * 60)
    print(" PERFORMANCE (prediction call latency)")
    print("=" * 60)
    print(f"  Calls made:     {len(latencies)}")
    print(f"  Mean latency:   {statistics.mean(latencies)*1000:.0f} ms")
    print(f"  Median (p50):   {percentile(lat_sorted, 50)*1000:.0f} ms")
    print(f"  p90:            {percentile(lat_sorted, 90)*1000:.0f} ms")
    print(f"  p99:            {percentile(lat_sorted, 99)*1000:.0f} ms")
    print(f"  Max:            {max(latencies)*1000:.0f} ms")
    print()
    print("  For reference, the esub script's CURL_TIMEOUT default is 3000 ms.")
    slow_calls = sum(1 for l in latencies if l > 3.0)
    if slow_calls:
        print(f"  WARNING: {slow_calls} of {len(latencies)} calls exceeded 3000ms - "
              f"these would fail open (fall back to unchanged submission) under "
              f"the current default timeout.")
    else:
        print(f"  All calls completed well within the 3000ms default timeout.")
    print("=" * 60)

    # ---------------- COMPARISON RESULTS ----------------
    print()
    print("=" * 60)
    print(" COMPARISON: original_defaults vs. conservative_calibrated")
    print("=" * 60)

    tiers = ["extreme_low", "moderate_low", "ok", "moderate_high", "extreme_high"]

    print("\nTier distribution under each configuration:")
    print(f"{'Tier':<16} {'original':>10} {'conservative':>14}")
    for tier in tiers:
        orig_count = sum(1 for c in classifications if c["original"] == tier)
        cons_count = sum(1 for c in classifications if c["conservative"] == tier)
        print(f"{tier:<16} {orig_count:>10} {cons_count:>14}")

    changed = [c for c in classifications if c["original"] != c["conservative"]]
    if classifications:
        pct_changed = len(changed) / len(classifications) * 100
    else:
        pct_changed = 0
    print(f"\nJobs with a DIFFERENT classification between configs: "
          f"{len(changed)} of {len(classifications)} ({pct_changed:.0f}%)")

    if changed:
        print("\nExamples of classification changes:")
        for c in changed[:8]:
            print(f"  requested={c['requested']:.0f}MB predicted={c['predicted']:.0f}MB  "
                  f"original={c['original']:<14} -> conservative={c['conservative']}")


if __name__ == "__main__":
    main()
