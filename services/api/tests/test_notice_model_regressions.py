import json
from test_foundation import client, register, semester
from test_agent import thread, turn, run, call


def test_notice_fill_task_does_not_borrow_meeting_deadline_or_invent_urgency(client):
    _,h=register(client);s=semester(client,h);tid=thread(client,h,s['id'])
    source='明天15:00在A201举行宣讲会。请各班班委填写共享文档。'
    sent=client.post(f'/api/v1/agent/threads/{tid}/turns',headers=h,json={
        'text':source,'request_id':'shared-notice','input_kind':'notice'}).json()
    groups=[{'title':'宣讲会','operations':[{'tool':'prepare_event','arguments':{'action':'create','fields':{
        'title':'宣讲会','time':{'precision':'exact','at':'2026-10-03T15:00:00+08:00'},'reserve_time':False}}}]},
        {'title':'填写文档','operations':[{'tool':'prepare_item','arguments':{'fields':{'kind':'task','title':'填写共享文档',
        'time':{'precision':'unknown','expression':'明天宣讲会前','meaning':'deadline'},
        'details':{'applicability':'各班班委','conditions':['如为本班班委']}}}}]}]
    run(client,lambda m,t:call('prepare_batch',{'groups':groups}))
    result=client.get('/api/v1/agent/runs/'+sent['id'],headers=h).json()
    assert result['status']=='needs_confirmation',result
    task=result['preview']['groups'][1]['operations'][0]['after']
    assert task['time']['precision']=='unknown' and task['time']['expression']==''
    assert task['details']['conditions']==['如为本班班委']
    from app.agent_tools import normalize_notice_task_time
    fields={'kind':'task','time':{'precision':'unknown','expression':'尽快'}}
    assert normalize_notice_task_time(fields,{'input_kind':'notice'},source)['time']['expression']==''
    explicit={'kind':'task','time':{'precision':'unknown','expression':'下课前'}}
    assert normalize_notice_task_time(explicit,{'input_kind':'notice'},'请下课前填写文档')==explicit
    assert normalize_notice_task_time(fields,{'input_kind':'message'},source)==fields


def test_explicit_nonreservation_is_supported_by_event_tool_and_batch_schema(client):
    _, h = register(client); s = semester(client,h); tid = thread(client,h,s['id'])
    req = turn(client,h,tid,'班长选两人并填名单，保存讲座参考但本人尚未决定参加。')
    groups = [
        {'title':'班长职责','operations':[{'tool':'prepare_item','arguments':{'fields':{
            'kind':'task','title':'选派两人并填写名单','time':{'precision':'unknown'},'certainty':'formal'}}}]},
        {'title':'讲座参考','operations':[{'tool':'prepare_event','arguments':{'action':'create','fields':{
            'title':'讲座参考','time':{'precision':'exact','at':'2026-10-09T15:00:00+08:00'},
            'reserve_time':False,'details':{'participation_status':'other','early_arrival_minutes':30}}}}]},
    ]
    run(client,lambda m,t:call('prepare_batch',{'groups':groups}))
    value = client.get('/api/v1/agent/runs/' + req['id'],headers=h).json()
    assert value['status']=='needs_confirmation',value
    assert value['preview']['groups'][1]['operations'][0]['after']['reserve_time'] is False
    assert value['preview']['groups'][0]['operations'][0]['after']['time']['at'] is None


def test_malformed_tool_json_gets_specific_repair_without_inventing_missing_fields(client):
    _, h = register(client); s = semester(client,h); tid = thread(client,h,s['id'])
    req = turn(client,h,tid,'记录一个无截止任务')
    errors=[]
    def model(messages,tools):
        if messages[-1]['role']=='user':
            value = call('prepare_item',{'fields':{'kind':'task','title':'无截止任务'}})
            value['tool_calls'][0]['function']['arguments'] = value['tool_calls'][0]['function']['arguments'][:-1]
            return value
        errors.append(json.loads(messages[-1]['content']))
        return call('prepare_item',{'fields':{'kind':'task','title':'无截止任务'}})
    run(client,model)
    assert errors[0]['error']['code']=='INVALID_TOOL_JSON'
    value = client.get('/api/v1/agent/runs/' + req['id'],headers=h).json()
    assert value['status']=='needs_confirmation' and value['preview']['after']['time']['at'] is None


def test_notice_policy_distinguishes_hour_window_from_date_range_and_organizer_deadline(client):
    _, h = register(client); s = semester(client,h); tid = thread(client,h,s['id'])
    req = turn(client,h,tid,'电子版10月7日前；纸质10月9日09:00至18:00任选时间送交。')
    def model(messages,tools):
        assert 'range仅用于日期范围' in messages[0]['content']
        assert '活动开始不等于选派、填名单或汇总任务的截止' in messages[0]['content']
        return call('prepare_item',{'fields':{'kind':'task','title':'纸质材料送交',
            'time':{'precision':'exact','meaning':'window','at':'2026-10-09T09:00:00+08:00',
                    'end_at':'2026-10-09T18:00:00+08:00'}}})
    run(client,model)
    value = client.get('/api/v1/agent/runs/' + req['id'],headers=h).json()
    assert value['status']=='needs_confirmation',value
    assert value['preview']['after']['time']['precision']=='exact'


def test_window_misclassified_as_event_still_never_reserves_the_entire_interval(client):
    _, h = register(client); s = semester(client,h)
    window = client.post('/api/v1/events',headers=h,json={'semester_id':s['id'],
        'title':'纸质送交窗口','expected_revision':0,'reserve_time':True,
        'time':{'precision':'exact','meaning':'window','at':'2026-10-09T09:00:00+08:00',
                'end_at':'2026-10-09T18:00:00+08:00'}})
    assert window.status_code==201,window.text
    calendar = client.get('/api/v1/semesters/' + s['id'] + '/calendar',headers=h,
        params={'from_date':'2026-10-09','to_date':'2026-10-09'}).json()
    entry = calendar['entries'][0]
    assert entry['resource_type']=='event' and entry['time']['meaning']=='window'
    assert entry['fixed'] is False and entry['occupancy_start_at'] is None
    assert entry['start_at'] is None and entry['end_at'] is None and entry['due_at'] is None
    own = client.post('/api/v1/events',headers=h,json={'semester_id':s['id'],
        'title':'本人会议','expected_revision':1,'time':{'precision':'exact',
            'at':'2026-10-09T09:30:00+08:00','end_at':'2026-10-09T10:30:00+08:00'}})
    assert own.status_code==201 and own.json()['fixed_conflicts']==[]
    stats = client.get('/api/v1/semesters/' + s['id'] + '/insights',headers=h,
        params={'from_date':'2026-10-09','to_date':'2026-10-09'}).json()['summary']
    assert stats['occupied_union_minutes']==60 and stats['fixed_scheduled_minutes']==60


def test_agent_definite_action_defaults_formal_without_requiring_a_deadline(client):
    _,h=register(client); s=semester(client,h); tid=thread(client,h,s['id'])
    req=turn(client,h,tid,'请记录明确要做的改群昵称，没说截止。')
    run(client,lambda m,t:call('prepare_item',{'fields':{'kind':'task','title':'改群昵称'}}))
    value=client.get('/api/v1/agent/runs/' + req['id'],headers=h).json()
    assert value['status']=='needs_confirmation',value
    assert value['preview']['after']['certainty']=='formal'
    assert value['preview']['after']['time']['precision']=='unknown'
    assert value['preview']['after']['time']['at'] is None


def test_agent_explicit_tentative_notice_remains_qualified(client):
    _,h=register(client); s=semester(client,h); tid=thread(client,h,s['id'])
    req=turn(client,h,tid,'暂定第12周考试，先记录学校通知。')
    run(client,lambda m,t:call('prepare_item',{'fields':{'kind':'exam','title':'示例考试',
        'certainty':'tentative','time':{'precision':'week','week':12,'expression':'暂定第12周'}}}))
    value=client.get('/api/v1/agent/runs/' + req['id'],headers=h).json()
    assert value['status']=='needs_confirmation' and value['preview']['after']['certainty']=='tentative'
    assert value['preview']['after']['time']['at'] is None


def test_notice_policy_keeps_step_recipients_and_completion_times_separate(client):
    _,h=register(client); s=semester(client,h); tid=thread(client,h,s['id'])
    req=turn(client,h,tid,'电子交班级负责人，电子已交；纸质交办公室A201。只记还要办的。')
    def model(messages,tools):
        system=messages[0]['content']
        assert '不同分项的接收者、渠道、地点、材料、期限和参与条件分别归属' in system
        assert '不能把通知截止推成实际提交或完成时间' in system
        assert 'notes只放其他必要说明' in system
        return call('prepare_item',{'fields':{'kind':'task','title':'送交纸质材料','location':'A201',
            'details':{'submission_channel':'纸质送交'},'notes':''}})
    run(client,model)
    value=client.get('/api/v1/agent/runs/' + req['id'],headers=h).json()
    assert value['status']=='needs_confirmation',value
    assert value['preview']['after']['details']['recipient']==''
    assert value['preview']['after']['notes']==''
