# LSF Predictor-Assisted Memory Validation

## Introduction

This add-on uses your existing **LSF Cognitive Predictor** model to catch unreasonable
memory requests at job submission time. When a user submits a job, this feature
checks the request (or lack of one) against the predictor's estimate of what the job
will actually need, and:

- **Leaves reasonable requests alone** - no interruption, no message.
- **Warns (but does not block)** requests that look moderately off - preserving
  flexibility for legitimate cases like intentional testing or experimentation.
- **Automatically corrects** requests that are extremely off in either direction -
  preventing likely out-of-memory (OOM) job failures on the low end, and reducing
  wasted cluster capacity on the high end.
- **Recommends a value** when no memory request was specified at all - the most
  common real-world submission pattern.

This is implemented as an **esub script** - a hook that LSF runs automatically at job
submission time, on the submission host, before a job is handed to the scheduler. It
does not modify LSF's core scheduler, the predictor's model, or its GUI - it is a
self-contained add-on that calls your existing predictor API as-is.

A setup wizard is included that can **automatically calibrate the sensitivity
thresholds by analyzing your specific model's real prediction accuracy**, rather than
relying on generic guessed values - see "Threshold calibration" below.

## What this is NOT

- It does not train or modify any prediction model. It only *consumes* an existing,
  already-trained prediction profile.
- It does not require any changes to LSF core or the predictor backend.
- It does not currently support interactive prompts - LSF's `esub` mechanism runs
  non-interactively and exits quickly, so this always resolves automatically to one
  of: no action, a warning, an automatic correction, or a recommendation.

## Prerequisites

Before setting this up, confirm you have all of the following:

1. **A running LSF Cognitive Predictor instance**, reachable over HTTPS from the LSF
   submission host(s) where this will be deployed.

2. **A real, completed prediction profile** trained on your cluster's actual workload
   history - not the sample/demo model. Check via the predictor GUI's Prediction tab,
   or `GET /api/predictions`, and confirm:
   - The profile's `state` is `completed` (not `Loading` or `failed`).
   - Its `label` is the value you want to validate against (e.g. `max_mem`).
   - Its `features` are: `run_time`, `project_name`, `job_name`, `queue_name`,
     `user_name`. (If your profile uses different features, the generated esub
     script's request payload will need to be adjusted accordingly.)

3. **Login credentials for the predictor's web application** (not to be confused with
   any CPD/WML credentials used internally by the predictor to train models). This is
   whatever account you use to log into the predictor's web console.

4. **The predictor's TLS certificate file**, accessible at a known path on the host
   where you'll run setup (commonly generated as part of the predictor's own startup
   process, e.g. `config/https/cacert_lsf.pem`).

5. **Admin/sudo access on the LSF submission host(s)**, since deployment requires
   writing into a protected LSF directory (`$LSF_SERVERDIR`), and may involve an
   `lsadmin`/`badmin reconfig` if you choose to make this run automatically for all
   submissions (see "Automatic vs. opt-in invocation" below).

6. **(Strongly recommended) The profile's ground-truth training CSV**, so the setup
   wizard can auto-calibrate thresholds using your model's real accuracy. This is
   typically found inside the predictor's container at
   `/opt/ibm/prediction/work/predictions/<profile>/<profile>.csv` and can be copied
   out with `docker cp`. If you skip this, the wizard falls back to generic
   starting-point ratios that are not derived from any real accuracy data.

## Quick start

1. Locate `setup_esub_predictor_memcheck.sh` (bundled alongside this README in the
   deployment package).

2. (Recommended) Copy your profile's ground-truth CSV out of the predictor container
   so the wizard can find it:
   ```bash
   docker cp <predictor_container>:/opt/ibm/prediction/work/predictions/<profile>/<profile>.csv ./<profile>.csv
   ```

3. Run the wizard:
   ```bash
   sh setup_esub_predictor_memcheck.sh
   ```

4. Follow the interactive prompts. You will be asked for:
   - The predictor's URL and cert path
   - Your predictor login (used once, to obtain an access token - not stored)
   - The prediction profile/model name to validate against (it will be tested live
     before continuing, so you'll know immediately if something's misconfigured).
     **The generated script and its `-a` method name are automatically derived from
     the model name you enter here** (e.g. model `sample_model_max_mem` produces
     `esub.sample_model_max_mem_memcheck`).
   - Whether to auto-calibrate thresholds (see below) - if you have the CSV from
     step 2, answer yes here
   - Threshold values (press Enter at each prompt to accept the shown default -
     your live-calibrated value, if you chose to calibrate)
   - Where to write the log file (see "Logging" below)

5. At the end, the wizard will attempt to auto-detect your LSF server directory and
   offer to deploy the generated script for you. Confirm with `y` if it looks correct.

6. Test it (the wizard prints the exact command to use, with your real method name
   filled in):
   ```bash
   bsub -a "<model_name>_memcheck" -q <your_queue> -R "rusage[mem=<some_value>]" -J test_job "sleep 60"
   ```
   Submit at least one deliberately low and one deliberately high memory request
   relative to what you expect the predictor to estimate for that job type, and
   check the log file (see below) for the resulting messages.

## How the recommended memory value is calculated

This is the core logic admins should understand before relying on this feature. There
are two distinct situations, handled differently.

### Situation A: no memory request was specified at all

This is arguably the most common real-world case - many users don't specify `-M` or
`-R "rusage[mem=...]"` at all. When this happens, there's nothing to compare against,
so the script doesn't try to judge the user's choice - it simply **recommends a
value** based on the prediction, and applies it:

```
recommended_value = predicted_value + safety_buffer
```

Where `safety_buffer` is itself calculated as:

```
safety_buffer = max( BUFFER_MIN_MB, predicted_value x BUFFER_RATIO )
```

**In plain terms:** take the predictor's estimate, then add a cushion on top of it -
either a fixed minimum amount, or a percentage of the prediction, whichever is
larger. The percentage-based cushion keeps the buffer proportional for large jobs;
the fixed minimum keeps it meaningful for very small jobs where a percentage alone
would be negligible.

**Worked example**, using this feature's own tested defaults (`BUFFER_RATIO=0.2`,
`BUFFER_MIN_MB=100`) and a real predicted value of 3863MB:

```
safety_buffer = max( 100, 3863 x 0.2 ) = max( 100, 772.6 ) = 773 MB
recommended_value = 3863 + 773 = 4636 MB
```

The job's memory request is then set to `rusage[mem=4636]`, and a message noting the
prediction and the applied recommendation is written to the log.

If the resulting recommendation is still below the absolute floor `MIN_MEM_MB`
(default 250MB), it's raised to that floor instead - this guards against
nonsensically small recommendations for edge cases.

### Situation B: a memory request was specified - tiered comparison

When the user *does* specify a memory value, the script compares it against the
prediction using **four thresholds**, splitting the range around the predicted value
into five zones. Each threshold is calculated using the same **hybrid** approach as
the safety buffer above - the larger of a percentage-based gap or a fixed minimum
gap - which avoids two common failure modes of simpler approaches: a pure percentage
threshold is nearly meaningless for very small predictions (e.g. 3x a 1MB prediction
is still only 3MB), while a pure fixed threshold is far too tight or loose depending
on job size. This hybrid approach is modeled on the same pattern Kubernetes' Vertical
Pod Autoscaler uses for its own memory-bump recommendations.

**The four thresholds:**

```
moderate_low_gap  = max( MODERATE_LOW_MIN_MB,  predicted_value x MODERATE_LOW_RATIO )
extreme_low_gap   = max( EXTREME_LOW_MIN_MB,   predicted_value x EXTREME_LOW_RATIO )
moderate_high_gap = max( MODERATE_HIGH_MIN_MB, predicted_value x MODERATE_HIGH_RATIO )
extreme_high_gap  = max( EXTREME_HIGH_MIN_MB,  predicted_value x EXTREME_HIGH_RATIO )

moderate_low  = predicted_value - moderate_low_gap   (floored at 0)
extreme_low   = predicted_value - extreme_low_gap    (floored at 0)
moderate_high = predicted_value + moderate_high_gap
extreme_high  = predicted_value + extreme_high_gap
```

**The five zones, and what happens in each:**

```
             extreme_low       moderate_low       moderate_high      extreme_high
  AUTO-ADJUST UP  |    WARN ONLY     |    NO ACTION     |    WARN ONLY     | AUTO-ADJUST DOWN
                  |   (preserved)    | (predicted here) |   (preserved)    |
```

| Requested value falls... | Zone | Behavior |
|---|---|---|
| below `extreme_low` | Extreme under-request | Auto-adjust up to `predicted + safety_buffer`, log the change |
| between `extreme_low` and `moderate_low` | Moderate under-request | Log a warning; request left unchanged |
| between `moderate_low` and `moderate_high` | Reasonable range | No action, no log entry |
| between `moderate_high` and `extreme_high` | Moderate over-request | Log a warning; request left unchanged |
| above `extreme_high` | Extreme over-request | Auto-adjust down to `predicted + safety_buffer`, log the change |

Note that **both** auto-adjust cases converge on the same formula
(`predicted + safety_buffer`) - whether the original request was far too low or far
too high, the corrected value is the same "predicted value plus a sensible cushion,"
not simply the raw prediction with no margin.

**Worked example**, using this feature's own tested, live-calibrated values on a
real profile (`MODERATE_LOW_RATIO=MODERATE_HIGH_RATIO=0.19`,
`EXTREME_LOW_RATIO=EXTREME_HIGH_RATIO=0.84`, minimum gaps at their defaults, and a
predicted value of 3863MB):

```
moderate_low_gap  = max(200, 3863 x 0.19) = max(200, 734)  = 734
extreme_low_gap   = max(500, 3863 x 0.84) = max(500, 3245) = 3245
moderate_high_gap = max(300, 3863 x 0.19) = max(300, 734)  = 734
extreme_high_gap  = max(750, 3863 x 0.84) = max(750, 3245) = 3245

moderate_low  = 3863 - 734  = 3129
extreme_low   = 3863 - 3245 = 618
moderate_high = 3863 + 734  = 4597
extreme_high  = 3863 + 3245 = 7108
```

So for this specific job type: a request under 618MB gets auto-corrected up; a
request between 618-3129MB gets a warning; 3129-4597MB is left alone entirely;
4597-7108MB gets a warning; and anything above 7108MB gets auto-corrected down.

## Threshold calibration

The wizard offers to **auto-calibrate ratio thresholds by live-testing your model's
prediction accuracy** against its own ground-truth training data, rather than using
one-size-fits-all defaults. When enabled, it:

1. Samples a configurable number of rows from your profile's training CSV.
2. Calls the live prediction endpoint for each row.
3. Compares predicted vs. actual values and computes real error percentiles
   (median and p75).
4. Uses those percentiles as the default ratio values for the moderate/extreme
   thresholds (moderate near the median error, extreme near the p75 error).

**Why p75 rather than p90 for the extreme threshold:** in our own testing, using p90
left a meaningful share of genuinely poor predictions sitting in the "moderate"
(warn-only) zone rather than triggering auto-correction. p75 catches these while
still leaving clear headroom below the true worst-case (p90+) predictions.

**Example from our own testing** (Sample_Prediction profile, 1000-sample live
calibration): median error 19.45%, p75 error 83.65% - meaningfully different from
generic guessed defaults, and directly affecting real behavior. A side-by-side
comparison test on 3000 real jobs showed **32% of jobs received a different
classification** between generic defaults and these calibrated values - this result
was consistent between a 300-sample run and a larger 3000-sample run, confirming it
reflects a real, stable difference rather than sampling noise.

**A note on calibration sample size:** in our own testing, a small calibration
sample (n=100) on this same profile produced a p75 error of over 100%, versus ~84%
from a 1000-sample run on the same model. At that inflated ratio, the extreme-low
threshold computed to a negative value (floored at 0), meaning the "auto-adjust up"
branch could never trigger at all - every under-request, no matter how severe,
would only ever produce a warning. This happened because this particular model's
accuracy varies enormously by job segment (see "accuracy can vary significantly"
below), so a small sample can easily be skewed by a handful of high-error jobs from
one segment. **We recommend a calibration sample size of at least several hundred**
for models with this kind of accuracy variance, and suggest spot-checking the
resulting ratios (e.g. via `validate_predictor_accuracy.py` with a larger sample)
if a wizard run used a small sample size.

**Important - accuracy can vary significantly within a single model.** In our
testing, prediction accuracy varied dramatically depending on the combination of
`project_name` and `queue_name` for a given job - some segments had error
consistently under 5%, while others had error consistently over 200%, with
`project_name` being the dominant factor and `queue_name` a secondary, compounding
one. A single global threshold is therefore a **compromise**: reasonably safe
overall, but not optimally tuned for every segment of your workload. See "Known
limitations" below.

If you skip calibration (or it fails, e.g. due to missing CSV or connectivity
issues), the wizard falls back to generic starting-point ratios (moderate=0.2,
extreme=0.5) that are not derived from any real accuracy data - treat these as
placeholders only.

## Performance

In our own testing against a live predictor instance (3000 sequential prediction
calls), latency was:

| Metric | Value |
|---|---|
| Mean | 28 ms |
| Median (p50) | 29 ms |
| p90 | 33 ms |
| p99 | 39 ms |
| Max | 49 ms |

All well within the script's default 3000ms timeout, confirming that local-model
scoring (no live external ML platform call at inference time) keeps this fast enough
for synchronous use inside `esub` without noticeable submission delay. This result
was consistent with an earlier, smaller 300-call run (mean 26ms, max 69ms),
indicating stable, predictable performance rather than sample-size noise.

## Logging

All `[predictor]` messages (warnings, auto-adjustments, recommendations, and
fail-open notices) are written to a **log file only** - never to `bsub`'s own
stdout/stderr - so job submission output stays completely clean for any tooling that
parses it. The log file path is set during wizard setup (default:
`/tmp/esub_predictor_memcheck.log`) and stored in the generated script's `LOG_FILE`
variable. Each entry is timestamped, e.g.:

```
2026-07-15 13:45:07 [predictor] Requested memory (900MB) is far below predicted need (3863MB).
2026-07-15 13:45:07 [predictor] Adjusting memory request to 4636MB to prevent likely OOM kill.
```

Check this file directly to see what the script has been doing:
```bash
tail -f <your LOG_FILE path>
```

## Automatic vs. opt-in invocation

By default, this esub script only runs when a job is submitted with the application
profile flag explicitly specified, using the method name derived from your model
name at setup time:

```bash
bsub -a "<model_name>_memcheck" ...
```

If you want this to run automatically for **every** submission on a queue (without
requiring users to remember the flag), that requires a separate LSF configuration
step - setting `LSB_ESUB_METHOD` (globally in `lsf.conf`, or per-queue in
`lsb.queues`) to include this method name, followed by `lsadmin reconfig` and
`badmin reconfig`. This is a cluster-wide configuration change and should be made
with your LSF cluster administrator's involvement.

## Fail-safe behavior

This script is designed to **fail open**: if the predictor is unreachable, returns an
error, or the response can't be parsed, the job is submitted with the user's original
request, unchanged, with no interruption. It will never block a job submission due to
predictor unavailability. Fail-open events are still recorded in the log file, so you
can distinguish "predictor unavailable" periods from normal operation.

## Additional tools included

- **`validate_predictor_accuracy.py`** - standalone script to compute real accuracy
  statistics (mean/median/p15/p75/p90/max error) from a profile's training CSV,
  independent of the setup wizard. Useful for investigating a model's accuracy before
  deciding whether to deploy this feature at all.
- **`analyze_error_by_group.py`** - breaks down prediction error by `queue_name` /
  `project_name` (or any other CSV columns), to identify whether accuracy problems
  are concentrated in specific segments of your workload rather than spread evenly.
- **`compare_and_perf_test.py`** - runs a single live sample against your predictor
  and uses it both to compare two threshold configurations side-by-side (how many
  jobs would be classified differently) and to measure real call latency.

## Known limitations

- **Single global threshold per profile**: as noted above, if your model's accuracy
  varies significantly by segment (project, queue, etc.), one global ratio is a
  compromise, not an optimal fit for every segment. Per-segment thresholds are a
  planned future enhancement, not currently implemented.
- **Memory unit parsing**: only plain numeric MB values in `rusage[mem=...]` (e.g.
  `mem=4096`) are correctly parsed today. Values using unit suffixes (e.g. `mem=4G`)
  are not yet normalized and may be misinterpreted - avoid unit suffixes until this
  is addressed.
- **Token lifetime**: the embedded authentication token is short-lived (commonly
  ~1 day). Re-run the setup wizard periodically to refresh it and redeploy.
- **No per-cluster profile auto-resolution**: the target prediction profile/model
  name is fixed at setup time. If you operate multiple clusters with different
  trained models, you'll need to run setup separately for each.
- **Calibration uses training data, not a confirmed held-out test set**: the CSV
  used for calibration is the model's training data; a portion may have been held
  out during training, but which rows isn't visible to this tooling. True
  out-of-sample accuracy may be somewhat worse than what calibration shows.

## Getting help / reporting issues

Please contact Randy Yang or George Gao on the LSF dev team.
