#!/usr/bin/env python3
"""
analyze_error_by_group.py

Extends the accuracy validation approach by breaking down prediction error
by queue_name and project_name, to identify whether prediction inconsistency
is concentrated in specific queue(s) or project(s) rather than being spread
randomly across the whole dataset.

Based on George's observation that the model should be sensitive to
queue_name and project_name (sample data uses queues: small, big, middle),
this helps confirm whether the ~930MB "default-looking" predictions we found
in the worst-case error analysis are tied to one specific queue/project.

Usage:
    python3 analyze_error_by_group.py \
        --csv /path/to/Sample_Prediction.csv \
        --api-url https://randyy2.dev.fyre.ibm.com:5050 \
        --profile Sample_Prediction \
        --model sample_model_max_mem \
        --cacert /tmp/lsf_cognitive_v1/config/https/cacert_lsf.pem \
        --token "<your JWT>" \
        --sample-size 500
"""

import argparse
import csv
import json
import random
import ssl
import statistics
import sys
import urllib.request
import urllib.error
from collections import defaultdict


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--csv", required=True)
    p.add_argument("--api-url", required=True)
    p.add_argument("--profile", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--cacert", required=True)
    p.add_argument("--token", required=True)
    p.add_argument("--sample-size", type=int, default=500)
    p.add_argument("--run-time-default", type=int, default=60)
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--group-by", default="queue_name,project_name",
                    help="Comma-separated column(s) to group by (default: queue_name,project_name)")
    return p.parse_args()


def load_csv_rows(path):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        return list(reader)


def call_predictor(api_url, profile, model, cacert, token, row, run_time_default):
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

    try:
        with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            return body.get("data", {}).get("y", [None])[0]
    except (urllib.error.URLError, urllib.error.HTTPError, KeyError, json.JSONDecodeError) as e:
        print(f"  [warn] prediction call failed: {e}", file=sys.stderr)
        return None


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

    group_cols = [c.strip() for c in args.group_by.split(",")]

    print(f"Loading ground-truth data from {args.csv} ...")
    rows = load_csv_rows(args.csv)
    print(f"Loaded {len(rows)} rows.")

    for col in group_cols:
        if col not in rows[0]:
            print(f"ERROR: column '{col}' not found in CSV.", file=sys.stderr)
            sys.exit(1)

    sample_size = min(args.sample_size, len(rows))
    sample = random.sample(rows, sample_size)
    print(f"Sampling {sample_size} rows, grouping by: {', '.join(group_cols)}\n")

    # group_key -> list of pct errors
    group_errors = defaultdict(list)
    # group_key -> list of (actual, predicted) pairs, for inspection
    group_examples = defaultdict(list)
    overall_errors = []
    failures = 0

    for i, row in enumerate(sample, 1):
        actual = row.get("max_mem")
        try:
            actual = float(actual)
        except (ValueError, TypeError):
            continue
        if actual == 0:
            continue

        predicted = call_predictor(
            args.api_url, args.profile, args.model, args.cacert, args.token,
            row, args.run_time_default
        )
        if predicted is None:
            failures += 1
            continue
        try:
            predicted = float(predicted)
        except (ValueError, TypeError):
            failures += 1
            continue

        pct_error = abs(predicted - actual) / actual * 100.0
        overall_errors.append(pct_error)

        key = tuple(row.get(c, "?") for c in group_cols)
        group_errors[key].append(pct_error)
        group_examples[key].append((actual, predicted))

        if i % 50 == 0:
            print(f"  ...{i}/{sample_size} processed")

    print(f"\nCompleted: {len(overall_errors)} successful comparisons, {failures} failed calls.\n")

    if not overall_errors:
        print("No successful comparisons.", file=sys.stderr)
        sys.exit(1)

    overall_sorted = sorted(overall_errors)
    print("=" * 70)
    print(f" OVERALL  (n={len(overall_errors)})")
    print(f"   mean={statistics.mean(overall_errors):.1f}%  "
          f"median={percentile(overall_sorted, 50):.1f}%  "
          f"p75={percentile(overall_sorted, 75):.1f}%  "
          f"p90={percentile(overall_sorted, 90):.1f}%")
    print("=" * 70)

    print(f"\nBreakdown by [{', '.join(group_cols)}]:\n")

    # Sort groups by mean error descending, so the worst offenders show first
    sorted_groups = sorted(
        group_errors.items(),
        key=lambda kv: statistics.mean(kv[1]),
        reverse=True
    )

    header = f"{'Group':<40} {'n':>5} {'mean%':>8} {'median%':>9} {'p90%':>8}"
    print(header)
    print("-" * len(header))

    for key, errs in sorted_groups:
        errs_sorted = sorted(errs)
        label = ", ".join(f"{c}={v}" for c, v in zip(group_cols, key))
        print(f"{label:<40} {len(errs):>5} {statistics.mean(errs):>8.1f} "
              f"{percentile(errs_sorted, 50):>9.1f} {percentile(errs_sorted, 90):>8.1f}")

    # Highlight the single worst group specifically
    if sorted_groups:
        worst_key, worst_errs = sorted_groups[0]
        worst_label = ", ".join(f"{c}={v}" for c, v in zip(group_cols, worst_key))
        print(f"\nWorst-performing group: {worst_label}")
        print(f"  Sample predictions from this group (actual -> predicted):")
        for actual, predicted in group_examples[worst_key][:5]:
            print(f"    {actual:.1f}MB -> {predicted:.1f}MB")

        # Check concentration: what fraction of overall high-error cases come from this group?
        high_error_threshold = percentile(overall_sorted, 75)
        total_high_error = sum(1 for e in overall_errors if e >= high_error_threshold)
        worst_group_high_error = sum(1 for e in worst_errs if e >= high_error_threshold)
        if total_high_error > 0:
            concentration = worst_group_high_error / total_high_error * 100
            print(f"\n  This group accounts for {concentration:.0f}% of all samples with "
                  f"error >= p75 threshold ({high_error_threshold:.1f}%)")
            print(f"  ({worst_group_high_error} of {total_high_error} high-error cases)")


if __name__ == "__main__":
    main()
