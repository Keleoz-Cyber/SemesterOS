from concurrent.futures import ThreadPoolExecutor
from test_foundation import client, register, semester
from test_agent import call, thread, turn, run
from test_agent_batches import batch,group


def create(client,h,sid):
    request=turn(client,h,thread(client,h,sid),'新增一条材料任务')
    run(client,lambda m,t:call('prepare_item',{'fields':{'kind':'task','title':'材料任务'}}))
    url='/api/v1/agent/runs/'+request['id']
    value=client.get(url,headers=h).json()
    result=client.post(url+'/decision',headers=h,json={'decision':'confirm','token':value['preview']['token']})
    assert result.status_code==200,result.text
    return url,result.json()


def test_undo_is_previewed_in_new_run_confirmed_once_and_owner_scoped(client):
    _,h=register(client);_,other=register(client,'other');s=semester(client,h)
    url,saved=create(client,h,s['id']);item_id=saved['receipt']['item']['id']
    assert saved['undo_available'] is True and 'undo_data' not in saved
    data={'request_id':'undo-1'}
    assert client.post(url+'/request-undo',headers=other,json=data).status_code==404
    response=client.post(url+'/request-undo',headers=h,json=data)
    assert response.status_code==201,response.text
    preview=response.json()
    assert client.post(url+'/request-undo',headers=h,json=data).json()==preview
    assert preview['status']=='needs_confirmation'
    assert client.get('/api/v1/items/'+item_id,headers=h).json()['lifecycle']=='active'
    undo_url='/api/v1/agent/runs/'+preview['id']+'/decision'
    decision={'decision':'confirm','token':preview['preview']['token']}
    result=client.post(undo_url,headers=h,json=decision)
    assert result.status_code==200,result.text
    assert client.post(undo_url,headers=h,json=decision).json()==result.json()
    assert result.json()['receipt']['undone'] is True
    assert client.get('/api/v1/items/'+item_id,headers=h).json()['lifecycle']=='cancelled'
    assert client.get(url,headers=h).json()['undo_available'] is False
    assert client.post(url+'/request-undo',headers=h,json={'request_id':'undo-2'}).status_code==409


def test_partial_batch_undo_only_restores_selected_saved_groups(client):
    _,h=register(client);s=semester(client,h)
    url,value=batch(client,h,s['id'],[group('甲'),group('乙')])
    data={'decision':'confirm','token':value['preview']['token'],'selected_group_ids':[value['preview']['groups'][0]['id']]}
    saved=client.post(url+'/decision',headers=h,json=data).json()
    assert saved['undo_available'] is True
    result=client.post(url+'/request-undo',headers=h,json={'request_id':'undo'}).json()
    assert [e['title'] for e in result['preview']['summary']]==['甲']
    response=client.post('/api/v1/agent/runs/'+result['id']+'/decision',headers=h,json={'decision':'confirm','token':result['preview']['token']})
    assert response.status_code==200,response.text
    items=client.get('/api/v1/semesters/'+s['id']+'/items',headers=h).json()['items']
    assert len(items)==1 and items[0]['title']=='甲' and items[0]['lifecycle']=='cancelled'


def test_model_undo_requires_real_action_query(client):
    _,h=register(client);s=semester(client,h);url,saved=create(client,h,s['id'])
    request=turn(client,h,saved['thread_id'],'撤销材料任务','undo-model')
    def model(messages,tools):
        if messages[-1]['role']=='user':return call('list_recent_actions',{})
        return call('prepare_undo',{'run_id':saved['id']})
    run(client,model)
    result=client.get('/api/v1/agent/runs/'+request['id'],headers=h).json()
    assert result['status']=='needs_confirmation',str(result)
    assert result['preview']['kind']=='undo'
    assert client.get(url,headers=h).json()['undo_available'] is True
