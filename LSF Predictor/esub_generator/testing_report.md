# Testing Plan: LSF Predictor-Assisted Memory Validation

This plan walks through validating the feature end-to-end on a cluster with a real,
completed prediction profile - from checking data quality, through calibrated setup,
to live job submission tests and final validation reporting.

## Prerequisites

- [ ] Predictor service is running and reachable.
- [ ] A completed (not "Loading" or "failed") prediction profile exists for the target
      cluster, with a known profile name and model name.
- [ ] You have login credentials for the predictor web app.
- [ ] You have admin/sudo access on the LSF host to deploy the esub script.
- [ ] `setup_esub_predictor_memcheck.sh`, `validate_predictor_accuracy.py`,
      `analyze_error_by_group.py`, and `compare_and_perf_test.py` are available on
      the host (or a host with `python3` and network access to the predictor, and
      `docker` access if the CSV lives inside a container).

---

## Step 1 - Confirm which profile is actually usable

```bash
curl -s -k --cacert <cacert_path> \
  -H "Authorization: <token>" \
  https://<predictor-host>:<port>/api/predictions | python3 -m json.tool
```

Check the `state` field for each profile/version. Only proceed with one showing
`"state": "completed"`. If you don't have a token yet, get one first:

```bash
curl -s -k -X POST https://<predictor-host>:<port>/api/login \
     -H 'Content-Type: application/json' \
     -d '{"name":"<username>","password":"<password>"}' | python3 -m json.tool
```

**Note:** if `/api/predictors` (plural) 500-errors, this may indicate an unrelated
WML/CPD connectivity issue on the backend (seen in our own testing - traced to a CPD
project membership problem). This does not block any step below, since none of them
depend on that route.

---

## Step 2 - Locate and copy out the profile's ground-truth training data

```bash
docker exec -it <predictor_container_name> find /opt/ibm/prediction/work/predictions -type f
```

Look for `<profile_name>.csv` under that profile's directory. Confirm it has a
`max_mem` column (or whatever your target label is) plus the feature columns the
model expects (`run_time`, `project_name`, `job_name`, `queue_name`, `user_name`).

```bash
docker cp <predictor_container_name>:/opt/ibm/prediction/work/predictions/<profile_name>/<profile_name>.csv ./<profile_name>.csv
```

**Note:** this file is training data. Some portion (commonly ~10%, check the
profile's `cpd_test_size` field) was likely held out during training, but which rows
isn't visible to us. Treat accuracy numbers derived from this file as an optimistic
upper bound, not a guaranteed real-world figure.

---

## Step 3 - (Optional but recommended) Investigate accuracy before committing

Before running the setup wizard, it's worth understanding the model's real accuracy
characteristics on their own:

```bash
python3 validate_predictor_accuracy.py \
    --csv ./<profile_name>.csv \
    --api-url https://<predictor-host>:<port> \
    --profile <profile_name> \
    --model <model_name> \
    --cacert <cacert_path> \
    --token "<token>" \
    --sample-size 500
```

Review mean/median/p15/p75/p90/max error, and the "worst 5" predictions for a sanity
check. **Decision point:** if median error is very high (e.g. above ~50%), consider
whether auto-adjustment is appropriate at all for this model - warn-only mode may be
safer until the model improves.

**If accuracy looks inconsistent or surprising**, break it down by segment to check
for concentration in specific projects/queues:

```bash
python3 analyze_error_by_group.py \
    --csv ./<profile_name>.csv \
    --api-url https://<predictor-host>:<port> \
    --profile <profile_name> \
    --model <model_name> \
    --cacert <cacert_path> \
    --token "<token>" \
    --sample-size 500
```

In our own testing, this revealed that accuracy varied by two orders of magnitude
depending on `project_name` (dominant factor) and `queue_name` (secondary,
compounding factor) - worth knowing before you commit to a single global threshold
for the whole profile.

---

## Step 4 - Run the setup wizard with live calibration

```bash
sh setup_esub_predictor_memcheck.sh
```

Walk through the prompts (connection details, login, profile/model). When asked:

```
Would you like to auto-calibrate the ratio thresholds by analyzing this
model's real prediction accuracy against its own training data? [y/N]
```

Answer **y**, and provide the path to the CSV from Step 2 when prompted (the wizard
will suggest `./<profile_name>.csv` as a default). Choose a sample size - larger
samples give more stable percentile estimates at the cost of a longer wait (roughly
linear in sample size).

**Important, based on our own testing:** a small sample (n=100) on a model with
significant per-segment accuracy variance produced a visibly unstable
`EXTREME_LOW_RATIO` (over 1.0, versus ~0.84 from a 1000-sample run on the same
model) - large enough that the extreme-low threshold computed to zero, silently
disabling the "auto-adjust up" behavior entirely. We recommend **at least a few
hundred samples**, and suggest cross-checking the resulting ratios against a
larger run of `validate_predictor_accuracy.py` if you used a small sample here.

The wizard will print the resulting calibrated percentiles and use them as the
default values for the threshold prompts that follow - press Enter to accept them,
or override if you have reason to.

The wizard will then:
- Generate the esub script with these values embedded
- Attempt to auto-detect `$LSF_SERVERDIR` and offer to deploy directly

---

## Step 5 - Manual connectivity sanity check (optional but recommended)

Before running real `bsub` tests, confirm the deployed script's exact configuration
works with a manual call:

```bash
curl -s -k --cacert <cacert_path> \
  -H "Content-type: application/json" \
  -H "Authorization: <token>" \
  -X POST https://<predictor-host>:<port>/api/predictions/<profile_name> \
  -d '{
    "model": "<model_name>",
    "input_data": {
      "fields": ["run_time", "project_name", "job_name", "queue_name", "user_name"],
      "values": [[60, "testproj", "testjob", "normal", "testuser"]]
    }
  }'
```

Confirm this returns a real `"y"` value, not an error.

---

## Step 6 - Live bsub tests across all tiers

Using the profile's real predicted value for a representative job (from Step 3 or
Step 5) as your baseline, submit test jobs spanning each tier. Replace `<predicted>`
below with that real number, and use your calibrated threshold ratios (printed by the
wizard in Step 4) to pick values that fall clearly within each zone.

```bash
# Reasonable range - expect: silent, no message, no adjustment
bsub -a "<esub_method_name>" -q <queue> -R "rusage[mem=<predicted>]" -J test_reasonable "sleep 60"

# Moderate under-request - expect: warn only, request preserved
bsub -a "<esub_method_name>" -q <queue> -R "rusage[mem=<value just past your moderate_low threshold>]" -J test_moderate_low "sleep 60"

# Extreme under-request - expect: auto-adjust up, notify
bsub -a "<esub_method_name>" -q <queue> -R "rusage[mem=<value well past your extreme_low threshold>]" -J test_extreme_low "sleep 60"

# Moderate over-request - expect: warn only, request preserved
bsub -a "<esub_method_name>" -q <queue> -R "rusage[mem=<value just past your moderate_high threshold>]" -J test_moderate_high "sleep 60"

# Extreme over-request - expect: auto-adjust down, notify
bsub -a "<esub_method_name>" -q <queue> -R "rusage[mem=<value well past your extreme_high threshold>]" -J test_extreme_high "sleep 60"
```

For each submission:
1. Confirm the `[predictor]` message (or absence of one) matches what's expected
   for that tier.
2. Check the actual applied value:
   ```bash
   bjobs -l <job_id>
   ```
   Look at the `Effective` resource requirement line to confirm any adjustment
   was actually applied to the job, not just printed as a message.

---

## Step 7 - Fail-open check

Temporarily point the script at an unreachable host/port (or stop the predictor
service), then submit a job:

```bash
bsub -a "<esub_method_name>" -q <queue> -R "rusage[mem=4096]" -J test_failopen "sleep 60"
```

Confirm the job still submits successfully with the original request unchanged, and
that a `[predictor]` message indicates the predictor was unavailable rather than
silently failing or blocking submission.

Restore the correct configuration afterward.

---

## Step 8 - Compare calibrated vs. generic thresholds, and check performance

Run the combined comparison/performance test:

```bash
python3 compare_and_perf_test.py \
    --csv ./<profile_name>.csv \
    --api-url https://<predictor-host>:<port> \
    --profile <profile_name> \
    --model <model_name> \
    --cacert <cacert_path> \
    --token "<token>" \
    --sample-size 1000
```

Larger samples give more stable results - in our own testing, a 300-sample and a
3000-sample run agreed closely (32% classification change in both), but a much
smaller wizard-calibration run (n=100) produced a visibly unstable threshold ratio
on the same model (see Step 4 note above). 1000 is a reasonable middle ground
between speed and stability for this step.

Review:
- **Performance**: mean/median/p90/p99/max latency, checked against the esub
  script's `CURL_TIMEOUT`. In our own testing (3000-sample run) this was
  consistently 28-49ms, far below the 3000ms default timeout, and closely matched
  an earlier smaller run - a good sign of stable, predictable performance.
- **Comparison**: how many jobs (and what percentage) would be classified
  differently under generic defaults vs. your calibrated values. In our own testing
  this was consistently about a third of all jobs across both a 300- and 3000-sample
  run - useful, concrete evidence for whether calibration is worth the extra setup
  step for your own model.

Note: update the script's `conservative_calibrated` config values (near the top of
the file) to match your own wizard-calibrated numbers before running, so the
comparison reflects what's actually deployed.

---

## Step 9 - Record results

For your own reference (and to share with others reviewing this work), note:

- Profile/model tested, and cluster it corresponds to
- Accuracy validation results (Step 3): sample size, mean/median/p75/p90 error, and
  whether error was concentrated in specific projects/queues
- Calibrated threshold values used (from Step 4), and whether they were accepted
  as-is or manually overridden
- Results of each Step 6 test case (expected vs. actual behavior)
- Performance and comparison results (Step 8)
- Any anomalies, failures, or unexpected behavior encountered
