IBM LSF for vLLM Persistent Inference Service
==========================================

Overview
--------
In this repository we demonstrate how to deploy a large-language model inference service on an LSF cluster using vLLM. The service exposes an OpenAI-compatible API. We show how various clients can use the model for interactive or batch inference.

What this implementation demonstrates
-------------------------------------
- IBM LSF launching and managing a persistent inference runtime as a service job
- vLLM exposing an OpenAI-compatible endpoint
- endpoint discovery through a small registry file written by the service job
- interactive validation using curl and Jupyter
- downstream reuse through a separate IBM LSF batch job

Repository layout
-----------------
- scripts/start_vllm_lsf.sh
  Starts the vLLM container, waits for readiness, writes the registry file, and keeps the
  service attached to the IBM LSF job lifecycle.
- scripts/resolve_endpoint.py
  Reads the registry file for a given IBM LSF job ID and prints the resolved base URL.
- scripts/batch_client.py
  Reads a prompt corpus and sends requests to the registered vLLM service.
- notebook/LSF_vLLM_Client.ipynb
  Jupyter notebook for interactive validation against the IBM LSF-managed runtime.
- corpus/prompts.txt
  Sample prompt corpus for downstream batch validation.

Prerequisites
-------------
- IBM LSF installed and operational
- podman installed
- python3 installed
- curl installed
- network access from the execution host to pull the vLLM image and model
- a single-node IBM LSF setup is sufficient for this implementation
- shared $HOME directory across the cluster

Note:
Replace "your-host" with the hostname or IP address of the system where the vLLM service is running.

The examples below assume you are running as the same user for all steps.

Get the repository and move into it
-----------------------------------

```bash
git clone https://github.com/IBMSpectrumComputing/lsf-integrations.git
cd lsf-integrations/LSF-vLLM
```
After this follow the instructions step by step given below. 

Part 1: Deploy the LLM
======================

Step 1: Create the working directories
--------------------------------------

```bash
mkdir -p ~/lsf_vllm_poc/{logs,registry,cache,corpus,results,notebook}
```

```bash
cp corpus/prompts.txt ~/lsf_vllm_poc/corpus/prompts.txt
```

```bash
cp scripts/start_vllm_lsf.sh ~/lsf_vllm_poc/
cp scripts/resolve_endpoint.py ~/lsf_vllm_poc/
cp scripts/batch_client.py ~/lsf_vllm_poc/
```

```bash
chmod +x ~/lsf_vllm_poc/start_vllm_lsf.sh
chmod +x ~/lsf_vllm_poc/resolve_endpoint.py
chmod +x ~/lsf_vllm_poc/batch_client.py
```

Step 2: Review the service script defaults
------------------------------------------

```bash
MODEL=Qwen/Qwen3-0.6B PORT=8001 API_KEY=local-vllm-key
```

NOTE : 
Default demo API key: local-vllm-key

The service script uses this value unless API_KEY is explicitly set before submission.
If you choose a different value, update the curl commands, notebook cells, and batch client inputs accordingly.

Step 3: Submit the persistent service job
-----------------------------------------

```bash
JOBID=$(
  bsub -J vllm_service        -q normal        -n 1        -R 'rusage[mem=12GB]'        -oo ~/lsf_vllm_poc/logs/vllm.%J.out        -eo ~/lsf_vllm_poc/logs/vllm.%J.err        ~/lsf_vllm_poc/start_vllm_lsf.sh   | awk '{print $2}' | tr -d '<>'
)

echo "Submitted service JOBID=$JOBID"
```

Step 4: Monitor the service startup
-----------------------------------

```bash
bjobs
bjobs -l ${JOBID}
bpeek ${JOBID}
```

```bash
podman ps -a | grep vllm-job-${JOBID}
podman logs -f vllm-job-${JOBID}
```

Step 5: Wait for the registry file
----------------------------------

```bash
until [[ -f ~/lsf_vllm_poc/registry/${JOBID}.json ]]; do
  sleep 2
done

cat ~/lsf_vllm_poc/registry/${JOBID}.json
```

Step 6: Resolve the endpoint
----------------------------

```bash
python3 ~/lsf_vllm_poc/resolve_endpoint.py ${JOBID}
```

```bash
ENDPOINT=$(python3 ~/lsf_vllm_poc/resolve_endpoint.py ${JOBID})
echo "${ENDPOINT}"
```

Kill the LLM service
--------------------

```bash
bkill ${JOBID}
```

Part 2: Use the LLM
===================

Use the LLM with curl
---------------------

```bash
curl -sS "${ENDPOINT}/models"   -H "Authorization: Bearer local-vllm-key"
```

```bash
curl -sS "${ENDPOINT}/chat/completions"   -H "Content-Type: application/json"   -H "Authorization: Bearer local-vllm-key"   -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [
      {"role": "user", "content": "Explain the top 5 deserts in the world."}
    ],
    "temperature": 0,
    "max_tokens": 120
  }'
```

Use the LLM from Jupyter
------------------------

Additional prerequisite:
- You must have SSH access from your laptop to the IBM LSF host where Jupyter will run.

Run the following commands on the IBM LSF host / cluster node:

```bash
python3 -m venv ~/lsf_vllm_poc/notebook/.venv
source ~/lsf_vllm_poc/notebook/.venv/bin/activate
pip install --upgrade pip
pip install notebook jupyterlab requests openai ipykernel
python -m ipykernel install --user --name lsf-vllm --display-name "Python (lsf-vllm)"
```

Start Jupyter on the IBM LSF host / cluster node:

```bash
jupyter notebook --no-browser --ip=0.0.0.0 --port 8888 --allow-root
```

Jupyter will print a URL containing a token. Keep that terminal running.

Run the following command on your laptop to create an SSH tunnel:

```bash
ssh -L 8888:127.0.0.1:8888 user@your-host
```

Open the following URL in a web browser on your laptop:

```
http://127.0.0.1:8888
```

When prompted, use the token printed by Jupyter on the IBM LSF host.

If the notebook kernel is running on the same IBM LSF host as the vLLM service, use the following base URL inside the notebook:

```
http://127.0.0.1:8001/v1
```

In this flow, the browser runs on the laptop, but the notebook kernel runs on the IBM LSF host. That is why the notebook can access the local vLLM endpoint at `http://127.0.0.1:8001/v1`.

Use the LLM from an IBM LSF batch job
-------------------------------------

```bash
python3 ~/lsf_vllm_poc/batch_client.py ${JOBID} ~/lsf_vllm_poc/corpus/prompts.txt
```

```bash
cat ~/lsf_vllm_poc/results/batch_${JOBID}.jsonl
```

```bash
BATCH_JOBID=$(
  bsub -J vllm_batch        -q normal        -n 1        -R 'rusage[mem=1GB]'        -oo ~/lsf_vllm_poc/logs/batch.%J.out        -eo ~/lsf_vllm_poc/logs/batch.%J.err        "python3 ~/lsf_vllm_poc/batch_client.py ${JOBID} ~/lsf_vllm_poc/corpus/prompts.txt"   | awk '{print $2}' | tr -d '<>'
)

echo "Submitted batch JOBID=$BATCH_JOBID"
```

```bash
bjobs
bpeek ${BATCH_JOBID}
cat ~/lsf_vllm_poc/results/batch_${JOBID}.jsonl
```

Use the LLM with Open WebUI (Linux)
-----------------------------------

```bash
podman run -d   -p 3000:8080   -e OPENAI_API_BASE_URL=http://your-host:8001/v1   -e OPENAI_API_KEY=local-vllm-key   -e WEBUI_SECRET_KEY=my-openwebui-secret   -v open-webui:/app/backend/data   --name open-webui   ghcr.io/open-webui/open-webui:main
```

```bash
podman ps
podman logs -f open-webui
```

http://localhost:3000

- Settings → Connections → OpenAI
- Base URL: http://your-host:8001/v1
- API Key: local-vllm-key

Model:
Qwen/Qwen3-0.6B

Test:
Say one short line about LSF-managed model serving.

Cleanup
-------

```bash
bkill ${BATCH_JOBID}
bkill ${JOBID}
```
