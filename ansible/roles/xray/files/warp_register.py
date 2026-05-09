#!/usr/bin/env python3

import base64
import datetime
import json
import urllib.request
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey


priv = X25519PrivateKey.generate()

private_key = base64.b64encode(priv.private_bytes_raw()).decode()
public_key = base64.b64encode(priv.public_key().public_bytes_raw()).decode()

payload = {
    "key": public_key,
    "tos": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.000Z"),
}

req = urllib.request.Request(
    "https://api.cloudflareclient.com/v0a4005/reg",
    data=json.dumps(payload).encode(),
    headers={
        "Content-Type": "application/json",
        "User-Agent": "okhttp/3.12.1",
    },
    method="POST",
)

with urllib.request.urlopen(req) as r:
    resp = json.loads(r.read())

addresses = resp["config"]["interface"]["addresses"]
peer = resp["config"]["peers"][0]

client_id = resp["config"]["client_id"]
reserved = list(base64.b64decode(client_id))

# Extract v4 endpoint host only (strip port if present)
endpoint_v4_raw = peer["endpoint"]["v4"]
endpoint_v4 = endpoint_v4_raw.rsplit(":", 1)[0]

result = {
    "private_key": private_key,
    "public_key": peer["public_key"],
    "v4": addresses["v4"],
    "v6": addresses["v6"],
    "reserved_dec": reserved,
    "endpoint": {
        "v4": endpoint_v4
    },
}

print(json.dumps(result, indent=2))
