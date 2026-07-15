#!/bin/sh
#
# setup_esub_predictor_memcheck.sh
#
# Interactive setup wizard for the LSF Predictor-Assisted Memory Validation esub script.
#
# This script prompts an LSF administrator for the predictor connection details,
# authenticates on their behalf, lets them customize (or accept defaults for) the
# tiered threshold values, and generates a ready-to-deploy esub script.
#
# This wizard is intended to be run interactively by a human administrator ONCE
# during setup. It is separate from the generated esub script itself, which must
# remain non-interactive since it is invoked automatically by LSF on every bsub call.

# Note: we deliberately do NOT use `set -e` here. This wizard makes several
# external calls (curl to the predictor) that can legitimately fail (bad
# host, bad credentials, network issues), and each of those is already
# checked explicitly below with its own clear error message. `set -e` would
# cause the script to exit silently and abruptly on the first curl failure,
# before our own error handling ever runs.

TEMPLATE_MARKER_START="# --- GENERATED CONFIGURATION START ---"
TEMPLATE_MARKER_END="# --- GENERATED CONFIGURATION END ---"

echo "==================================================================="
echo " LSF Predictor-Assisted Memory Validation - Setup Wizard"
echo "==================================================================="
echo ""
echo "This will generate a ready-to-deploy esub script configured for your"
echo "predictor instance. Press Enter at any prompt to accept the shown"
echo "default value."
echo ""

prompt_with_default() {
    # $1 = prompt text, $2 = default value
    # Echoes the final value (input, or default if input was empty)
    _prompt="$1"
    _default="$2"
    printf "%s [%s]: " "$_prompt" "$_default" >&2
    read -r _input
    if [ -z "$_input" ]; then
        echo "$_default"
    else
        echo "$_input"
    fi
}

prompt_required() {
    # $1 = prompt text - loops until a non-empty value is given
    _prompt="$1"
    _input=""
    while [ -z "$_input" ]; do
        printf "%s: " "$_prompt" >&2
        read -r _input
        if [ -z "$_input" ]; then
            echo "  (this value is required)" >&2
        fi
    done
    echo "$_input"
}

prompt_password() {
    _prompt="$1"
    printf "%s: " "$_prompt" >&2
    stty -echo 2>/dev/null || true
    read -r _input
    stty echo 2>/dev/null || true
    echo "" >&2
    echo "$_input"
}

is_valid_number() {
    # Accepts positive or negative integers/decimals, e.g. 0.2, 200, 3.0
    # Returns 0 (true) if valid, 1 (false) otherwise - POSIX-compatible, no bashisms
    case "$1" in
        ''|*[!0-9.-]*) return 1 ;;   # contains something other than digits/./-
        *.*.*) return 1 ;;            # more than one decimal point
        *) return 0 ;;
    esac
}

prompt_number_with_default() {
    # $1 = prompt text, $2 = default value - loops until a valid number is entered
    _prompt="$1"
    _default="$2"
    while true; do
        printf "%s [%s]: " "$_prompt" "$_default" >&2
        read -r _input
        if [ -z "$_input" ]; then
            echo "$_default"
            return
        fi
        if is_valid_number "$_input"; then
            echo "$_input"
            return
        fi
        echo "  '$_input' doesn't look like a valid number. Please enter a number (e.g. 0.2 or 200)." >&2
    done
}

# --- Step 1: Connection details ---------------------------------------------

echo "--- Step 1: Predictor connection ---"
API_URL=$(prompt_required "Predictor base URL (e.g. https://host:5050)")
CACERT=$(prompt_required "Absolute path to the predictor's TLS cert file")

if [ ! -f "$CACERT" ]; then
    echo ""
    echo "WARNING: no file found at '$CACERT'. Continuing anyway, but the"
    echo "generated script will fail its health check until this is fixed."
    echo ""
fi

# --- Step 2: Authenticate ----------------------------------------------------

echo ""
echo "--- Step 2: Predictor login ---"
echo "These credentials are used once, now, to obtain an access token."
echo "They are NOT stored in the generated script - only the resulting token is."
echo ""

LOGIN_NAME=$(prompt_required "Predictor login username")
LOGIN_PASSWORD=$(prompt_password "Predictor login password")

echo ""
echo "Requesting token from ${API_URL}/api/login ..."

LOGIN_RESPONSE=$(curl -s -k --cacert "$CACERT" -X POST "${API_URL}/api/login" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${LOGIN_NAME}\",\"password\":\"${LOGIN_PASSWORD}\"}" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    token = data.get('token')
    if token:
        print(token)
except Exception:
    pass
" 2>/dev/null)

if [ -z "$AUTH_TOKEN" ]; then
    echo ""
    echo "ERROR: could not obtain an auth token. Raw response was:"
    echo "$LOGIN_RESPONSE"
    echo ""
    echo "Common causes: wrong username/password, wrong CACERT path, or the"
    echo "predictor service is unreachable at $API_URL."
    exit 1
fi

echo "Login succeeded. Token obtained (not displayed)."
echo ""
echo "NOTE: this token is short-lived by default (commonly ~1 day)."
echo "It will need to be regenerated periodically by re-running this wizard,"
echo "unless a longer-lived service-account token is minted separately."

# --- Step 3: Predictor profile/model -----------------------------------------

echo ""
echo "--- Step 3: Prediction profile ---"

PREDICTOR_PROFILE=$(prompt_with_default "Predictor profile name" "Sample_Prediction")
PREDICTOR_MODEL=$(prompt_with_default "Model name within that profile" "sample_model_max_mem")

OUTPUT_NAME="esub.${PREDICTOR_MODEL}_memcheck"

echo ""
echo "Verifying profile is reachable..."

VERIFY_RESPONSE=$(curl -s -k --cacert "$CACERT" \
    -H "Content-type: application/json" \
    -H "Authorization: ${AUTH_TOKEN}" \
    -X POST "${API_URL}/api/predictions/${PREDICTOR_PROFILE}" \
    -d "{\"model\":\"${PREDICTOR_MODEL}\",\"input_data\":{\"fields\":[\"run_time\",\"project_name\",\"job_name\",\"queue_name\",\"user_name\"],\"values\":[[60,\"setup_test\",\"setup_test\",\"normal\",\"setup\"]]}}" \
    2>/dev/null)

TEST_PREDICTION=$(echo "$VERIFY_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    y = data.get('data', {}).get('y', [None])[0]
    if y is not None:
        print(y)
except Exception:
    pass
" 2>/dev/null)

if [ -z "$TEST_PREDICTION" ]; then
    echo ""
    echo "WARNING: test prediction call did not return a usable value."
    echo "Raw response was:"
    echo "$VERIFY_RESPONSE"
    echo ""
    echo "Continuing setup, but verify the profile/model names before deploying."
else
    echo "Profile verified - test prediction returned: ${TEST_PREDICTION}MB"
fi

# --- Step 4: Threshold configuration ------------------------------------------

echo ""
echo "--- Step 4: Threshold configuration ---"
echo "These control when a memory request is considered moderately vs. extremely"
echo "off from the predicted value, using a hybrid ratio + absolute-floor"
echo "mechanism (modeled on Kubernetes VPA's OOM-bump formula)."
echo ""

# Generic, dataset-independent starting points - used only if the admin
# declines live calibration, or if calibration fails for any reason.
GENERIC_MODERATE_RATIO="0.2"
GENERIC_EXTREME_RATIO="0.5"

MODERATE_RATIO_DEFAULT="$GENERIC_MODERATE_RATIO"
EXTREME_RATIO_DEFAULT="$GENERIC_EXTREME_RATIO"

printf "Would you like to auto-calibrate the ratio thresholds by analyzing this\n"
printf "model's real prediction accuracy against its own training data? [y/N]: " >&2
read -r DO_CALIBRATE

case "$DO_CALIBRATE" in
    [yY]|[yY][eE][sS])
        echo ""
        DEFAULT_CSV_GUESS="./${PREDICTOR_PROFILE}.csv"
        CALIB_CSV=$(prompt_with_default "Path to this profile's ground-truth CSV" "$DEFAULT_CSV_GUESS")

        if [ ! -f "$CALIB_CSV" ]; then
            echo ""
            echo "WARNING: no file found at '$CALIB_CSV'."
            echo "(This is typically found inside the predictor's container at"
            echo "/opt/ibm/prediction/work/predictions/<profile>/<profile>.csv -"
            echo "copy it out first with 'docker cp', e.g.:"
            echo "  docker cp <container_name>:/opt/ibm/prediction/work/predictions/${PREDICTOR_PROFILE}/${PREDICTOR_PROFILE}.csv ./${PREDICTOR_PROFILE}.csv"
            echo ")"
            echo "Falling back to generic default ratios."
        else
            CALIB_SAMPLE_SIZE=$(prompt_number_with_default "Sample size for calibration (larger = slower but more reliable)" "500")

            echo ""
            echo "Running live calibration (this will make ${CALIB_SAMPLE_SIZE} prediction"
            echo "calls against your model - may take a minute)..."
            echo ""

            CALIB_OUTPUT=$(python3 - "$CALIB_CSV" "$API_URL" "$PREDICTOR_PROFILE" "$PREDICTOR_MODEL" "$CACERT" "$AUTH_TOKEN" "$CALIB_SAMPLE_SIZE" <<'PYEOF'
import csv, json, random, ssl, statistics, sys, urllib.request, urllib.error

csv_path, api_url, profile, model, cacert, token, sample_size = sys.argv[1:8]
sample_size = int(sample_size)

try:
    with open(csv_path, newline="") as f:
        rows = list(csv.DictReader(f))
except Exception as e:
    print(f"CALIBRATION_FAILED: could not read CSV: {e}", file=sys.stderr)
    sys.exit(1)

if not rows or "max_mem" not in rows[0]:
    print("CALIBRATION_FAILED: CSV missing or has no 'max_mem' column", file=sys.stderr)
    sys.exit(1)

sample = random.sample(rows, min(sample_size, len(rows)))

ctx = ssl.create_default_context(cafile=cacert)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

errors = []
for i, row in enumerate(sample, 1):
    try:
        actual = float(row.get("max_mem"))
    except (TypeError, ValueError):
        continue
    if actual == 0:
        continue

    try:
        run_time = int(float(row.get("run_time", 60)))
    except (TypeError, ValueError):
        run_time = 60

    payload = {
        "model": model,
        "input_data": {
            "fields": ["run_time", "project_name", "job_name", "queue_name", "user_name"],
            "values": [[run_time, row.get("project_name", ""), row.get("job_name", ""),
                        row.get("queue_name", ""), row.get("user_name", "")]]
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
            predicted = body.get("data", {}).get("y", [None])[0]
            if predicted is None:
                continue
            predicted = float(predicted)
    except Exception:
        continue

    errors.append(abs(predicted - actual) / actual * 100.0)

    if i % 25 == 0:
        print(f"  ...{i}/{len(sample)} processed", file=sys.stderr)

if len(errors) < 5:
    print(f"CALIBRATION_FAILED: only {len(errors)} successful comparisons - too few to calibrate from", file=sys.stderr)
    sys.exit(1)

errors_sorted = sorted(errors)

def percentile(data, pct):
    k = (len(data) - 1) * (pct / 100.0)
    f = int(k)
    c = min(f + 1, len(data) - 1)
    if f == c:
        return data[f]
    return data[f] + (data[c] - data[f]) * (k - f)

p50 = percentile(errors_sorted, 50)
p75 = percentile(errors_sorted, 75)

print(f"CALIBRATION_OK n={len(errors)} p50={p50:.2f} p75={p75:.2f}")
PYEOF
)
            CALIB_STATUS=$?

            echo "$CALIB_OUTPUT" | grep -v '^CALIBRATION_' >&2

            CALIB_RESULT_LINE=$(echo "$CALIB_OUTPUT" | grep '^CALIBRATION_OK')

            if [ "$CALIB_STATUS" -eq 0 ] && [ -n "$CALIB_RESULT_LINE" ]; then
                CALIB_N=$(echo "$CALIB_RESULT_LINE" | sed -n 's/.*n=\([0-9]*\).*/\1/p')
                CALIB_P50=$(echo "$CALIB_RESULT_LINE" | sed -n 's/.*p50=\([0-9.]*\).*/\1/p')
                CALIB_P75=$(echo "$CALIB_RESULT_LINE" | sed -n 's/.*p75=\([0-9.]*\).*/\1/p')

                MODERATE_RATIO_DEFAULT=$(awk -v p="$CALIB_P50" 'BEGIN{printf "%.2f", p/100}')
                EXTREME_RATIO_DEFAULT=$(awk -v p="$CALIB_P75" 'BEGIN{printf "%.2f", p/100}')

                echo ""
                echo "Calibration complete (n=${CALIB_N} successful comparisons)."
                echo "  Median error (p50): ${CALIB_P50}%  -> moderate ratio default: ${MODERATE_RATIO_DEFAULT}"
                echo "  p75 error:           ${CALIB_P75}%  -> extreme ratio default:  ${EXTREME_RATIO_DEFAULT}"
                echo ""
                echo "These will be used as the defaults below - press Enter to accept,"
                echo "or type a different value at each prompt to override."
            else
                echo ""
                echo "Calibration failed or returned too few results. Falling back to"
                echo "generic default ratios (${GENERIC_MODERATE_RATIO} / ${GENERIC_EXTREME_RATIO})."
            fi
        fi
        ;;
    *)
        echo "Skipping calibration - using generic default ratios."
        ;;
esac

echo ""

MODERATE_LOW_RATIO=$(prompt_number_with_default "Moderate under-request ratio" "$MODERATE_RATIO_DEFAULT")
MODERATE_LOW_MIN_MB=$(prompt_number_with_default "Moderate under-request minimum gap (MB)" "200")

EXTREME_LOW_RATIO=$(prompt_number_with_default "Extreme under-request ratio" "$EXTREME_RATIO_DEFAULT")
EXTREME_LOW_MIN_MB=$(prompt_number_with_default "Extreme under-request minimum gap (MB)" "500")

MODERATE_HIGH_RATIO=$(prompt_number_with_default "Moderate over-request ratio" "$MODERATE_RATIO_DEFAULT")
MODERATE_HIGH_MIN_MB=$(prompt_number_with_default "Moderate over-request minimum gap (MB)" "300")

EXTREME_HIGH_RATIO=$(prompt_number_with_default "Extreme over-request ratio" "$EXTREME_RATIO_DEFAULT")
EXTREME_HIGH_MIN_MB=$(prompt_number_with_default "Extreme over-request minimum gap (MB)" "750")

BUFFER_RATIO=$(prompt_number_with_default "Adjustment safety buffer ratio" "0.2")
BUFFER_MIN_MB=$(prompt_number_with_default "Adjustment safety buffer minimum (MB)" "100")

MIN_MEM_MB=$(prompt_number_with_default "Absolute minimum memory floor after adjustment (MB)" "250")

CURL_TIMEOUT=$(prompt_number_with_default "Curl timeout for predictor calls (seconds)" "3")

echo ""
echo "--- Logging ---"
echo "All [predictor] messages (warnings, adjustments, fail-open notices) are"
echo "written to a log file - bsub's own output stays completely clean for any"
echo "tooling that parses it."
echo ""

LOG_FILE=$(prompt_with_default "Log file path" "/tmp/esub_predictor_memcheck.log")

# --- Step 5: Generate the script ----------------------------------------------

echo ""
echo "--- Step 5: Generating script ---"

OUTPUT_PATH="./${OUTPUT_NAME}"

cat > "$OUTPUT_PATH" <<SCRIPT_EOF
#!/bin/sh
#
# ${OUTPUT_NAME}
#
# Validates user-specified memory limit (-M / rusage[mem=...]) against the
# LSF Cognitive Predictor's max_mem regression estimate.
#
# Generated by setup_esub_predictor_memcheck.sh on $(date)
#
# Tiered behavior:
#   - Mild deviation      -> pass through unchanged, no message
#   - Moderate deviation  -> warn via stderr, pass through unchanged
#   - Extreme deviation   -> auto-adjust the memory value, notify via stderr
#
# Fails open: any predictor unavailability / error results in unchanged
# submission (no blocking, no adjustment).

${TEMPLATE_MARKER_START}
API_URL="${API_URL}"
PREDICTOR_PROFILE="${PREDICTOR_PROFILE}"
PREDICTOR_MODEL="${PREDICTOR_MODEL}"
CACERT="${CACERT}"
AUTH_TOKEN="${AUTH_TOKEN}"

CURL_TIMEOUT=${CURL_TIMEOUT}

MODERATE_LOW_RATIO=${MODERATE_LOW_RATIO}
MODERATE_LOW_MIN_MB=${MODERATE_LOW_MIN_MB}
EXTREME_LOW_RATIO=${EXTREME_LOW_RATIO}
EXTREME_LOW_MIN_MB=${EXTREME_LOW_MIN_MB}
MODERATE_HIGH_RATIO=${MODERATE_HIGH_RATIO}
MODERATE_HIGH_MIN_MB=${MODERATE_HIGH_MIN_MB}
EXTREME_HIGH_RATIO=${EXTREME_HIGH_RATIO}
EXTREME_HIGH_MIN_MB=${EXTREME_HIGH_MIN_MB}
BUFFER_RATIO=${BUFFER_RATIO}
BUFFER_MIN_MB=${BUFFER_MIN_MB}
MIN_MEM_MB=${MIN_MEM_MB}
LOG_FILE="${LOG_FILE}"
${TEMPLATE_MARKER_END}

# --- Helpers ------------------------------------------------------------
# All [predictor] messages are written to LOG_FILE only - bsub's own
# stdout/stderr output stays completely clean for tooling that parses it.

log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [predictor] \$1" >> "\$LOG_FILE" 2>/dev/null
}

fail_open() {
    log "Predictor unavailable or errored (\$1); submitting with original request."
    exit 0
}

# --- Source submission parameters ---------------------------------------

if [ -z "\$LSB_SUB_PARM_FILE" ] || [ ! -f "\$LSB_SUB_PARM_FILE" ]; then
    fail_open "missing LSB_SUB_PARM_FILE"
fi
. "\$LSB_SUB_PARM_FILE"

# --- Health check ---------------------------------------------------------

health_response=\$(curl -s -k -m "\$CURL_TIMEOUT" --cacert "\$CACERT" \\
    "\${API_URL}/api/system/info" 2>/dev/null)

if [ -z "\$health_response" ]; then
    fail_open "health check failed (no response from /api/system/info)"
fi

# --- Extract requested memory from LSB_SUB_RES_REQ (may be empty) --------
# Note: we no longer skip validation when no memory was specified. Instead,
# if nothing was requested, we still consult the predictor and populate a
# recommended value - this is the most common real-world submission case
# (many users don't specify -M at all) and arguably the highest-value case
# to assist with, rather than silently doing nothing.

requested_mem_raw=""
if [ -n "\$LSB_SUB_RES_REQ" ]; then
    requested_mem_raw=\$(echo "\$LSB_SUB_RES_REQ" | sed -n 's/.*mem=\([0-9]*\).*/\1/p')
fi

# --- Build request body ---------------------------------------------------

user=\$(id | awk 'BEGIN { FS="("} { print \$2}' | awk 'BEGIN { FS=")"} {print \$1}')
project="\$LSB_SUB_PROJECT_NAME"
queue="\$LSB_SUB_QUEUE"
job_name="\$LSB_SUB_JOB_NAME"
run_time=60

payload=\$(cat <<EOF
{
  "model": "\${PREDICTOR_MODEL}",
  "input_data": {
    "fields": ["run_time", "project_name", "job_name", "queue_name", "user_name"],
    "values": [[\${run_time}, "\${project}", "\${job_name}", "\${queue}", "\${user}"]]
  }
}
EOF
)

# --- Call predictor --------------------------------------------------------

response=\$(curl -s -k -m "\$CURL_TIMEOUT" --cacert "\$CACERT" \\
    -H "Content-type: application/json" \\
    -H "Authorization: \${AUTH_TOKEN}" \\
    -X POST "\${API_URL}/api/predictions/\${PREDICTOR_PROFILE}" \\
    -d "\$payload" 2>/dev/null)

if [ -z "\$response" ]; then
    fail_open "no response from prediction endpoint"
fi

predicted_mem=\$(echo "\$response" | \\
    awk 'BEGIN{RS=EOF}{gsub(/\n/,""); gsub(" ","");
        idx="\"y\":[";
        start=index(\$0, idx);
        if (start == 0) { exit 1 }
        rest=substr(\$0, start+length(idx));
        endidx=index(rest, "]");
        print substr(rest, 1, endidx-1);
    }')

if [ -z "\$predicted_mem" ]; then
    fail_open "could not parse prediction response"
fi

predicted_mem_int=\${predicted_mem%%.*}

if [ -z "\$predicted_mem_int" ]; then
    fail_open "non-numeric prediction value"
fi

safety_buffer=\$(awk -v p="\$predicted_mem_int" -v r="\$BUFFER_RATIO" -v m="\$BUFFER_MIN_MB" \\
    'BEGIN{ratio_val = p*r; printf "%d", (ratio_val > m) ? ratio_val : m}')

adjusted_mem_int=""

# --- Case 1: no memory request specified at all - recommend one ------------

if [ -z "\$requested_mem_raw" ]; then
    adjusted_mem_int=\$(awk -v p="\$predicted_mem_int" -v b="\$safety_buffer" 'BEGIN{printf "%d", p+b}')

    if [ "\$adjusted_mem_int" -lt "\$MIN_MEM_MB" ]; then
        adjusted_mem_int=\$MIN_MEM_MB
    fi

    log "No memory request specified. Predicted need: \${predicted_mem_int}MB."
    log "Applying recommended memory request: \${adjusted_mem_int}MB."

    if [ -n "\$LSB_SUB_RES_REQ" ]; then
        # A res_req exists but has no mem= clause - append one rather than
        # trying to rewrite an unknown existing resource string in place.
        new_res_req="\${LSB_SUB_RES_REQ} rusage[mem=\${adjusted_mem_int}]"
    else
        new_res_req="rusage[mem=\${adjusted_mem_int}]"
    fi

    echo "LSB_SUB_RES_REQ=\"\${new_res_req}\"" >> "\$LSB_SUB_MODIFY_FILE"
    exit 0
fi

# --- Case 2: a memory request was specified - run tiered comparison --------

requested_mem_int=\${requested_mem_raw%%.*}

if [ -z "\$requested_mem_int" ]; then
    fail_open "non-numeric requested value"
fi

# --- Compute thresholds using hybrid gap = max(fixed_min, ratio*predicted) ---

moderate_low_gap=\$(awk -v p="\$predicted_mem_int" -v r="\$MODERATE_LOW_RATIO" -v m="\$MODERATE_LOW_MIN_MB" \\
    'BEGIN{ratio_val = p*r; printf "%d", (ratio_val > m) ? ratio_val : m}')
extreme_low_gap=\$(awk -v p="\$predicted_mem_int" -v r="\$EXTREME_LOW_RATIO" -v m="\$EXTREME_LOW_MIN_MB" \\
    'BEGIN{ratio_val = p*r; printf "%d", (ratio_val > m) ? ratio_val : m}')
moderate_high_gap=\$(awk -v p="\$predicted_mem_int" -v r="\$MODERATE_HIGH_RATIO" -v m="\$MODERATE_HIGH_MIN_MB" \\
    'BEGIN{ratio_val = p*r; printf "%d", (ratio_val > m) ? ratio_val : m}')
extreme_high_gap=\$(awk -v p="\$predicted_mem_int" -v r="\$EXTREME_HIGH_RATIO" -v m="\$EXTREME_HIGH_MIN_MB" \\
    'BEGIN{ratio_val = p*r; printf "%d", (ratio_val > m) ? ratio_val : m}')

moderate_low=\$(awk -v p="\$predicted_mem_int" -v g="\$moderate_low_gap" 'BEGIN{v=p-g; printf "%d", (v>0)?v:0}')
extreme_low=\$(awk -v p="\$predicted_mem_int" -v g="\$extreme_low_gap" 'BEGIN{v=p-g; printf "%d", (v>0)?v:0}')
moderate_high=\$(awk -v p="\$predicted_mem_int" -v g="\$moderate_high_gap" 'BEGIN{printf "%d", p+g}')
extreme_high=\$(awk -v p="\$predicted_mem_int" -v g="\$extreme_high_gap" 'BEGIN{printf "%d", p+g}')

# --- Tiered decision logic -------------------------------------------------

if [ "\$requested_mem_int" -lt "\$extreme_low" ]; then
    adjusted_mem_int=\$(awk -v p="\$predicted_mem_int" -v b="\$safety_buffer" 'BEGIN{printf "%d", p+b}')
    log "Requested memory (\${requested_mem_int}MB) is far below predicted need (\${predicted_mem_int}MB)."
    log "Adjusting memory request to \${adjusted_mem_int}MB to prevent likely OOM kill."

elif [ "\$requested_mem_int" -lt "\$moderate_low" ]; then
    log "Requested memory (\${requested_mem_int}MB) is below predicted need (\${predicted_mem_int}MB)."
    log "Job may be at risk of running out of memory. Original request preserved."

elif [ "\$requested_mem_int" -gt "\$extreme_high" ]; then
    adjusted_mem_int=\$(awk -v p="\$predicted_mem_int" -v b="\$safety_buffer" 'BEGIN{printf "%d", p+b}')
    log "Requested memory (\${requested_mem_int}MB) is far above predicted need (\${predicted_mem_int}MB)."
    log "Adjusting memory request to \${adjusted_mem_int}MB to reduce cluster resource waste."

elif [ "\$requested_mem_int" -gt "\$moderate_high" ]; then
    log "Requested memory (\${requested_mem_int}MB) is above predicted need (\${predicted_mem_int}MB)."
    log "This may be intentional (e.g. testing/experimentation). Original request preserved."

else
    exit 0
fi

# --- Apply adjustment if one was computed ---------------------------------

if [ -n "\$adjusted_mem_int" ]; then
    if [ "\$adjusted_mem_int" -lt "\$MIN_MEM_MB" ]; then
        adjusted_mem_int=\$MIN_MEM_MB
    fi

    new_res_req=\$(echo "\$LSB_SUB_RES_REQ" | sed "s/mem=[0-9]*[A-Za-z]*/mem=\${adjusted_mem_int}/")
    echo "LSB_SUB_RES_REQ=\"\${new_res_req}\"" >> "\$LSB_SUB_MODIFY_FILE"
fi

exit 0
SCRIPT_EOF

chmod +x "$OUTPUT_PATH"

echo ""
echo "==================================================================="
echo " Script generated: ${OUTPUT_PATH}"
echo "==================================================================="

# --- Step 6: Auto-detect LSF_SERVERDIR and offer to deploy directly ----------

echo ""
echo "--- Step 6: Deployment ---"

DETECTED_SERVERDIR="$LSF_SERVERDIR"

if [ -z "$DETECTED_SERVERDIR" ]; then
    echo "LSF_SERVERDIR is not currently set in this shell."
    echo "Attempting to locate an LSF profile to source..."

    for _candidate in \
        /opt/ibm/lsfsuite/lsf/conf/profile.lsf \
        /opt/ibm/lsf/conf/profile.lsf \
        /usr/share/lsf/conf/profile.lsf
    do
        if [ -f "$_candidate" ]; then
            echo "Found: $_candidate"
            # shellcheck disable=SC1090
            . "$_candidate" 2>/dev/null
            if [ -n "$LSF_SERVERDIR" ]; then
                DETECTED_SERVERDIR="$LSF_SERVERDIR"
                echo "LSF_SERVERDIR resolved to: $DETECTED_SERVERDIR"
                break
            fi
        fi
    done
fi

if [ -z "$DETECTED_SERVERDIR" ]; then
    echo ""
    echo "Could not auto-detect LSF_SERVERDIR."
    DETECTED_SERVERDIR=$(prompt_with_default "Enter the LSF server directory manually (or leave blank to skip deployment)" "")
fi

if [ -n "$DETECTED_SERVERDIR" ]; then
    echo ""
    echo "Detected/entered LSF_SERVERDIR: $DETECTED_SERVERDIR"

    if [ ! -d "$DETECTED_SERVERDIR" ]; then
        echo "WARNING: this directory does not appear to exist. Skipping auto-deploy."
        DETECTED_SERVERDIR=""
    fi
fi

DEPLOY_TARGET="${DETECTED_SERVERDIR}/${OUTPUT_NAME}"

if [ -n "$DETECTED_SERVERDIR" ]; then
    printf "Deploy the generated script to %s now? [y/N]: " "$DEPLOY_TARGET" >&2
    read -r DEPLOY_CONFIRM
    case "$DEPLOY_CONFIRM" in
        [yY]|[yY][eE][sS])
            echo ""
            echo "Note: this typically requires elevated privileges (sudo)."

            if sudo cp "$OUTPUT_PATH" "$DEPLOY_TARGET" 2>/tmp/deploy_err.log && \
               sudo chmod a+xr "$DEPLOY_TARGET" 2>>/tmp/deploy_err.log; then
                echo "Deployed successfully to: $DEPLOY_TARGET"
                DEPLOYED=1
            else
                echo "ERROR: deployment failed. Details:"
                cat /tmp/deploy_err.log 2>/dev/null
                echo ""
                echo "You can deploy manually with:"
                echo "    sudo cp ${OUTPUT_PATH} ${DEPLOY_TARGET}"
                echo "    sudo chmod a+xr ${DEPLOY_TARGET}"
                DEPLOYED=0
            fi
            rm -f /tmp/deploy_err.log 2>/dev/null
            ;;
        *)
            echo "Skipping auto-deploy."
            DEPLOYED=0
            ;;
    esac
else
    echo "Skipping auto-deploy (no valid LSF_SERVERDIR available)."
    DEPLOYED=0
fi

ESUB_METHOD_NAME="${OUTPUT_NAME#esub.}"

echo ""
echo "==================================================================="
echo " Setup complete!"
echo "==================================================================="
echo ""

if [ "$DEPLOYED" = "1" ]; then
    echo "The script is deployed and ready to test:"
    echo "    bsub -a \"${ESUB_METHOD_NAME}\" -q <queue> -R \"rusage[mem=<value>]\" -J test_job \"sleep 60\""
else
    echo "Generated: ${OUTPUT_PATH}"
    echo ""
    echo "Next steps:"
    echo "  1. Review the generated script if desired."
    echo "  2. Deploy it:"
    echo "       sudo cp ${OUTPUT_PATH} \$LSF_SERVERDIR/${OUTPUT_NAME}"
    echo "       sudo chmod a+xr \$LSF_SERVERDIR/${OUTPUT_NAME}"
    echo "  3. Test with:"
    echo "       bsub -a \"${ESUB_METHOD_NAME}\" -q <queue> -R \"rusage[mem=<value>]\" -J test_job \"sleep 60\""
fi

echo ""
echo "Reminder: check whether \$LSF_SERVERDIR is shared across your cluster"
echo "or local per-host. If it's local per-host, repeat deployment on every"
echo "host that should run this validation."
echo ""
echo "Note: the embedded auth token is short-lived. Re-run this wizard to"
echo "refresh it and regenerate the script when it expires."
echo ""
