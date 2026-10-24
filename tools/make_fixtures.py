"""Generates the JSON fixtures the Swift Uconnect client is tested against.

To regenerate (from the repo root):

    python3 -I tools/make_fixtures.py ios/ForxTests/Fixtures

The SigV4 expected values are computed by py-uconnect's own signer (sigv4.py),
loaded straight from the reference checkout below; nothing is installed. All
values are fake: VIN 1C4JJXP60RW000000, location 0.0 / 0.0, no real secrets.
"""

import importlib.util
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

SIGV4_PATH = Path(
    "/tmp/claude-0/-home-claude/49428304-0dd0-528c-984a-fb334289ec08/scratchpad/"
    "uconnect/py-uconnect/py_uconnect/sigv4.py"
)

VIN = "1C4JJXP60RW000000"
NOW = "2026-10-24T12:00:00Z"
REGION = "us-east-1"
TS_MS = 1792843200000  # 2026-10-24T12:00:00Z

SERVICES = [
    {"service": name, "vehicleCapable": True, "serviceEnabled": True}
    for name in ("RDL", "RDU", "HBLF", "REON", "REOFF")
]


def load_sigv4():
    spec = importlib.util.spec_from_file_location("sigv4", SIGV4_PATH)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["sigv4"] = mod
    spec.loader.exec_module(mod)
    return mod


def sigv4_fixture():
    sigv4 = load_sigv4()
    request = {
        "method": "GET",
        "url": f"https://api.example.invalid/v4/accounts/uid-fake/vehicles/{VIN}/status?stage=ALL&brand=FAKE&sdp=ALL",
        "headers": {"Content-Type": "application/json", "x-api-key": "fake-api-key"},
        "body": "",
    }
    creds = {"access": "AKIAFAKEACCESSKEY", "secret": "fake-secret-key", "session": "fake-session-token"}
    now = datetime.fromisoformat(NOW.replace("Z", "+00:00")).astimezone(UTC)
    added = sigv4.sign(
        request["method"],
        request["url"],
        request["headers"],
        request["body"].encode(),
        sigv4.AWSCredentials(creds["access"], creds["secret"], creds["session"]),
        REGION,
        "execute-api",
        now,
    )
    return {
        "request": request,
        "creds": creds,
        "now": NOW,
        "region": REGION,
        "service": "execute-api",
        "expected": {
            "authorization": added["Authorization"],
            "x_amz_date": added["X-Amz-Date"],
        },
    }


def tyre(kind, kpa, warn=False):
    return {"type": kind, "pressure": {"value": str(kpa), "unit": "kPa"}, "warning": str(warn).lower()}


def vehicle_info():
    return {
        "timestamp": TS_MS,
        "vehicleInfo": {
            "batteryInfo": {"batteryVoltage": {"value": "12.6", "unit": "V"}, "batteryStateOfCharge": "GOOD"},
            "daysToService": "120",
            "distanceToService": {"distanceToService": {"value": "4000", "unit": "km"}},
            "fuel": {"distanceToEmpty": {"value": "300", "unit": "km"}, "isFuelLevelLow": "false", "fuelAmountLevel": "60"},
            "oilLevel": {"oilLevel": "80"},
            "odometer": {"odometer": {"value": "12345.6", "unit": "km"}},
            # Rear right tire intentionally missing
            "tyrePressure": [tyre("FL", 241), tyre("FR", 238), tyre("RL", 234)],
        },
        "evInfo": {
            "battery": {
                "stateOfCharge": "78",
                "chargingStatus": "NOT_CHARGING",
                "chargingLevel": "DEFAULT",
                "plugInStatus": False,
                "distanceToEmpty": {"value": "40", "unit": "km"},
                "gasRange": "260",
                "totalRange": "300",
                "timeToFullyChargeL3": "-1",
                "timeToFullyChargeL2": "150",
                "timeToFullyChargeL1": "600",
            },
            "chargePowerPreference": "LEVEL_TWO",
            "ignitionStatus": "OFF",
        },
        "windows": None,
        "hvac": None,
        "liftgate": None,
    }


def door(status="LOCKED"):
    return {"status": status}


def remote_status():
    return {
        "timestamp": TS_MS,
        "doors": {"driver": door(), "passenger": door(), "leftRear": door(), "rightRear": door()},
        "trunk": door(),
        "liftGate": door(),
        "engine": {"status": "OFF"},
        "evRunning": {"status": "OFF"},
        "hvac": {"status": "OFF", "temperature": {"value": "22", "unit": "C"}},
    }


def vehicles():
    return {
        "vehicles": [
            {
                "vin": VIN,
                "nickname": "Test Jeep",
                "make": "Jeep",
                "modelDescription": "Wrangler 4xe",
                "year": "2024",
                "soldRegion": "US",
                "sdp": "ignite",
                "fuelType": "PHEV",
                "privacyMode": "INACTIVE",
                "vehicleImageURL": "https://example.invalid/jeep.png",
                "services": SERVICES,
            }
        ]
    }


def build():
    return {
        "sigv4_get": sigv4_fixture(),
        "vehicles": vehicles(),
        "vehicle_info": vehicle_info(),
        "remote_status": remote_status(),
        "pin_ok": {"token": "pin-token", "expiry": 300000},
        "command_ok": {"correlationId": "corr-1"},
        "status_pending": {"status": "PENDING"},
        "status_success": {"status": "SUCCESS"},
        "status_failure": {"status": "FAILURE"},
        "services": SERVICES,
        "gigya_login": {
            "statusCode": 200,
            "errorCode": 0,
            "UID": "uid-fake",
            "sessionInfo": {"login_token": "fake-login-token"},
        },
        "gigya_login_badpassword": {
            "statusCode": 403,
            "errorCode": 403042,
            "errorMessage": "Invalid LoginID",
            "errorDetails": "invalid loginID or password",
        },
        "gigya_jwt": {"statusCode": 200, "errorCode": 0, "id_token": "fake-id-token"},
        "token_exchange": {"IdentityId": "us-east-1:fake-identity-id", "Token": "fake-openid-token"},
        "cognito": {
            "IdentityId": "us-east-1:fake-identity-id",
            "Credentials": {
                "AccessKeyId": "AKIAFAKEACCESSKEY",
                "SecretKey": "fake-secret-key",
                "SessionToken": "fake-session-token",
                "Expiration": 1792846800,  # 2026-10-24T13:00:00Z
            },
        },
    }


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make_fixtures.py OUTPUT_DIR")
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, data in build().items():
        (out / f"{name}.json").write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    print(f"wrote {len(build())} fixtures to {out}")


if __name__ == "__main__":
    main()
