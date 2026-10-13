from datetime import datetime, timezone
from app.capacity import calendar_context, local_day
from test_foundation import client, register, semester


def test_buffers_and_rest_only_reduce_study_windows_not_event_facts():
    s = {'first_monday': '2026-10-12', 'total_weeks': 1, 'periods': [], 'fixed_events': [{
        'id': 'e', 'title': '会议', 'certainty': 'formal', 'reserve_time': True,
        'time': {'precision': 'exact', 'at': '2026-10-12T09:00:00+08:00', 'end_at': '2026-10-12T10:00:00+08:00'}}]}
    settings = {'configured': True, 'weekly': [{'weekday': 1, 'start': '08:00', 'end': '14:00'}],
        'buffer_before_minutes': 15, 'buffer_after_minutes': 10,
        'rest_weekly': [{'weekday': 1, 'start': '12:00', 'end': '13:00'}]}
    c = calendar_context(s, settings, [], [], datetime(2026, 10, 12, 0, tzinfo=timezone.utc))
    base = local_day('2026-10-12').timestamp()
    assert c['free'].spans == [(base+8*3600, base+8*3600+45*60), (base+10*3600+10*60, base+12*3600), (base+13*3600, base+14*3600)]
    assert c['conflicts'] == []
    assert s['fixed_events'][0]['time']['at'] == '2026-10-12T09:00:00+08:00'
    # A just-ended event must still leave the user's after-event buffer.
    c = calendar_context(s, settings, [], [], datetime(2026, 10, 12, 2, 5, tzinfo=timezone.utc))
    assert c['free'].spans[0][0] == base+10*3600+10*60


def test_old_client_preserves_saved_buffers(client):
    _, h = register(client); s = semester(client, h)
    url = f"/api/v1/semesters/{s['id']}/availability"
    r = client.put(url, headers=h, json={'expected_version': 0, 'expected_revision': s['revision'],
        'weekly': [], 'buffer_before_minutes': 15, 'rest_weekly': [{'weekday': 1, 'start': '12:00', 'end': '13:00'}]})
    assert r.status_code == 200, r.text
    value = r.json()
    old = client.put(url, headers=h, json={'expected_version': value['version'], 'expected_revision': value['revision'], 'weekly': [], 'exclusions': []})
    assert old.status_code == 200, old.text
    assert old.json()['buffer_before_minutes'] == 15
    assert old.json()['rest_weekly'] == value['rest_weekly']
