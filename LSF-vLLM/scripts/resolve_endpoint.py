#!/usr/bin/env python3
import json
import os
import sys

if len(sys.argv) != 2:
    print("Usage: resolve_endpoint.py <JOBID>", file=sys.stderr)
    sys.exit(1)

jobid = sys.argv[1]
reg_path = os.path.expanduser(f"~/lsf_vllm_poc/registry/{jobid}.json")

with open(reg_path) as f:
    reg = json.load(f)

print(f"http://{reg['host']}:{reg['port']}/v1")
