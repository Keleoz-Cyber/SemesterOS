"""Fresh AIC evidence: HTTP, real provider and solver, synthetic local accounts only.

No service is launched by this script. --execute-local is mandatory and the base
URL is pinned to http://127.0.0.1:8874. Passwords and session/preview tokens stay in
memory; evidence redacts them. Optional SQLite traces query only this script's
new user id and run ids, through a read-only connection.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import secrets
import sqlite3
import sys
import time

import httpx

LOCAL_BASE = "http://127.0.0.1:8874"
TZ = timezone(timedelta(hours=8))
SECRET_FIELDS = {"password", "new_password", "token", "access_token", "refresh_token",
                 "logout_token", "recovery_code", "authorization", "api_key"}


def redact(value):
    if isinstance(value, dict):
        return {k: ("[REDACTED]" if k.lower() in SECRET_FIELDS or k.lower().endswith("_token") else redact(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v) for v in value]
    if isinstance(value, str) and value.lstrip().startswith(("{", "[")):
        # Tool messages contain JSON inside a string, including preview tokens.
        try:
            parsed = json.loads(value)
        except (ValueError, TypeError):
            return value
        if isinstance(parsed, (dict, list)):
            return json.dumps(redact(parsed), ensure_ascii=False)
    return value


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(redact(value), ensure_ascii=False, indent=2), encoding="utf-8")


class Evidence:
    def __init__(self, args, name, expectation):
        self.args, self.name, self.started = args, name, time.monotonic()
        self.value = {"case": name, "expected": expectation, "passed": False,
                      "data": "synthetic disposable local account", "steps": [], "checks": []}
        self.api = httpx.Client(base_url=LOCAL_BASE + "/api/v1", timeout=70, trust_env=False)
        self.user_id = None
        self.session = None
        self.day = (datetime.now(TZ) + timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
        self.monday = self.day.date() - timedelta(days=self.day.weekday())

    def request(self, method, url, body=None, expected=200, headers=None, params=None):
        start = time.monotonic()
        response = self.api.request(method, url, json=body, headers=headers, params=params)
        try:
            data = response.json()
        except ValueError:
            data = response.text
        # Registration secrets must never reach either logs or assertion messages.
        safe = redact(data)
        self.value["steps"].append({"method": method, "path": url, "input": redact(body),
            "params": params, "expected_status": expected, "actual_status": response.status_code,
            "seconds": round(time.monotonic() - start, 3), "actual": safe})
        if expected is not None:
            self.expect(response.status_code == expected, f"{method} {url}: HTTP {expected}",
                        {"actual_status": response.status_code, "response": safe})
        return data

    def expect(self, condition, label, actual=None):
        self.value["checks"].append({"expected": label, "passed": bool(condition), "actual": redact(actual)})
        if not condition:
            raise AssertionError(label)

    def at(self, hour, minute=0):
        return self.day.replace(hour=hour, minute=minute).isoformat()

    def setup(self, courses=False, availability=None):
        username = "qa_aic_" + secrets.token_hex(7)
        self.session = self.request("POST", "/auth/register", {"username": username,
            "password": secrets.token_urlsafe(30)}, expected=201)
        self.user_id = self.session["user"]["id"]
        self.value["account"] = username
        self.api.headers["Authorization"] = "Bearer " + self.session["access_token"]
        s = self.request("POST", "/semesters", {"name": "AIC本轮合成验证·" + self.name,
            "first_monday": self.monday.isoformat(), "total_weeks": 20,
            "periods": [{"number": 1, "start": "09:00", "end": "10:00"},
                        {"number": 2, "start": "10:10", "end": "11:00"}]}, expected=201)
        self.sid, self.path = s["id"], "/semesters/" + s["id"]
        if courses:
            payload = {"semester_id": self.sid, "source": "manual", "courses": [
                {"title": "合成第一课", "weekday": self.day.isoweekday(), "weeks": [1, 2], "sections": [1]},
                {"title": "合成后续课", "weekday": self.day.isoweekday(), "weeks": [1, 2], "sections": [2]}]}
            batch = self.request("POST", "/imports", payload, expected=201)
            self.request("POST", "/imports/" + batch["id"] + "/apply",
                         {"expected_revision": batch["base_revision"]})
        if availability:
            pref = {"expected_version": 0, "weekly": [{"weekday": self.day.isoweekday(),
                        "start": availability[0], "end": availability[1]}], "exclusions": []}
            preview = self.request("POST", self.path + "/availability/preview", pref)
            self.request("PUT", self.path + "/availability", {**pref, "expected_revision": preview["base_revision"]})
        return s

    def revision(self):
        terms = self.request("GET", "/semesters")
        return next(s["revision"] for s in terms if s["id"] == self.sid)

    def timetable(self, week=1):
        return self.request("GET", self.path + "/timetable", params={"week": week})["events"]

    def calendar(self):
        return self.request("GET", self.path + "/calendar", params={
            "from_date": self.day.date().isoformat(), "to_date": self.day.date().isoformat()})

    def event_body(self, revision=None):
        return {"semester_id": self.sid, "expected_revision": self.revision() if revision is None else revision,
                "title": "合成开始点会议", "certainty": "formal", "reserve_time": True,
                "time": {"precision": "exact", "at": self.at(9, 15)}, "source_text": "只知道09:15开始，结束未定"}

    def task(self, title, minutes=60, splittable=False):
        return self.request("POST", "/items", {"semester_id": self.sid, "kind": "task", "title": title,
            "certainty": "formal", "time": {"precision": "exact", "at": self.at(13)},
            "remaining_minutes": minutes, "splittable": splittable, "start_policy": "at",
            "earliest_start_at": self.at(9)}, expected=201)

    def ask(self, text, input_kind="message", thread_id=None):
        thread = thread_id or self.request("POST", "/agent/threads", {"semester_id": self.sid}, expected=201)["id"]
        start = time.monotonic()
        turn = self.request("POST", "/agent/threads/" + thread + "/turns",
            {"text": text, "request_id": "aic_" + secrets.token_hex(7), "input_kind": input_kind}, expected=202)
        rid, last_status = turn["id"], None
        deadline = time.monotonic() + self.args.model_timeout
        while True:
            # Polls are coalesced to retain only status transitions and the final state.
            response = self.api.get("/agent/runs/" + rid)
            self.expect(response.status_code == 200, "agent polling HTTP 200", {"status": response.status_code})
            value = response.json()
            if value["status"] != last_status:
                self.value["steps"].append({"method": "GET", "path": "/agent/runs/" + rid,
                    "actual_status": 200, "actual": redact(value), "since_turn_seconds": round(time.monotonic()-start, 3)})
                last_status = value["status"]
            if value["status"] not in ("queued", "running"):
                break
            if time.monotonic() >= deadline:
                self.value["model_timeout_actual"] = redact(value)
                raise TimeoutError("local real-model worker did not finish within deadline")
            time.sleep(0.5)
        self.value.setdefault("model_runs", []).append({"run_id": rid, "status": value["status"],
            "seconds": round(time.monotonic()-start, 3), "input": text, "error": value.get("error"),
            "model": self.args.model_name, "mode": "production HTTP agent worker, real provider"})
        self.trace(rid)
        self.expect(value["status"] != "failed", "real provider run completes without error", value.get("error"))
        return value

    def trace(self, rid):
        if not self.args.database:
            return
        uri = Path(self.args.database).resolve().as_uri() + "?mode=ro"
        with sqlite3.connect(uri, uri=True) as db:
            record = db.execute("SELECT state FROM agent_runs WHERE id=? AND user_id=?", (rid, self.user_id)).fetchone()
        if record:
            state = json.loads(record[0])
            self.value.setdefault("model_traces", []).append({"run_id": rid,
                "model_calls": state.get("model_calls"), "tool_calls": state.get("tool_calls"),
                "usage": state.get("usage"), "turn_messages": redact(state.get("turn_messages", []))})

    def decision(self, value, **choices):
        body = {"decision": "confirm", "token": value["preview"]["token"], **choices}
        if value["preview"]["kind"] == "batch":
            body["selected_group_ids"] = [g["id"] for g in value["preview"]["groups"]]
        return self.request("POST", "/agent/runs/" + value["id"] + "/decision", body), body

    def close(self):
        if self.session:
            try:
                self.request("POST", "/auth/logout", {"logout_token": self.session["logout_token"]}, expected=204)
            except Exception as exc:
                self.value["logout_error"] = type(exc).__name__
        self.api.close()


def operations(preview):
    return [op for group in preview.get("groups", []) for op in group["operations"]] if preview["kind"] == "batch" else [preview]


def manual_conflict(e):
    e.setup(courses=True)
    original = e.timetable()
    first = next(c for c in original if c["title"] == "合成第一课")
    later = next(c for c in original if c["title"] == "合成后续课")
    before_revision = e.revision()
    body = e.event_body(before_revision)
    p = e.request("POST", "/events/conflict-preview", body)
    impact = p["impact"]
    e.expect([c["occurrence_id"] for c in impact["course_conflicts"]] == [first["id"]],
             "only the occurrence containing stated 09:15 start conflicts; later 10:10 course is not forced into leave", impact)
    e.expect(impact["new_fixed_conflicts"][0]["overlap_at_start"], "start-point evidence is explicit", impact)
    e.expect(e.revision() == before_revision and not any(r["resource_type"] == "event" for r in e.calendar()["entries"]),
             "preview has no business write")
    blocked = e.request("POST", "/events", body, expected=422)
    e.expect(blocked["code"] == "CONFIRM_FIXED_CONFLICTS", "unconfirmed conflict is rejected", blocked)
    confirmed = {**body, "confirm_fixed_conflicts": True}
    key = {"Idempotency-Key": "aic-overlap-" + secrets.token_hex(5)}
    saved = e.request("POST", "/events", confirmed, expected=201, headers=key)
    repeated = e.request("POST", "/events", confirmed, expected=201, headers=key)
    e.expect(saved == repeated, "duplicate confirmation returns identical receipt")
    e.expect(saved["event"]["time"]["end_at"] is None, "unknown end remains null", saved["event"]["time"])
    after = e.timetable()
    e.expect(all(c.get("attendance_status") is None for c in after), "retaining overlap does not imply course leave", after)
    e.expect(sum(r["resource_type"] == "event" for r in e.calendar()["entries"]) == 1,
             "duplicate confirmation creates exactly one event")
    e.value["actual_summary"] = {"conflict_occurrence": first["id"], "later_occurrence": later["id"],
        "retained_overlap": True, "end_at": None, "confirmed_event_count": 1}


def manual_atomic_leave(e):
    e.setup(courses=True)
    body = e.event_body()
    p = e.request("POST", "/events/conflict-preview", body)
    target = p["impact"]["course_conflicts"][0]["occurrence_id"]
    initial_revision = e.revision()
    e.request("POST", "/events", {**body, "course_leave_targets": [target, "invalid-synthetic-occurrence"]}, expected=422)
    e.expect(e.revision() == initial_revision and all(c.get("attendance_status") is None for c in e.timetable()),
             "invalid combined choice rolls back all changes")
    e.expect(not any(r["resource_type"] == "event" for r in e.calendar()["entries"]), "failed atomic save creates no event")
    chosen = {**body, "course_leave_targets": [target]}
    key = {"Idempotency-Key": "aic-leave-" + secrets.token_hex(5)}
    saved = e.request("POST", "/events", chosen, expected=201, headers=key)
    repeated = e.request("POST", "/events", chosen, expected=201, headers=key)
    e.expect(saved == repeated, "atomic save replay has identical receipt")
    table = e.timetable()
    e.expect([c["id"] for c in table if c.get("attendance_status") == "leave"] == [target],
             "only selected occurrence is marked leave", table)
    e.expect(all(c.get("attendance_status") is None for c in e.timetable(2)), "same courses in next week retain attendance")
    e.expect(saved["event"]["time"]["end_at"] is None, "atomic leave does not invent meeting end")
    e.value["actual_summary"] = {"event_and_leave_saved": True, "selected_occurrences": [target], "next_week_changed": False}


def stale_confirmation(e):
    e.setup(courses=True)
    body = e.event_body()
    e.request("POST", "/events/conflict-preview", body)
    e.request("POST", "/items", {"semester_id": e.sid, "kind": "task", "title": "合成后续修改"}, expected=201)
    stale = e.request("POST", "/events", {**body, "confirm_fixed_conflicts": True}, expected=409)
    e.expect(stale["code"] == "SNAPSHOT_STALE", "expired revision is rejected", stale)
    e.expect(not any(r["resource_type"] == "event" for r in e.calendar()["entries"]), "expired confirmation has no event write")
    e.value["actual_summary"] = {"expired_status": 409, "new_event_count": 0}


def model_event_leave_undo(e):
    e.setup(courses=True)
    before = e.timetable()
    first = next(c for c in before if c["title"] == "合成第一课")
    request = f"请记录：{e.day:%Y年%m月%d日}09:15开合成项目会，结束时间未定，地点示例楼A101。我确定参加，提前30分钟提醒。请核对与课表的冲突。"
    value = e.ask(request)
    e.expect(value["status"] == "needs_confirmation", "real model produces confirmation preview", value)
    p = value["preview"]
    event = next(op for op in operations(p) if op["kind"] == "event")
    time_value = event["after"]["time"]
    e.expect(datetime.fromisoformat(time_value["at"]) == datetime.fromisoformat(e.at(9, 15)) and time_value["end_at"] is None,
             "model retains exact stated start and unknown end", time_value)
    e.expect(event["after"]["reminder_minutes"] == [30], "real model retains 30-minute reminder", event["after"])
    impact = p.get("impact", event.get("impact", {}))
    targets = [c["occurrence_id"] for c in impact["course_conflicts"]]
    e.expect(targets == [first["id"]], "model preview conflicts only with containing course occurrence", impact)
    e.expect(not any(r["resource_type"] == "event" for r in e.calendar()["entries"]), "model preview is not saved")
    body = {"decision": "confirm", "token": p["token"]}
    if p["kind"] == "batch":
        body["selected_group_ids"] = [g["id"] for g in p["groups"]]
    url = "/agent/runs/" + value["id"]
    e.request("POST", url + "/decision", body, expected=422)
    e.request("POST", url + "/decision", {**body, "course_leave_targets": [first["id"], "invalid-synthetic-occurrence"]}, expected=422)
    e.expect(all(c.get("attendance_status") is None for c in e.timetable()), "failed agent consent changes no attendance")
    saved, chosen = e.decision(value, course_leave_targets=[first["id"]])
    repeated = e.request("POST", url + "/decision", chosen)
    e.expect(repeated == saved, "agent duplicate confirmation returns identical receipt")
    e.expect([c["id"] for c in e.timetable() if c.get("attendance_status") == "leave"] == [first["id"]],
             "agent confirmation atomically saves selected occurrence leave")
    e.expect(all(c.get("attendance_status") is None for c in e.timetable(2)), "agent save retains future attendance")
    undo = e.request("POST", url + "/request-undo", {"request_id": "aic-undo-" + secrets.token_hex(5)}, expected=201)
    e.expect(undo["status"] == "needs_confirmation", "undo is previewed")
    undone, undo_body = e.decision(undo)
    e.expect(undone["receipt"]["undone"], "confirmed undo succeeds", undone)
    e.expect(e.request("POST", "/agent/runs/" + undo["id"] + "/decision", undo_body) == undone,
             "duplicate undo returns identical receipt")
    e.expect(all(c.get("attendance_status") is None for c in e.timetable()), "undo restores original attendance")
    e.expect(not any(r["resource_type"] == "event" for r in e.calendar()["entries"]), "undo removes active meeting")
    e.value["actual_summary"] = {"model_start_at": time_value["at"], "model_end_at": None,
        "reminder_minutes": [30], "conflicted_course_count": 1, "atomic_undo_restored": True}


def model_notice(e):
    e.setup()
    source = f"通知：{e.day:%Y年%m月%d日}14:40到示例楼A101集合，15:00正式开始合成项目交流会，结束时间未定，参会同学为全体成员。另外请填写合成共享表，具体截止时间没有公布。"
    value = e.ask(source, input_kind="notice")
    e.expect(value["status"] == "needs_confirmation", "real notification model produces grouped preview", value)
    ops = operations(value["preview"])
    event = next(op["after"] for op in ops if op["kind"] == "event")
    task = next(op["after"] for op in ops if op["kind"] == "item")
    e.expect(datetime.fromisoformat(event["time"]["at"]) == datetime.fromisoformat(e.at(15)) and event["time"]["end_at"] is None,
             "15:00 formal start is retained; gathering is not interpreted as event duration", event)
    e.expect(event["details"]["early_arrival_minutes"] == 20, "14:40 gathering is explicit 20-minute early arrival", event["details"])
    e.expect(task["time"]["precision"] == "unknown" and task["time"]["at"] is None,
             "shared form task does not borrow meeting time as deadline", task["time"])
    e.expect(e.revision() == 0, "notice preview writes no business records")
    # A same-source structured API counterpart is a service-call sample. Input
    # fields are supplied from ground truth; it does not measure human entry.
    paired = e.request("POST", "/semesters", {"name": "AIC同源结构化API对照（合成）",
        "first_monday": e.monday.isoformat(), "total_weeks": 20,
        "periods": [{"number": 1, "start": "09:00", "end": "10:00"}]}, expected=201)
    structured_event = {"semester_id": paired["id"], "expected_revision": 0,
        "title": "合成项目交流会", "certainty": "formal", "time": {"precision":"exact", "at":e.at(15)},
        "details": {"early_arrival_minutes":20}, "location":"示例楼A101", "source_text":source}
    structured_task = {"semester_id":paired["id"], "expected_revision":0, "kind":"task",
        "title":"填写合成共享表", "certainty":"formal", "time":{"precision":"unknown"}, "source_text":source}
    pair_start = time.monotonic()
    event_preview = e.request("POST", "/events/conflict-preview", structured_event)
    task_preview = e.request("POST", "/items/conflict-preview", structured_task)
    pair_seconds = round(time.monotonic()-pair_start, 3)
    e.value["automation_comparison"] = {"same_source_text":source, "sample_count_each":1,
        "known_ground_truth":{"formal_start":e.at(15),"early_arrival_minutes":20,"event_end_at":None,"task_deadline_precision":"unknown"},
        "structured_api_supplied_fields":{"event":structured_event,"task":structured_task},
        "structured_api_preview_seconds":pair_seconds,
        "real_model_preview_seconds":e.value["model_runs"][-1]["seconds"],
        "limitations":["structured fields supplied beforehand; excludes field entry and extraction time",
                       "automated service-call samples only; different input methods and endpoints",
                       "not a human efficiency comparison or overall accuracy statistic"]}
    saved, chosen = e.decision(value)
    e.expect(e.request("POST", "/agent/runs/" + value["id"] + "/decision", chosen) == saved,
             "multi-item confirmation replay is idempotent")
    e.value["actual_summary"] = {"operations": len(ops), "event_start": event["time"]["at"],
        "event_end": None, "arrival_lead": 20, "task_deadline_precision": task["time"]["precision"]}


def model_free_scope(e):
    e.setup(availability=("19:00", "21:00"))
    revision = e.revision()
    date_text = f"{e.day:%Y年%m月%d日}"
    ordinary = e.ask(date_text + "14:00到16:00之间，有没有至少一小时的日程空档可约朋友？")
    e.expect(ordinary["status"] == "completed" and ordinary["preview"] is None, "ordinary free query completes with no write preview", ordinary)
    data = next(c["data"] for c in ordinary["cards"] if c["kind"] == "windows")
    e.expect(data["scope"] == "calendar" and bool(data["windows"]), "ordinary free time is not restricted to 19:00–21:00 study preference", data)
    e.expect(any(datetime.fromisoformat(w["start_at"]) == datetime.fromisoformat(e.at(14)) and
                 datetime.fromisoformat(w["end_at"]) == datetime.fromisoformat(e.at(16)) for w in data["windows"]),
             "ordinary query returns exact requested 14:00–16:00 window", data["windows"])
    study = e.ask(date_text + "在我已保存的学习时段内，有没有至少一小时可以学习？")
    e.expect(study["status"] == "completed" and study["preview"] is None, "study free query completes without write", study)
    sd = next(c["data"] for c in study["cards"] if c["kind"] == "windows")
    e.expect(sd["scope"] == "study" and bool(sd["windows"]), "explicit study query uses saved preference", sd)
    e.expect(all(datetime.fromisoformat(w["start_at"]) >= datetime.fromisoformat(e.at(19)) and
                 datetime.fromisoformat(w["end_at"]) <= datetime.fromisoformat(e.at(21)) for w in sd["windows"]),
             "learning result stays inside 19:00–21:00 preference", sd["windows"])
    e.expect(e.revision() == revision, "both queries preserve business revision")
    e.value["actual_summary"] = {"calendar_scope": data["scope"], "calendar_windows": data["windows"],
        "study_scope": sd["scope"], "study_windows": sd["windows"]}


def plan_request(e, items):
    return {"days": 7, "lead_minutes": 0, "chunk_minutes": 60, "allow_partial": False,
            "tasks": [{"item_id": i["id"]} for i in items], "window_start_at": e.at(9), "window_end_at": e.at(13)}


def accept(e, p):
    return e.request("POST", "/plan-proposals/" + p["id"] + "/accept",
        {"expected_version": p["version"], "expected_revision": p["base_revision"]})


def solver_schedule(e):
    e.setup(availability=("09:00", "13:00"))
    batch = e.request("POST", "/imports", {"semester_id": e.sid, "source": "manual", "courses": [
        {"title": "合成固定课", "weekday": e.day.isoweekday(), "weeks": [1], "sections": [2]}]}, expected=201)
    e.request("POST", "/imports/" + batch["id"] + "/apply", {"expected_revision": batch["base_revision"]})
    fixed = e.timetable()
    items = [e.task("合成排程任务A", 90, True), e.task("合成排程任务B", 60, False)]
    p = e.request("POST", e.path + "/plan-proposals", plan_request(e, items), expected=201)
    e.expect(p["status"] == "FEASIBLE_COMPLETE" and p["can_apply"], "production solver produces complete feasible proposal", p)
    before = e.request("GET", e.path + "/plans")
    e.expect(not before["blocks"], "proposal does not create saved blocks")
    spans = sorted((datetime.fromisoformat(b["start_at"]), datetime.fromisoformat(b["end_at"])) for b in p["blocks"])
    e.expect(all(a >= datetime.fromisoformat(e.at(9)) and b <= datetime.fromisoformat(e.at(13)) for a,b in spans), "all blocks remain in requested window", p["blocks"])
    e.expect(all(b <= datetime.fromisoformat(e.at(10,10)) or a >= datetime.fromisoformat(e.at(11)) for a,b in spans), "solver avoids fixed course 10:10–11:00", p["blocks"])
    e.expect(all(b <= c for (_,b),(c,_) in zip(spans, spans[1:])), "scheduled blocks do not overlap")
    receipt = accept(e, p)
    e.expect(accept(e, p) == receipt, "plan acceptance is idempotent")
    feed = e.request("GET", e.path + "/plans")
    e.expect(sum(b["minutes"] for b in feed["blocks"]) == 150 and not feed["invalid_blocks"], "saved plan covers 150 minutes without invalid blocks", feed)
    e.expect(e.timetable() == fixed, "scheduling retains fixed course facts")
    e.expect(all(e.request("GET", "/items/" + i["id"])["remaining_minutes"] == i["remaining_minutes"] for i in items), "scheduled work is not marked completed")
    undone = e.request("POST", "/plan-proposals/" + p["id"] + "/undo", {"expected_version": receipt["proposal_version"], "expected_revision": feed["revision"]})
    e.expect(undone["undone"], "latest unmodified plan can be undone")
    active = [b for b in e.request("GET", e.path + "/plans")["blocks"] if b["status"] == "active"]
    e.expect(not active, "safe undo leaves no active blocks")
    e.value["actual_summary"] = {"scheduled_minutes": 150, "solver_status": p.get("solver_status"),
        "solver_version": p.get("solver_version"), "complete": True, "safe_undo": True}


def solver_replan(e):
    e.setup(availability=("09:00", "13:00"))
    items = [e.task("合成重排任务A"), e.task("合成重排任务B")]
    p = e.request("POST", e.path + "/plan-proposals", plan_request(e, items), expected=201)
    e.expect(p["status"] == "FEASIBLE_COMPLETE", "initial two-task proposal is complete", p)
    accept(e, p)
    blocks = sorted(e.request("GET", e.path + "/plans")["blocks"], key=lambda b: b["start_at"])
    e.expect(len(blocks) == 2, "two unsplittable tasks produce two blocks", blocks)
    moving, locked = blocks
    e.request("PATCH", "/plan-blocks/" + locked["id"] + "/lock", {"expected_version": locked["version"], "locked": True})
    before = e.request("GET", e.path + "/plans")["blocks"]
    e.request("POST", "/plan-blocks/" + locked["id"] + "/cancel", {"expected_version": 2}, expected=422)
    change = e.request("POST", e.path + "/changes", {"kind": "block", "title": "合成临时活动",
        "source_text": "确认在原任务时段参加活动", "start_at": moving["start_at"], "end_at": moving["end_at"]}, expected=201)
    e.expect(e.request("GET", e.path + "/plans")["blocks"] == before, "reality preview preserves saved plans")
    applied = e.request("POST", "/changes/" + change["id"] + "/apply", {"expected_revision": change["base_revision"]})
    e.expect(e.request("POST", "/changes/" + change["id"] + "/apply", {"expected_revision": change["base_revision"]}) == applied,
             "reality acceptance is idempotent")
    e.expect(e.request("GET", e.path + "/plans")["blocks"] == before, "reality confirmation does not silently replan")
    r = e.request("POST", e.path + "/replan-proposals", {"lead_minutes": 0}, expected=201)
    e.expect(r["status"] == "FEASIBLE_COMPLETE" and r["moved_tasks"] == 1, "minimal replan moves exactly one affected task", r)
    e.expect(r["shift_minutes"] == 120, "minimum offset is 120 minutes with adjacent task locked", r.get("shift_minutes"))
    e.expect(e.request("GET", e.path + "/plans")["blocks"] == before, "replan preview preserves saved blocks")
    accepted = accept(e, r)
    after = e.request("GET", e.path + "/plans")
    e.expect({b["id"] for b in after["blocks"]} == {b["id"] for b in before}, "replan preserves block identities")
    locked_after = next(b for b in after["blocks"] if b["id"] == locked["id"])
    e.expect(locked_after["start_at"] == locked["start_at"] and locked_after["locked"], "locked task retains time and lock", locked_after)
    e.expect(sum(b["minutes"] for b in after["blocks"]) == 120 and not after["invalid_blocks"], "replan conserves work and removes conflicts", after)
    e.request("POST", "/plan-proposals/" + r["id"] + "/undo", {"expected_version": accepted["proposal_version"], "expected_revision": after["revision"]}, expected=409)
    e.expect(e.request("GET", e.path + "/plans")["blocks"] == after["blocks"], "unsafe undo is rejected without changing blocks")
    activity = next(o for o in e.request("GET", e.path + "/changes")["occurrences"] if o["title"] == "合成临时活动")
    cancel = e.request("POST", e.path + "/changes", {"kind": "cancel", "targets": [activity["id"]],
        "title": activity["title"], "source_text": "合成新通知取消活动"}, expected=201)
    cancelled = e.request("POST", "/changes/" + cancel["id"] + "/apply", {"expected_revision": cancel["base_revision"]})
    undone = e.request("POST", "/plan-proposals/" + r["id"] + "/undo", {"expected_version": accepted["proposal_version"], "expected_revision": cancelled["revision"]})
    e.expect(undone["undone"], "undo succeeds once conflicting reality is explicitly cancelled")
    restored = e.request("GET", e.path + "/plans")["blocks"]
    e.expect(sorted((b["id"],b["start_at"],b["end_at"]) for b in restored) == sorted((b["id"],b["start_at"],b["end_at"]) for b in before), "safe replan undo restores original block times")
    e.value["actual_summary"] = {"moved_tasks": r["moved_tasks"], "shift_minutes": r["shift_minutes"],
        "locked_unchanged": True, "unsafe_undo_status": 409, "cancel_then_safe_undo": True,
        "optimal": r.get("optimal"), "phases": r.get("phases")}


CASES = {
    "manual_unknown_end_conflict": (manual_conflict, "09:15 start conflicts only with 09:00–10:00 course; preserve null end; retain overlap choice and duplicate save"),
    "manual_atomic_leave": (manual_atomic_leave, "event+selected occurrence leave save atomically; invalid selection rolls back; future courses unchanged"),
    "expired_confirmation": (stale_confirmation, "business revision mutation rejects old conflict consent with 409 and no event write"),
    "model_event_leave_undo": (model_event_leave_undo, "real DeepSeek produces start-only event preview, exact conflict, reminder; chosen occurrence leave and event undo atomically"),
    "model_multi_notice": (model_notice, "real DeepSeek retains early gathering vs formal start, unknown end and unknown independent task deadline"),
    "model_free_vs_study": (model_free_scope, "ordinary calendar gap query can use 14:00–16:00; explicit study query obeys 19:00–21:00 preference; no writes"),
    "solver_schedule_and_undo": (solver_schedule, "real OR-Tools fits 150 minutes, avoids fixed course, previews read-only, preserves remaining work, confirms idempotently and safely undoes"),
    "solver_locked_replan_and_undo": (solver_replan, "one affected task moves minimally; lock and identities/work preserved; unsafe undo rejected, explicit reality cancellation enables undo"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute-local", action="store_true", help="explicit gate for actual HTTP execution")
    parser.add_argument("--base-url", default=LOCAL_BASE)
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / "evidence")
    parser.add_argument("--database", type=Path, help="isolated SQLite only; read-only own-run trace lookup")
    parser.add_argument("--model-name", default=os.environ.get("DEEPSEEK_MODEL", "deepseek-flash"))
    parser.add_argument("--model-timeout", type=int, default=180)
    parser.add_argument("--cases", nargs="*", choices=list(CASES))
    args = parser.parse_args()
    if args.base_url.rstrip("/") != LOCAL_BASE:
        parser.error("base URL must be isolated local http://127.0.0.1:8874")
    if not args.execute_local:
        print(json.dumps({"execute": False, "case_names": list(CASES), "gate": "requires --execute-local; no HTTP issued"}))
        return
    if args.database and not args.database.is_file():
        parser.error("isolated database path must already exist")
    start = datetime.now(TZ)
    report = {"created_at": start.isoformat(), "base_url": LOCAL_BASE, "source": "fresh automated HTTP samples",
        "boundaries": ["synthetic new accounts only", "local isolated database", "real provider for model cases",
                       "no human efficiency claim", "no real device/OEM delivery claim"], "cases": []}
    for name in args.cases or list(CASES):
        function, expectation = CASES[name]
        e = Evidence(args, name, expectation)
        try:
            function(e)
            e.value["passed"] = True
        except Exception as exc:
            # Only exception type and known assertion labels are logged; HTTP bodies
            # are already captured with field-level secret redaction.
            e.value["failure"] = {"type": type(exc).__name__, "message": str(exc) if isinstance(exc,(AssertionError,TimeoutError)) else "inspect captured steps"}
        finally:
            e.close()
        e.value["seconds"] = round(time.monotonic() - e.started, 3)
        write_json(args.output / (name + ".json"), e.value)
        report["cases"].append({k:v for k,v in e.value.items() if k not in ("steps", "model_traces")})
        print(json.dumps({"case":name,"passed":e.value["passed"],"seconds":e.value["seconds"],"failure":e.value.get("failure")}, ensure_ascii=False), flush=True)
        report["passed"] = all(c["passed"] for c in report["cases"])
        report["finished_at"] = datetime.now(TZ).isoformat()
        write_json(args.output / "backend-report.json", report)
    if not report["passed"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
