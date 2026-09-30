"""Collect Flutter widget-build timing names on a connected profile app.

Only timing event names and durations are saved; event arguments and app data
are discarded. Use `start`, perform the UI action, then `stop`.
"""

import argparse
import json
import re
from collections import defaultdict
from contextlib import contextmanager
from pathlib import Path

import httpx

from capture_phone_frames import PACKAGE, adb


@contextmanager
def service(serial: str):
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
            base_url=f"http://127.0.0.1:{forwarded}/{auth}", timeout=30
        ) as client:
            vm = client.get("getVM").json()["result"]
            isolate = next(
                item["id"] for item in vm["isolates"] if item.get("name") == "main"
            )
            yield client, isolate
    finally:
        adb(serial, "forward", "--remove", "tcp:" + forwarded)


def call(client, path, params=None):
    result = client.get(path, params=params).json()
    if "error" in result:
        raise RuntimeError(result["error"])
    return result["result"]


def summarize(events):
    totals = defaultdict(lambda: [0, 0.0, 0.0])
    pending = defaultdict(list)
    for event in events:
        name, phase = event.get("name", ""), event.get("ph")
        thread = (event.get("pid"), event.get("tid"))
        if phase == "B":
            pending[thread].append((name, event.get("ts", 0)))
        elif phase == "E" and pending[thread]:
            start_name, start = pending[thread].pop()
            duration = max(0.0, (event.get("ts", 0) - start) / 1000)
            row = totals[start_name]
            row[0] += 1
            row[1] += duration
            row[2] = max(row[2], duration)
        elif phase == "X":
            duration = event.get("dur", 0) / 1000
            row = totals[name]
            row[0] += 1
            row[1] += duration
            row[2] = max(row[2], duration)
    return [
        {"name": name, "count": count, "total_ms": round(total, 3), "max_ms": round(maximum, 3)}
        for name, (count, total, maximum) in sorted(
            totals.items(), key=lambda item: item[1][1], reverse=True
        )
    ]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["start", "stop"])
    parser.add_argument("--serial", required=True, help="ADB serial from adb devices")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    with service(args.serial) as (client, isolate):
        if args.action == "start":
            call(client, "clearVMTimeline")
            call(
                client,
                "ext.flutter.profileWidgetBuilds",
                {"isolateId": isolate, "enabled": "true"},
            )
            print("Widget-build timeline started")
        else:
            call(
                client,
                "ext.flutter.profileWidgetBuilds",
                {"isolateId": isolate, "enabled": "false"},
            )
            events = call(client, "getVMTimeline").get("traceEvents", [])
            summary = summarize(events)
            output = {"events": len(events), "top": summary[:40]}
            if args.output:
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(json.dumps(output, indent=2), encoding="utf-8")
                compact = [
                    {key: event[key] for key in ("name", "ph", "ts", "dur", "pid", "tid") if key in event}
                    for event in events
                    if event.get("ph") in ("B", "E", "X")
                ]
                args.output.with_name(args.output.stem + "-events.json").write_text(
                    json.dumps(compact), encoding="utf-8"
                )
            print(json.dumps(output, ensure_ascii=False))
