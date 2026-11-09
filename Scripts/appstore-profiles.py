#!/usr/bin/env python3
"""Creates fresh App Store provisioning profiles for TestFlight builds, through the App Store Connect API.

    Scripts/appstore-profiles.py CERT_SERIAL BUNDLE_ID [BUNDLE_ID ...]

For each bundle ID it deletes any earlier profile named "Meetball CI <bundle ID>", creates a new IOS_APP_STORE profile
of that name for the Apple Distribution certificate with serial number CERT_SERIAL (hex), and installs it where
xcodebuild looks. A fresh profile each run always carries the App ID's current capabilities and the current
certificate. Used by .github/workflows/testflight.yml.

Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8) from the environment. Standard library and the openssl
command only, so it runs on a stock macOS runner.
"""
import base64
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
PROFILE_PREFIX = "Meetball CI "


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """An ECDSA signature from openssl is DER (SEQUENCE of two INTEGERs); a JWT wants r and s as 32 bytes each."""
    def read_int(buf, i):
        assert buf[i] == 0x02, "bad DER signature"
        length = buf[i + 1]
        value = buf[i + 2:i + 2 + length]
        return int.from_bytes(value, "big"), i + 2 + length
    i = 2 if der[1] < 0x80 else 3
    r, i = read_int(der, i)
    s, _ = read_int(der, i)
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def token() -> str:
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    now = int(time.time())
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(claims).encode())}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
                         input=signing_input, capture_output=True, check=True).stdout
    return f"{signing_input.decode()}.{b64url(der_to_raw(der))}"


def call(method, path, body=None, query=None):
    url = f"{API}/{path}" + (f"?{urllib.parse.urlencode(query)}" if query else "")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")
        sys.exit(f"App Store Connect API {method} {path} failed ({err.code}): {detail}")


def norm_serial(serial: str) -> str:
    return serial.strip().upper().lstrip("0")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    serial, bundle_ids = norm_serial(sys.argv[1]), sys.argv[2:]

    certs = call("GET", "certificates", query={"limit": 200})["data"]
    dist = [c for c in certs if c["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION")]
    match = [c for c in dist if norm_serial(c["attributes"]["serialNumber"]) == serial]
    if not match:
        known = ", ".join(f'{c["attributes"]["name"]} ({c["attributes"]["serialNumber"]})' for c in dist) or "none"
        sys.exit(f"No distribution certificate with serial {serial} on this team (found: {known}). "
                 "Is DISTRIBUTION_CERTIFICATE_P12 an Apple Distribution certificate from team TS339TNM5P?")
    cert_id = match[0]["id"]
    print(f"Certificate: {match[0]['attributes']['name']} ({serial})")

    dirs = [pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles",
            pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"]
    for d in dirs:
        d.mkdir(parents=True, exist_ok=True)

    for bundle in bundle_ids:
        found = call("GET", "bundleIds", query={"filter[identifier]": bundle, "limit": 200})["data"]
        ids = [b for b in found if b["attributes"]["identifier"] == bundle]
        if not ids:
            sys.exit(f"App ID {bundle} isn't registered on this team. Build MeetballPhone to your iPhone from Xcode once "
                     "(README, \"Install it on your iPhone\") so Xcode registers it, then run this again.")
        bundle_ref = ids[0]["id"]

        name = PROFILE_PREFIX + bundle
        for old in call("GET", "profiles", query={"filter[name]": name, "limit": 200})["data"]:
            if old["attributes"]["name"] == name:
                call("DELETE", f"profiles/{old['id']}")
                print(f"Deleted old profile {name} ({old['id']})")

        created = call("POST", "profiles", body={"data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_ref}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            },
        }})["data"]["attributes"]
        content = base64.b64decode(created["profileContent"])
        for d in dirs:
            (d / f"{created['uuid']}.mobileprovision").write_bytes(content)
        print(f"Installed profile {name} ({created['uuid']})")


if __name__ == "__main__":
    main()
