#!/usr/bin/env python3
import json
import os
import sys
import urllib.request

if len(sys.argv) not in (2, 3):
    print("Usage: batch_client.py <JOBID> [PROMPTS_FILE]", file=sys.stderr)
    sys.exit(1)

jobid = sys.argv[1]
base = os.path.expanduser("~/lsf_vllm_poc")
prompts_file = sys.argv[2] if len(sys.argv) == 3 else os.path.join(base, "corpus", "prompts.txt")

with open(os.path.join(base, "registry", f"{jobid}.json")) as f:
    reg = json.load(f)

url = f"http://{reg['host']}:{reg['port']}/v1/chat/completions"
headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {reg['api_key']}",
}

outp = os.path.join(base, "results", f"batch_{jobid}.jsonl")

with open(prompts_file) as fin, open(outp, "w") as fout:
    for line in fin:
        prompt = line.strip()
        if not prompt:
            continue

        payload = {
            "model": reg["model"],
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0,
            "max_tokens": 96,
            "chat_template_kwargs": {"enable_thinking": False},
        }

        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )

        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.load(resp)

        text = data["choices"][0]["message"]["content"]
        fout.write(json.dumps({"prompt": prompt, "response": text}) + "\n")

print(outp)
