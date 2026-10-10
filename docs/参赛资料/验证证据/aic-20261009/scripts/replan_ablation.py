"""Synthetic candidate-only objective comparison against production replanner.

The sole source variation is the objective list: lexicographic moved-task count,
total shift, then earlier starts, versus only sum(start). All hard constraints,
input preparation, solver settings, 10-second total budget, and output validation
are the same production code. Nothing is inserted into a database.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import hashlib
import inspect
import json
from pathlib import Path
import sys
import time

ROOT = next((parent for parent in Path(__file__).resolve().parents
    if (parent / "services/api/app").is_dir() and (parent / "apps/mobile/lib").is_dir()), None)
if ROOT is None:
    raise RuntimeError("Place this anonymous experiment script inside a SemesterOS checkout.")
sys.path.insert(0, str(ROOT / "services/api"))
from app import replanner
from app.capacity import calendar_context
from app.plan_rules import classify
from app.reminder_rules import instant

TZ = timezone(timedelta(hours=8))
ORIGINAL_OBJECTIVES = "objectives=[('moved_tasks',sum(task_moves)),('shift_minutes',sum(offsets)),('earlier',sum(variables))]"
BASELINE_OBJECTIVES = "objectives=[('earlier',sum(variables))]"


def sha(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def make_scenario(name, starts, locked, activity):
    day = (datetime.now(TZ) + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    monday = day.date() - timedelta(days=day.weekday())
    at = lambda hour: day.replace(hour=hour).isoformat()
    now = day.replace(hour=8)
    calendar = {"first_monday": monday.isoformat(), "total_weeks": 20, "periods": [], "fixed_events": []}
    if activity:
        calendar["fixed_events"] = [{"id": "activity", "title": "合成新增固定活动", "certainty": "formal",
            "reserve_time": True, "time": {"precision": "exact", "at": at(activity[0]), "end_at": at(activity[1])}}]
    pref = {"configured": True, "weekly": [{"weekday": day.isoweekday(), "start": "09:00", "end": "17:00"}], "exclusions": []}
    items, blocks = [], []
    for index, hour in enumerate(starts):
        identity = chr(ord("a")+index)
        items.append({"id": identity, "kind": "task", "title": "合成任务" + identity, "lifecycle": "active",
            "certainty": "formal", "time": {"precision": "exact", "at": at(17)},
            "remaining_minutes": 60, "splittable": False, "start_policy": "at", "earliest_start_at": at(9)})
        blocks.append({"id": "block-"+identity, "item_id": identity, "title": "合成任务"+identity,
            "start_at": at(hour), "end_at": at(hour+1), "minutes": 60,
            "status": "active", "version": 1, "locked": index in locked})
    return {"name":name,"calendar":calendar,"preferences":pref,"courses":[],"items":items,
            "plans":blocks,"request":{"lead_minutes":0},"now":now.isoformat()}


def independent_validate(snapshot, candidate):
    """Validate directly from snapshot, without trusting candidate metrics."""
    original = {b["id"]: b for b in snapshot["plans"]}
    blocks = candidate.get("blocks", [])
    checks = {}
    checks["complete_feasible"] = candidate.get("status") == "FEASIBLE_COMPLETE"
    checks["same_block_set"] = len(blocks) == len(original) and {b["id"] for b in blocks} == set(original)
    checks["conserved_payload_and_duration"] = checks["same_block_set"] and all(
        all(b.get(k) == original[b["id"]].get(k) for k in ("item_id","minutes","locked","version","status"))
        and instant(b["end_at"])-instant(b["start_at"]) == timedelta(minutes=original[b["id"]]["minutes"])
        for b in blocks)
    checks["locked_unchanged"] = checks["same_block_set"] and all(
        not original[b["id"]]["locked"] or
        (instant(b["start_at"]) == instant(original[b["id"]]["start_at"]) and
         instant(b["end_at"]) == instant(original[b["id"]]["end_at"])) for b in blocks)
    now = datetime.fromisoformat(snapshot["now"])
    context = calendar_context(snapshot["calendar"],snapshot["preferences"],snapshot["courses"],snapshot["items"],now)
    _, issues = classify(blocks,snapshot["items"],context["free"].spans,context["begin"],
        obligation_points=context["obligation_points"])
    checks["all_hard_time_rules"] = not issues
    changed = [b for b in blocks if b["id"] in original and instant(b["start_at"]) != instant(original[b["id"]]["start_at"])]
    recomputed = {"moved_tasks":len({b["item_id"] for b in changed}),"moved_blocks":len(changed),
        "shift_minutes":sum(int(abs((instant(b["start_at"])-instant(original[b["id"]]["start_at"])).total_seconds())/60) for b in changed),
        "total_start_minutes":sum(int(instant(b["start_at"]).timestamp()/60) for b in blocks),
        "work_minutes":sum(b["minutes"] for b in blocks)}
    checks["reported_metrics_match"] = all(candidate.get(k) == recomputed[k] for k in ("moved_tasks","moved_blocks","shift_minutes"))
    return {"passed":all(checks.values()),"checks":checks,"issues":issues,"recomputed":recomputed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute-local", action="store_true")
    parser.add_argument("--output",type=Path,default=Path(__file__).parent/"evidence/replan-ablation.json")
    parser.add_argument("--repeat",type=int,default=1)
    args=parser.parse_args()
    if args.repeat < 1:
        parser.error("--repeat must be at least 1")
    if not args.execute_local:
        print("No solver executed; requires --execute-local gate.")
        return
    source = inspect.getsource(replanner.generate)
    if source.count(ORIGINAL_OBJECTIVES) != 1:
        raise RuntimeError("Production objective source changed; refusing an uncontrolled comparison")
    baseline_source = source.replace(ORIGINAL_OBJECTIVES, BASELINE_OBJECTIVES)
    namespace = dict(replanner.__dict__)
    exec(compile(baseline_source, str(Path(replanner.__file__).resolve())+"#earlier-only", "exec"),namespace)
    baseline = namespace["generate"]
    scenarios = [
        make_scenario("conflict_at_09_locked_late",[9,12,14],{2},(9,10)),
        make_scenario("conflict_at_11_locked_last",[11,13,15],{2},(11,12)),
        make_scenario("valid_plan_retention",[12,14,16],{2},None),
    ]
    report = {"generated_at":datetime.now(TZ).isoformat(),"source":"synthetic candidate-only comparison",
        "production_file":str(Path(replanner.__file__).resolve()),
        "production_file_sha256":hashlib.sha256(Path(replanner.__file__).read_bytes()).hexdigest(),
        "generate_sha256":sha(source),"baseline_generate_sha256":sha(baseline_source),
        "unique_difference":{"before":ORIGINAL_OBJECTIVES,"after":BASELINE_OBJECTIVES},
        "preserved":["same frozen snapshot for both candidates", "all production constraints",
                     "all block identities and work amounts", "locked blocks", "deadlines and releases",
                     "10-second total solver budget", "4 workers", "production validator"],
        "caveats":["3 small synthetic scenes are illustrative; not a large statistical benchmark",
                   "only objective function differs; earlier-only remains a legitimate baseline",
                   "one repetition does not support a runtime advantage; 4-worker timings vary",
                   "no database writes; no human efficiency claim"],"cases":[]}
    for repetition in range(args.repeat):
        for scene in scenarios:
            row={"scenario":scene["name"],"repetition":repetition+1,"input":scene,
                 "snapshot_sha256":sha(json.dumps(scene,sort_keys=True,ensure_ascii=False)),"candidates":{}}
            # Alternate execution order to reduce a systematic first-run timing bias.
            ordered=[("minimum_disruption",replanner.generate),("earlier_only",baseline)]
            if repetition%2: ordered.reverse()
            for label,fn in ordered:
                frozen=deepcopy(scene)
                started=time.monotonic()
                result=fn(frozen["calendar"],frozen["preferences"],frozen["courses"],frozen["items"],
                          frozen["plans"],frozen["request"],datetime.fromisoformat(frozen["now"]))
                seconds=time.monotonic()-started
                check=independent_validate(scene,result)
                row["candidates"][label]={"seconds":round(seconds,6),"result":result,"validation":check}
                if frozen != scene:
                    raise AssertionError("Candidate altered its input snapshot")
            a=row["candidates"]["minimum_disruption"]["validation"]["recomputed"]
            b=row["candidates"]["earlier_only"]["validation"]["recomputed"]
            row["comparison"]={"minimum_disruption_moved_tasks":a["moved_tasks"],"earlier_only_moved_tasks":b["moved_tasks"],
                "minimum_disruption_shift_minutes":a["shift_minutes"],"earlier_only_shift_minutes":b["shift_minutes"],
                "same_work_minutes":a["work_minutes"]==b["work_minutes"],
                "lexicographic_dominance":(a["moved_tasks"],a["shift_minutes"]) <= (b["moved_tasks"],b["shift_minutes"]),
                "both_optimal":all(c["result"].get("optimal") for c in row["candidates"].values())}
            row["passed"]=(all(c["validation"]["passed"] for c in row["candidates"].values())
                and row["comparison"]["same_work_minutes"] and row["comparison"]["lexicographic_dominance"]
                and row["comparison"]["both_optimal"])
            report["cases"].append(row)
            print(json.dumps({"scenario":row["scenario"],"passed":row["passed"],**row["comparison"]},ensure_ascii=False),flush=True)
    report["passed"]=all(c["passed"] for c in report["cases"])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    if not report["passed"]: sys.exit(1)


if __name__ == "__main__":
    main()
