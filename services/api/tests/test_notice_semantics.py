import json
import pytest
from test_foundation import client, register, semester
from test_agent import thread, turn, run, call


def test_no_deadline_expression_and_notice_details_are_optional_and_validated(client):
    _, h = register(client); s = semester(client, h)
    body = {'semester_id': s['id'], 'kind': 'task', 'title': '修改群昵称',
        'time': {'precision': 'unknown', 'expression': '方便时发'},
        'details': {'recipient': '班级联络人', 'materials': ['电子照片'],
                    'submission_channel': '班级群', 'conditions': ['申请补办者']}}
    result = client.post('/api/v1/items', headers=h, json=body)
    assert result.status_code == 201, result.text
    saved = result.json()
    assert saved['time']['expression'] == '方便时发'
    assert saved['anchor_at'] is None and saved['remaining_minutes'] is None
    assert saved['details']['materials'] == ['电子照片']
    assert client.post('/api/v1/items', headers=h, json={**body,
        'details': {'early_arrival_minutes': -1}}).status_code == 422
    assert client.post('/api/v1/items', headers=h, json={**body,
        'details': {'privileged_user_id': 'other'}}).status_code == 422
    old = {**body, 'expected_version': 1, 'change_reason': '修改标题', 'title': '改班级群昵称'}
    old.pop('details'); old['time'] = {'precision': 'unknown'}
    edited = client.patch('/api/v1/items/' + saved['id'], headers=h, json=old)
    assert edited.status_code == 200, edited.text
    assert edited.json()['details'] == saved['details']
    assert edited.json()['time']['expression'] == '方便时发'


def test_paper_delivery_window_does_not_create_deadline_or_fixed_occupancy(client):
    _, h = register(client); s = semester(client, h)
    result = client.post('/api/v1/items', headers=h, json={'semester_id': s['id'],
        'kind': 'task', 'title': '纸质材料送交', 'time': {'precision': 'exact',
            'meaning': 'window', 'expression': '10月9日9点至18点任选时间送交',
            'at': '2026-10-09T09:00:00+08:00', 'end_at': '2026-10-09T18:00:00+08:00'}})
    assert result.status_code == 201, result.text
    assert result.json()['anchor_at'] is None
    value = client.get('/api/v1/semesters/' + s['id'] + '/calendar', headers=h,
        params={'from_date': '2026-10-09', 'to_date': '2026-10-09'}).json()
    entry = value['entries'][0]
    assert entry['fixed'] is False and entry['start_at'] is None and entry['end_at'] is None
    assert entry['due_at'] is None
    from app.reminder_rules import instant
    assert instant(entry['time']['end_at']).isoformat() == '2026-10-09T10:00:00+00:00'
    assert value['fixed_conflicts'] == []
    insights = client.get('/api/v1/semesters/' + s['id'] + '/insights', headers=h,
        params={'from_date': '2026-10-09', 'to_date': '2026-10-09'}).json()
    assert insights['records'][0]['due_at'] is None


@pytest.mark.parametrize('time', [
    {'precision': 'unknown', 'expression': '尽快'},
    {'precision': 'unknown', 'expression': '等通知'},
    {'precision': 'date', 'date': '2026-10-09', 'expression': '预计10月9日'},
    {'precision': 'unknown', 'meaning': 'candidate', 'candidate_dates': ['2026-10-09', '2026-10-10'], 'expression': '9日或10日'},
    {'precision': 'unknown', 'meaning': 'course_anchor', 'course_anchor': {'title': '示例课程', 'week': 12, 'sections': [2]}, 'expression': '第12周第2节课前'},
    {'precision': 'week', 'week': 12, 'expression': '第12周考试'},
])
def test_partial_time_is_saved_without_fabricated_instants(client, time):
    _, h = register(client); s = semester(client, h)
    result = client.post('/api/v1/items', headers=h, json={'semester_id': s['id'],
        'kind': 'task', 'title': '核对通知', 'time': time})
    assert result.status_code == 201, result.text
    assert result.json()['anchor_at'] is None
    assert result.json()['time']['at'] is None


def test_meeting_start_without_end_and_later_location_update_preserves_details(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    first = turn(client, h, tid, '班会16:30开始，结束和地点待通知')
    run(client, lambda m, t: call('prepare_event', {'action': 'create', 'fields': {
        'title': '班会', 'time': {'precision': 'exact', 'at': '2026-10-09T16:30:00+08:00'},
        'details': {'participation': '被选中的参会同学', 'early_arrival_minutes': 10}}}))
    url = '/api/v1/agent/runs/' + first['id']; preview = client.get(url, headers=h).json()['preview']
    assert preview is not None
    assert preview['after']['time']['end_at'] is None
    assert preview['provided_fields'] == ['details', 'time', 'title']
    saved = client.post(url + '/decision', headers=h, json={'decision': 'confirm', 'token': preview['token']}).json()
    eid = saved['receipt']['event']['id']
    assert saved['receipt']['event']['time']['end_at'] is None
    assert saved['receipt']['event']['arrival_at'] == '2026-10-09T08:20:00+00:00'
    follow = turn(client, h, tid, '地点补充为A101', 'later')
    def model(messages, tools):
        if messages[-1]['role'] != 'tool': return call('find_records', {'query': '班会'})
        return call('prepare_event', {'action': 'update', 'event_id': eid, 'fields': {'location': 'A101'}})
    run(client, model)
    url = '/api/v1/agent/runs/' + follow['id']; p = client.get(url, headers=h).json()['preview']
    assert p['after']['details']['early_arrival_minutes'] == 10
    result = client.post(url + '/decision', headers=h, json={'decision': 'confirm', 'token': p['token']})
    assert result.status_code == 200, result.text
    assert result.json()['receipt']['event']['id'] == eid
    assert result.json()['receipt']['event']['location'] == 'A101'


def test_query_card_previews_are_bounded_but_all_targets_are_authorized(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    ids = []
    for i in range(9):
        ids.append(client.post('/api/v1/items', headers=h, json={'semester_id': s['id'],
            'kind': 'task', 'title': '材料登记'}).json()['id'])
    req = turn(client, h, tid, '找材料登记')
    def model(messages, tools):
        if messages[-1]['role'] == 'user': return call('find_records', {'query': '材料登记'})
        assert len(json.loads(messages[-1]['content'])['records']) == 9
        return {'content': '找到**9项**登记，请选择具体记录。'}
    run(client, model)
    result = client.get('/api/v1/agent/runs/' + req['id'], headers=h).json()
    card = result['cards'][0]['data']
    assert len(card['records']) <= 5 and card['total_count'] == 9
    assert card['navigation_query']['query'] == '材料登记'
    assert set(result['ambiguous_ids']) == set(ids)


def test_followup_changes_existing_task_deadline_and_details_without_duplicate(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    item = client.post('/api/v1/items', headers=h, json={'semester_id': s['id'],
        'kind': 'task', 'title': '提交材料', 'details': {'materials': ['申请表']}}).json()
    req = turn(client, h, tid, '提交材料补充电子版10月7日前发班级群')
    def model(messages, tools):
        if messages[-1]['role'] != 'tool': return call('find_records', {'query': '提交材料'})
        return call('prepare_item_change', {'item_id': item['id'], 'fields': {
            'time': {'precision': 'date', 'date': '2026-10-07', 'meaning': 'deadline', 'expression': '10月7日前'},
            'details': {'submission_channel': '班级群'}}})
    run(client, model)
    url = '/api/v1/agent/runs/' + req['id']; p = client.get(url, headers=h).json()['preview']
    assert p is not None
    saved = client.post(url + '/decision', headers=h, json={'decision': 'confirm', 'token': p['token']})
    assert saved.status_code == 200, saved.text
    assert saved.json()['receipt']['item']['id'] == item['id']
    assert saved.json()['receipt']['item']['time']['date'] == '2026-10-07'
    assert saved.json()['receipt']['item']['details']['materials'] == ['申请表']
    assert len(client.get('/api/v1/semesters/' + s['id'] + '/items', headers=h).json()['items']) == 1


def test_undated_notice_does_not_block_unrelated_free_window_query(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    response = client.post('/api/v1/events', headers=h, json={'semester_id': s['id'],
        'title': '等通知的说明会', 'expected_revision': 0})
    assert response.status_code == 201
    req = turn(client, h, tid, '查询空闲时间')
    def model(messages, tools):
        if messages[-1]['role'] != 'tool': return call('find_free_windows', {
            'from_date': '2026-10-09', 'to_date': '2026-10-09', 'duration_minutes': 30})
        value = json.loads(messages[-1]['content'])
        assert not value.get('needs_input')
        return {'content': '已查询设置中的空闲时间。'}
    run(client, model)
    assert client.get('/api/v1/agent/runs/' + req['id'], headers=h).json()['status'] == 'completed'


@pytest.mark.parametrize('include_end', [False, True])
def test_legacy_edit_retains_window_semantics_and_end_when_new_fields_omitted(client, include_end):
    _, h = register(client); s = semester(client, h)
    base = {'semester_id':s['id'], 'kind':'task', 'title':'纸质送交', 'time':{
        'precision':'exact', 'meaning':'window', 'expression':'9点至18点任选时间',
        'at':'2026-10-09T09:00:00+08:00', 'end_at':'2026-10-09T18:00:00+08:00'}}
    saved = client.post('/api/v1/items', headers=h, json=base).json()
    old_time = {'precision':'exact', 'at':saved['time']['at']}
    if include_end: old_time['end_at'] = saved['time']['end_at']
    result = client.patch('/api/v1/items/' + saved['id'], headers=h,
        json={**base, 'time':old_time, 'title':'送交纸质材料', 'expected_version':1, 'change_reason':'改标题'})
    assert result.status_code == 200, result.text
    assert result.json()['time']['meaning'] == 'window'
    assert result.json()['time']['end_at'] == saved['time']['end_at']
    assert result.json()['anchor_at'] is None


def test_start_meaning_on_personal_task_is_not_a_hard_deadline(client):
    _, h = register(client); s = semester(client, h)
    saved = client.post('/api/v1/items', headers=h, json={'semester_id':s['id'], 'kind':'task',
        'title':'开始准备材料', 'time':{'precision':'exact', 'meaning':'start', 'at':'2026-10-09T09:00:00+08:00'}})
    assert saved.status_code == 201, saved.text
    assert saved.json()['anchor_at'] is None


@pytest.mark.parametrize('role,text,tool,fields', [
    ('学委', '学委尽快收齐补办学生证材料；申请人交给学委。帮我记录本人职责。',
        'prepare_item', {'kind':'task', 'title':'收齐补办学生证材料',
            'time':{'precision':'unknown','expression':'尽快'},
            'details':{'responsibility':'班级材料汇总','materials':['申请表','电子照片'],'recipient':'学院事务窗口'}}),
    ('', '我是补办申请人，材料交给学委；帮我记录个人提交。',
        'prepare_item', {'kind':'task','title':'提交补办学生证材料',
            'details':{'responsibility':'个人申请','conditions':['需补办学生证'],'recipient':'学委'}}),
    ('班长', '班长选2人参加说明会并填名册；我先记录选人和填表。',
        'prepare_item', {'kind':'task','title':'选2人参会并填写名册',
            'details':{'responsibility':'组织人选','materials':['参会名册'],'conditions':['选择2名同学']}}),
    ('', '我已被选中参会，10月9日16:30开始，提前10分钟签到。',
        'prepare_event', {'title':'参会并签到','time':{'precision':'exact','at':'2026-10-09T16:30:00+08:00'},
            'details':{'participation':'已被选中参会','early_arrival_minutes':10}}),
    ('', '普通学生可观看公开课，学院工作人员另报送材料；帮我记录观看公开课。',
        'prepare_event', {'title':'观看公开课','details':{'applicability':'普通学生','participation':'观看'}}),
    ('学院工作人员', '学院工作人员需要报送公开课材料；我记录报送工作。',
        'prepare_item', {'kind':'task','title':'报送公开课材料','details':{'applicability':'学院工作人员','responsibility':'材料报送'}}),
    ('', '@示例同学预约教室；全体班会10月9日16:30。帮我记录班会。',
        'prepare_event', {'title':'全体班会','time':{'precision':'exact','at':'2026-10-09T16:30:00+08:00'}}),
    ('', '转发日期9月30日，原消息9月29日12:17：本周二09:00说明会。记录原时间并提示矛盾。',
        'prepare_event', {'title':'说明会','time':{'precision':'exact','at':'2026-09-29T09:00:00+08:00',
            'expression':'原发布9月29日12:17，本周二09:00'},'notes':'通知时刻早于原消息发布时刻，需核对'}),
])
def test_anonymized_notice_contract_preserves_personal_responsibility_and_optional_values(client, role, text, tool, fields):
    # The provider is controlled: this verifies context/tool validation/persistence,
    # not the accuracy of a live model's selection or interpretation.
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    assert client.put('/api/v1/me/profile', headers=h, json={'expected_version':0,'class_role':role}).status_code == 200
    req = turn(client, h, tid, text)
    def model(messages, tools):
        profile = next(json.loads(m['content'])['self_reported_profile'] for m in messages
            if m['role']=='user' and 'self_reported_profile' in (m.get('content') or ''))
        assert profile['class_role'] == role
        assert '班长选2人' in messages[0]['content'] and '不顺延' in messages[0]['content']
        return call(tool, {'action':'create','fields':fields} if tool == 'prepare_event' else {'fields':fields})
    run(client, model)
    url = '/api/v1/agent/runs/' + req['id']; value = client.get(url, headers=h).json()
    assert value['status'] == 'needs_confirmation' and value['preview']['after']['title'] == fields['title']
    assert value['preview']['after']['time']['end_at'] is None
    result = client.post(url + '/decision', headers=h, json={'decision':'confirm','token':value['preview']['token']})
    assert result.status_code == 200, result.text
    saved = result.json()['receipt']['event' if tool == 'prepare_event' else 'item']
    assert saved['details'] == value['preview']['after']['details']
    assert saved['location'] == ''
    if tool == 'prepare_item': assert saved['remaining_minutes'] is None


def test_electronic_deadline_and_paper_window_are_independent_notice_steps(client):
    _, h = register(client); s = semester(client, h); tid = thread(client, h, s['id'])
    req = turn(client, h, tid, '电子材料10月7日前发班级群；纸质10月9日9至18点任选时间送交。')
    groups = [
        {'title':'电子提交', 'operations':[{'tool':'prepare_item','arguments':{'fields':{
            'kind':'task','title':'发电子材料','time':{'precision':'date','date':'2026-10-07','meaning':'deadline'},
            'details':{'submission_channel':'班级群'}}}}]},
        {'title':'纸质送交', 'operations':[{'tool':'prepare_item','arguments':{'fields':{
            'kind':'task','title':'送交纸质材料','time':{'precision':'exact','meaning':'window',
                'at':'2026-10-09T09:00:00+08:00','end_at':'2026-10-09T18:00:00+08:00'}}}}]},
    ]
    run(client, lambda m,t:call('prepare_batch',{'groups':groups}))
    url = '/api/v1/agent/runs/' + req['id']; p = client.get(url, headers=h).json()['preview']
    assert p is not None and p['impact']['fixed_conflicts'] == []
    result = client.post(url + '/decision', headers=h, json={'decision':'confirm','token':p['token'],
        'selected_group_ids':[g['id'] for g in p['groups']]})
    assert result.status_code == 200, result.text
    items = client.get('/api/v1/semesters/' + s['id'] + '/items', headers=h).json()['items']
    assert len(items) == 2 and all(i['anchor_at'] is None for i in items)
    assert {i['time']['meaning'] for i in items} == {'window','deadline'}


def test_explicit_arrival_is_displayed_and_complete_occupancy_includes_it(client):
    from datetime import datetime
    from sqlalchemy.orm import Session
    from app.models import User
    from app.academics import owned_semester
    from app.schedule_api import snapshot
    from app.capacity import calendar_context
    account, h = register(client); s = semester(client, h)
    event = client.post('/api/v1/events', headers=h, json={'semester_id':s['id'],
        'title':'说明会', 'expected_revision':0,
        'time':{'precision':'exact','at':'2026-10-09T15:00:00+08:00','end_at':'2026-10-09T16:00:00+08:00'},
        'details':{'early_arrival_minutes':30}}).json()['event']
    assert event['arrival_at'] == '2026-10-09T06:30:00+00:00'
    value = client.get('/api/v1/semesters/' + s['id'] + '/calendar', headers=h,
        params={'from_date':'2026-10-09','to_date':'2026-10-09'}).json()['entries'][0]
    assert value['start_at'].startswith('2026-10-09T07:00:00')
    assert value['occupancy_start_at'] == event['arrival_at']
    with Session(client.app.state.engine) as db:
        user = db.get(User, account['user']['id']); term = owned_semester(db,user,s['id'])
        snap = snapshot(db,user,term)
        snap[1]['weekly'] = [{'weekday':5,'start':'14:00','end':'17:00'}]
        snap[1]['configured'] = True
        context = calendar_context(*snap[:4], datetime.fromisoformat('2026-10-09T13:00:00+08:00'))
        at_1445 = datetime.fromisoformat('2026-10-09T14:45:00+08:00').timestamp()
        assert not any(a <= at_1445 < b for a,b in context['free'].spans)
    second = client.post('/api/v1/events', headers=h, json={'semester_id':s['id'],
        'title':'其他安排', 'expected_revision':1,
        'time':{'precision':'exact','at':'2026-10-09T14:45:00+08:00','end_at':'2026-10-09T14:55:00+08:00'}})
    assert second.status_code == 422 and second.json()['code'] == 'CONFIRM_FIXED_CONFLICTS'
    second = client.post('/api/v1/events', headers=h, json={'semester_id':s['id'],
        'title':'其他安排', 'expected_revision':1, 'confirm_fixed_conflicts':True,
        'time':{'precision':'exact','at':'2026-10-09T14:45:00+08:00','end_at':'2026-10-09T14:55:00+08:00'}})
    assert second.status_code == 201, second.text
    assert second.json()['fixed_conflicts']
    stats = client.get('/api/v1/semesters/' + s['id'] + '/insights', headers=h,
        params={'from_date':'2026-10-09','to_date':'2026-10-09'}).json()['summary']
    assert stats['occupied_union_minutes'] == 90
