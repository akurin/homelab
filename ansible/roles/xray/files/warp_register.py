#!/usr/bin/env python3
import base64, json, urllib.request
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

priv = X25519PrivateKey.generate()
priv_b64 = base64.b64encode(priv.private_bytes_raw()).decode()
pub_b64  = base64.b64encode(priv.public_key().public_bytes_raw()).decode()

req = urllib.request.Request(
    "https://api.cloudflareclient.com/v0a4005/reg",
    data=json.dumps({
        "key": pub_b64,
        "install_id": "",
        "fcm_token": "",
        "tos": "2023-11-01T00:00:00.000Z",
        "model": "PC",
        "serial_number": "",
        "locale": "en_US"
    }).encode(),
    headers={"Content-Type": "application/json", "User-Agent": "okhttp/3.12.1"}
)
with urllib.request.urlopen(req) as r:
    resp = json.loads(r.read())

ipv4       = resp["config"]["interface"]["addresses"]["v4"] + "/32"
ipv6       = resp["config"]["interface"]["addresses"]["v6"] + "/128"
server_pub = resp["config"]["peers"][0]["public_key"]

print(json.dumps({
    "private_key": priv_b64,
    "public_key":  server_pub,
    "v4":          ipv4,
    "v6":          ipv6,
}, indent=2))
