from app.school_periods import HAUT_PERIODS
from test_foundation import client, register, semester


def test_haut_periods_are_previewed_and_applied_with_courses_only_on_confirmation(client):
    _, headers = register(client)
    term = semester(client, headers)
    payload = {'semester_id': term['id'], 'source': 'haut_webview', 'courses': [{
        'title': '学校课程', 'weekday': 1, 'weeks': [1], 'sections': [9, 10]}]}
    preview = client.post('/api/v1/imports', headers=headers, json=payload)
    assert preview.status_code == 201, preview.text
    assert preview.json()['source_periods'] == HAUT_PERIODS
    assert client.get('/api/v1/semesters', headers=headers).json()[0]['periods'] == term['periods']
    assert client.get(f"/api/v1/semesters/{term['id']}/timetable?week=1", headers=headers).json()['events'] == []
    applied = client.post(f"/api/v1/imports/{preview.json()['id']}/apply", headers=headers,
        json={'expected_revision': preview.json()['base_revision']})
    assert applied.status_code == 200, applied.text
    assert applied.json()['periods_updated'] is True
    assert client.get('/api/v1/semesters', headers=headers).json()[0]['periods'] == HAUT_PERIODS
    event = client.get(f"/api/v1/semesters/{term['id']}/timetable?week=1", headers=headers).json()['events'][0]
    assert event['start_at'].endswith('T19:30:00+08:00')
    assert event['end_at'].endswith('T21:05:00+08:00')
    repeated = client.post(f"/api/v1/imports/{preview.json()['id']}/apply", headers=headers,
        json={'expected_revision': preview.json()['base_revision']})
    assert repeated.json() == applied.json()


def test_manual_import_preserves_custom_periods(client):
    _, headers = register(client)
    term = semester(client, headers)
    preview = client.post('/api/v1/imports', headers=headers, json={
        'semester_id': term['id'], 'source': 'manual',
        'courses': [{'title': '手工课', 'weekday': 1, 'weeks': [1], 'sections': [1]}]}).json()
    assert preview['source_periods'] is None
    assert client.post(f"/api/v1/imports/{preview['id']}/apply", headers=headers,
        json={'expected_revision': preview['base_revision']}).status_code == 200
    assert client.get('/api/v1/semesters', headers=headers).json()[0]['periods'] == term['periods']
