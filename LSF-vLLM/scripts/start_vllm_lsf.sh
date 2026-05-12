#!/usr/bin/env bash
set -Eeuo pipefail

MODEL="${MODEL:-Qwen/Qwen3-0.6B}"
PORT="${PORT:-8001}"
API_KEY="${API_KEY:-local-vllm-key}"
IMAGE="${IMAGE:-docker.io/vllm/vllm-openai-cpu:latest-x86_64}"

BASE="${HOME}/lsf_vllm_poc"
CACHE_DIR="${BASE}/cache"
REG_DIR="${BASE}/registry"
LOG_DIR="${BASE}/logs"
CONTAINER_NAME="vllm-job-${LSB_JOBID:-manual}"

mkdir -p "${CACHE_DIR}" "${REG_DIR}" "${LOG_DIR}"

echo "Starting vLLM service wrapper..."
echo "MODEL=${MODEL}"
echo "PORT=${PORT}"
echo "JOBID=${LSB_JOBID:-manual}"
echo "CONTAINER_NAME=${CONTAINER_NAME}"

cleanup() {
  echo "Cleaning up container ${CONTAINER_NAME}"
  podman stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

HF_ENV=()
if [[ -n "${HF_TOKEN:-}" ]]; then
  HF_ENV=(-e "HF_TOKEN=${HF_TOKEN}")
fi

podman run -d \
  --name "${CONTAINER_NAME}" \
  -p "${PORT}:8000" \
  -v "${CACHE_DIR}:/root/.cache/huggingface:Z" \
  -e HF_HOME=/root/.cache/huggingface \
  -e VLLM_CPU_KVCACHE_SPACE=6 \
  -e VLLM_CPU_NUM_OF_RESERVED_CPU=1 \
  --security-opt seccomp=unconfined \
  --cap-add SYS_NICE \
  --shm-size=4g \
  "${HF_ENV[@]}" \
  "${IMAGE}" \
  "${MODEL}" \
  --dtype=bfloat16 \
  --max-model-len 32768 \
  --api-key "${API_KEY}" >/dev/null

HOST_FQDN="$(hostname -f)"
export MODEL PORT API_KEY HOST_FQDN

echo "Waiting for service readiness..."
READY=0
for i in $(seq 1 240); do
  if curl -fsS "http://127.0.0.1:${PORT}/v1/models" \
      -H "Authorization: Bearer ${API_KEY}" >/dev/null 2>&1; then
    READY=1
    break
  fi
  if (( i % 10 == 0 )); then
    echo "Still waiting... iteration=${i}"
  fi
  sleep 5
done

if [[ "${READY}" != "1" ]]; then
  echo "vLLM did not become ready in time"
  podman logs "${CONTAINER_NAME}" || true
  exit 1
fi

echo "Service is ready. Writing registry file..."

python3 - <<'PY'
import json, os
jobid = os.environ.get("LSB_JOBID", "manual")
doc = {
    "jobid": jobid,
    "service_name": "qwen-chat",
    "model": os.environ["MODEL"],
    "host": os.environ["HOST_FQDN"],
    "port": int(os.environ["PORT"]),
    "api_key": os.environ["API_KEY"],
    "status": "ready",
}
path = os.path.expanduser(f"~/lsf_vllm_poc/registry/{jobid}.json")
with open(path, "w") as f:
    json.dump(doc, f, indent=2)
print(f"registry written: {path}")
print(f"endpoint: http://{doc['host']}:{doc['port']}/v1")
PY

echo "Streaming container logs..."
podman logs -f "${CONTAINER_NAME}"
