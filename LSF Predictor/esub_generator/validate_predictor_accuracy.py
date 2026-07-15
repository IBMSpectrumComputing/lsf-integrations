#!/usr/bin/env python3
"""
validate_predictor_accuracy.py

Computes real prediction accuracy statistics by sampling rows from the
predictor's own training/ground-truth CSV, calling the live prediction
endpoint for each row's features, and comparing the predicted max_mem
against the actual (ground truth) max_mem already present in the CSV.

This bypasses the broken /api/predictors route entirely - it only uses
/api/predictions/<profile>, which does not depend on the WML/CPD client.

CAVEAT: this CSV is the training dataset, not a confirmed held-out test
set. cpd_test_size=0.1 means ~10% of these rows were likely held out
during training, but we don't have visibility into exactly which rows.
Testing against rows the model was trained on will likely show BETTER
(lower error) accuracy than true out-of-sample performance would. Treat
these numbers as an optimistic upper bound on accuracy, not a guarantee.

Usage:
    python3 validate_predictor_accuracy.py \
        --csv /opt/ibm/prediction/work/predictions/Sample_Prediction/Sample_Prediction.csv \
        --api-url https://randyy2.dev.fyre.ibm.com:5050 \
        --profile Sample_Prediction \
        --model sample_model_max_mem \
        --cacert /tmp/lsf_cognitive_v1/config/https/cacert_lsf.pem \
        --token "<your JWT>" \
        --sample-size 200
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


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--csv", required=True, help="Path to the ground-truth CSV")
    p.add_argument("--api-url", required=True, help="Predictor base URL, e.g. https://host:5050")
    p.add_argument("--profile", required=True, help="Prediction profile name")
    p.add_argument("--model", required=True, help="Model name within the profile")
    p.add_argument("--cacert", required=True, help="Path to the predictor's TLS cert file")
    p.add_argument("--token", required=True, help="Auth token (raw JWT, no Bearer prefix)")
    p.add_argument("--sample-size", type=int, default=200,
                    help="Number of rows to randomly sample from the CSV (default: 200)")
    p.add_argument("--run-time-default", type=int, default=60,
                    help="run_time value to use if not present as a column (default: 60)")
    p.add_argument("--seed", type=int, default=None, help="Random seed for reproducible sampling")
    return p.parse_args()


def load_csv_rows(path):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        return list(reader)


def call_predictor(api_url, profile, model, cacert, token, row, run_time_default):
    ctx = ssl.create_default_context(cafile=cacert)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # matches curl -k usage seen throughout this project

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
        headers={
            "Content-type": "application/json",
            "Authorization": token,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            return body.get("data", {}).get("y", [None])[0]
    except (urllib.error.URLError, urllib.error.HTTPError, KeyError, json.JSONDecodeError) as e:
        print(f"  [warn] prediction call failed: {e}", file=sys.stderr)
        return None


def main():
    args = parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    print(f"Loading ground-truth data from {args.csv} ...")
    rows = load_csv_rows(args.csv)
    print(f"Loaded {len(rows)} rows.")

    if "max_mem" not in rows[0]:
        print("ERROR: 'max_mem' column not found in CSV. Cannot compute accuracy.", file=sys.stderr)
        sys.exit(1)

    sample_size = min(args.sample_size, len(rows))
    sample = random.sample(rows, sample_size)
    print(f"Sampling {sample_size} rows for accuracy validation...\n")

    errors = []  # absolute percentage errors
    results = []
    failures = 0

    for i, row in enumerate(sample, 1):
        actual = row.get("max_mem")
        try:
            actual = float(actual)
        except (ValueError, TypeError):
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

        if actual == 0:
            # Avoid divide-by-zero; skip rows with zero actual memory
            continue

        pct_error = abs(predicted - actual) / actual * 100.0
        errors.append(pct_error)
        results.append({
            "actual": actual,
            "predicted": predicted,
            "pct_error": pct_error,
        })

        if i % 25 == 0:
            print(f"  ...{i}/{sample_size} processed")

    print(f"\nCompleted: {len(errors)} successful comparisons, {failures} failed calls.\n")

    if not errors:
        print("No successful comparisons - cannot compute statistics.", file=sys.stderr)
        sys.exit(1)

    errors_sorted = sorted(errors)

    def percentile(data, pct):
        if not data:
            return None
        k = (len(data) - 1) * (pct / 100.0)
        f = int(k)
        c = min(f + 1, len(data) - 1)
        if f == c:
            return data[f]
        return data[f] + (data[c] - data[f]) * (k - f)

    print("=" * 60)
    print(" Absolute Percentage Error (APE) Statistics")
    print(" (computed locally from ground-truth CSV vs live predictions)")
    print("=" * 60)
    print(f"  Sample size (successful):  {len(errors)}")
    print(f"  Mean APE:                  {statistics.mean(errors):.1f}%")
    print(f"  Median APE (p50):          {percentile(errors_sorted, 50):.1f}%")
    print(f"  p15:                       {percentile(errors_sorted, 15):.1f}%")
    print(f"  p75:                       {percentile(errors_sorted, 75):.1f}%")
    print(f"  p90:                       {percentile(errors_sorted, 90):.1f}%")
    print(f"  Max APE:                   {max(errors):.1f}%")
    print("=" * 60)
    print()
    print("CAVEAT: this CSV is training data, not a confirmed held-out test")
    print("set. True out-of-sample accuracy may be worse than shown here.")
    print()
    print("Suggested threshold calibration based on these results:")
    p50 = percentile(errors_sorted, 50)
    p75 = percentile(errors_sorted, 75)
    p90 = percentile(errors_sorted, 90)
    print(f"  MODERATE_LOW_RATIO / MODERATE_HIGH_RATIO ~ {p50/100:.2f}  (around median error)")
    print(f"  EXTREME_LOW_RATIO / EXTREME_HIGH_RATIO   ~ {p90/100:.2f}  (around p90 error)")
    print()

    # Show a few worst-case examples for manual inspection
    worst = sorted(results, key=lambda r: r["pct_error"], reverse=True)[:5]
    print("Worst 5 predictions in this sample (for manual sanity check):")
    for r in worst:
        print(f"  actual={r['actual']:.1f}MB  predicted={r['predicted']:.1f}MB  error={r['pct_error']:.1f}%")


if __name__ == "__main__":
    main()
