import json
from sqlalchemy.orm import Session
from app.models import AgentRun
from test_foundation import client, register, semester
from test_agent import thread, turn, run, call


def test_cached_card_pages_are_private_scoped_and_keep_later_target_selection(client):
    _, h = register(client); _, other = register(client,'student_b')
    s = semester(client,h); tid = thread(client,h,s['id'])
    ids = []
    for i in range(36):
        ids.append(client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],
            'kind':'task','title':'材料登记','location':'A' + str(i)}).json()['id'])
    req = turn(client,h,tid,'查找材料登记')
    def model(messages,tools):
        if messages[-1]['role']=='user':return call('find_records',{'query':'材料登记'})
        return {'content':'找到多项材料登记，请选择具体记录。'}
    run(client,model)
    url = '/api/v1/agent/runs/' + req['id']
    value = client.get(url,headers=h).json(); card = value['cards'][0]
    assert 'card_pages' not in value
    assert len(card['data']['records']) == 5 and card['total_count'] == 36
    assert card['has_more'] is True and card['next_offset'] == 5
    page_url = url + '/cards/' + card['card_id']
    response = client.get(page_url,headers=h,params={'offset':5,'limit':20})
    assert response.status_code == 200,response.text
    page = response.json()
    assert len(page['card']['data']['records']) == 20 and page['has_more'] is True and page['next_offset'] == 25
    chosen = page['card']['data']['records'][-1]['id']
    assert chosen not in {r['id'] for r in card['data']['records']}
    tail = client.get(page_url,headers=h,params={'offset':25,'limit':20}).json()
    assert len(tail['card']['data']['records']) == 11 and tail['has_more'] is False and tail['next_offset'] is None
    assert client.get(page_url,headers=other).status_code == 404
    assert client.get(url + '/cards/missing',headers=h).status_code == 404
    assert client.get(page_url,headers=h,params={'limit':51}).status_code == 422
    assert client.get(url,headers=h).json()['sequence'] == value['sequence']
    with Session(client.app.state.engine) as db:
        assert db.get(AgentRun,req['id']).state['model_calls'] == 2
    selected = client.post('/api/v1/agent/threads/' + tid + '/turns',headers=h,
        json={'text':'修改选中记录的地点','request_id':'chosen','selected_record_ids':[chosen]})
    assert selected.status_code == 202,selected.text
    with Session(client.app.state.engine) as db:
        assert chosen in db.get(AgentRun, selected.json()['id']).state['known_ids']
    run(client,lambda m,t:call('prepare_item_change',{'item_id':chosen,'fields':{'location':'已核对地点'}}))
    result = client.get('/api/v1/agent/runs/' + selected.json()['id'],headers=h).json()
    assert result['preview']['target_id'] == chosen
    assert client.get('/api/v1/agent/runs/' + selected.json()['id'] + '/cards/' + card['card_id'],headers=h).status_code == 404


def test_calendar_pages_use_one_contiguous_offset_across_dated_and_undated_entries(client):
    _, h = register(client); s = semester(client,h); tid = thread(client,h,s['id'])
    for i in range(8):
        client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'定日登记' + str(i),
            'time':{'precision':'date','date':'2026-10-09'}})
    for i in range(4):
        client.post('/api/v1/items',headers=h,json={'semester_id':s['id'],'kind':'task','title':'等通知' + str(i)})
    req = turn(client,h,tid,'查10月9日安排')
    def model(messages,tools):
        if messages[-1]['role']=='user':return call('query_calendar',{'from_date':'2026-10-09','to_date':'2026-10-09'})
        return {'content':'已查到相关安排。'}
    run(client,model)
    value = client.get('/api/v1/agent/runs/' + req['id'],headers=h).json(); card = value['cards'][0]
    first = card['data']['entries'] + card['data']['undated']
    assert len(first) == 5 and card['total_count'] == 12
    page = client.get('/api/v1/agent/runs/' + req['id'] + '/cards/' + card['card_id'],headers=h,
        params={'offset':card['next_offset'],'limit':20}).json()
    later = page['card']['data']['entries'] + page['card']['data']['undated']
    assert len(later) == 7 and len({r['id'] for r in first+later}) == 12
    assert page['has_more'] is False
