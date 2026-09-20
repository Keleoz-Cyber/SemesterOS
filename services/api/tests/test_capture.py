import json
import pytest
import httpx
from fastapi import HTTPException
from app.text_model import deepseek_text

from test_foundation import client, register, semester


def test_parse_returns_review_candidate_without_creating_item_and_only_applies_once(client):
    _, h = register(client)
    s = semester(client, h)
    def model(_text, _reference, _courses):
        return {'intent': 'create_item', 'item': {'kind': 'assignment', 'title': 'Java报告',
            'time': {'precision': 'date', 'date': '2026-09-25'}, 'remaining_minutes': None},
            'evidence': {'title': 'Java报告'}, 'inferred_fields': ['time.date'], 'questions': []}, {'model': 'synthetic-test'}
    client.app.state.text_model = model
    r = client.post('/api/v1/capture/text', headers=h, json={'semester_id': s['id'], 'text': '周五交Java报告',
                                                         'reference_at': '2026-09-20T12:00:00+08:00'})
    assert r.status_code == 200, r.text
    c = r.json()
    assert c['review_state'] == 'pending'
    assert c['item']['time']['precision'] == 'date'
    assert c['item']['remaining_minutes'] is None
    assert client.get(f"/api/v1/semesters/{s['id']}/items", headers=h).json()['items'] == []
    body = {**c['item'], 'semester_id': s['id'], 'candidate_id': c['id'], 'source_text': '不可覆盖原文'}
    a = client.post('/api/v1/items', headers=h, json=body)
    assert a.status_code == 201, a.text
    assert a.json()['source_text'] == '周五交Java报告'
    assert client.post('/api/v1/items', headers=h, json=body).status_code == 409


def test_model_cannot_associate_other_users_course_or_execute_a_change(client):
    _, h = register(client)
    s = semester(client, h)
    client.app.state.text_model = lambda *a: ({'intent': 'create_item', 'item': {'kind': 'task', 'title': '事项',
        'course_id': 'other-account-course'}, 'evidence': {}, 'inferred_fields': [], 'questions': []}, {})
    r = client.post('/api/v1/capture/text', headers=h, json={'semester_id': s['id'], 'text': '测试通知'})
    assert r.status_code == 502
    client.app.state.text_model = lambda *a: ({'intent': 'report_change', 'item': None,
        'evidence': {}, 'inferred_fields': [], 'questions': ['请通过现实变化核对流程处理']}, {})
    r = client.post('/api/v1/capture/text', headers=h, json={'semester_id': s['id'], 'text': '把概率论改到周五'})
    assert r.status_code == 200
    assert r.json()['intent'] == 'report_change'
    assert r.json()['item'] is None
    assert client.get(f"/api/v1/semesters/{s['id']}/items", headers=h).json()['items'] == []


def test_unconfigured_model_is_explicitly_unavailable(client, monkeypatch):
    monkeypatch.delenv('DEEPSEEK_API_KEY', raising=False)
    _, h = register(client)
    s = semester(client, h)
    r = client.post('/api/v1/capture/text', headers=h, json={'semester_id': s['id'], 'text': '测试'})
    assert r.status_code == 503
    assert r.json()['code'] == 'MODEL_UNAVAILABLE'


def test_malformed_outer_provider_json_retries_once_then_returns_sanitized_error(monkeypatch):
    calls = []
    class Client:
        def __init__(self, **kwargs): pass
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def post(self, *args, **kwargs):
            calls.append(True)
            return httpx.Response(200, content=b'not-json')
    monkeypatch.setenv('DEEPSEEK_API_KEY', 'synthetic-test-value')
    monkeypatch.setattr(httpx, 'Client', Client)
    with pytest.raises(HTTPException) as e:
        deepseek_text('合成通知', '2026-09-20T12:00:00+08:00', [])
    assert e.value.status_code == 502
    assert len(calls) == 2
