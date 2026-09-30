"""Read opt-in Flutter frame timings from a connected profile build.

The probe returns durations only. This script does not inspect app content,
change app data, or save the VM service address.
"""

import argparse
import json
import re
import subprocess
from pathlib import Path

import httpx


ADB = Path.home() / "AppData/Local/Android/Sdk/platform-tools/adb.exe"
PACKAGE = "cn.semesteros.semester_os"


def adb(serial: str, *args: str) -> str:
    return subprocess.run(
        [str(ADB), "-s", serial, *args],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    ).stdout.strip()


def capture(serial: str, reset: bool) -> dict:
    pid = adb(serial, "shell", "pidof", PACKAGE)
    if not re.fullmatch(r"\d+", pid):
        raise RuntimeError("The phone app is not running")
    log = adb(serial, "logcat", f"--pid={pid}", "-d", "-s", "flutter")
    matches = re.findall(
        r"The Dart VM service is listening on http://127\.0\.0\.1:(\d+)/([^\s]+)",
        log,
    )
    if not matches:
        raise RuntimeError("Profile VM service was not advertised")
    port, auth = matches[-1]
    forwarded = adb(serial, "forward", "tcp:0", "tcp:" + port)
    try:
        with httpx.Client(
            base_url=f"http://127.0.0.1:{forwarded}/{auth}", timeout=20
        ) as client:
            vm = client.get("getVM").json()["result"]
            isolate = next(
                item["id"] for item in vm["isolates"] if item.get("name") == "main"
            )
            result = client.get(
                "ext.semesteros.frames",
                params={"isolateId": isolate, "reset": str(reset).lower()},
            ).json()
            if "error" in result:
                raise RuntimeError(result["error"])
            return result["result"]
    finally:
        adb(serial, "forward", "--remove", "tcp:" + forwarded)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["read", "reset"])
    parser.add_argument("--serial", required=True, help="ADB serial from adb devices")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    metrics = capture(args.serial, args.action == "reset")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(json.dumps(metrics, ensure_ascii=False))
