from io import BytesIO
import wave
from PIL import Image
from test_foundation import client,register,semester


def png():
    f=BytesIO();im=Image.new('RGB',(80,50),'white');exif=Image.Exif();exif[270]='private metadata';im.save(f,format='PNG',exif=exif);return f.getvalue()


def wav(seconds=1):
    f=BytesIO()
    with wave.open(f,'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000);w.writeframes(b'\0\0'*16000*seconds)
    return f.getvalue()


def setup(client,tmp_path):
    client.app.state.media_root=tmp_path/'media';_,h=register(client);s=semester(client,h)
    return h,s


def upload(client,h,s,data=None,kind='image',key='upload-one'):
    return client.post(f"/api/v1/semesters/{s['id']}/sources?kind={kind}",headers={**h,'Content-Type':'application/octet-stream','Idempotency-Key':key},content=data or png())


def test_media_is_private_sanitized_and_retry_does_not_duplicate(client,tmp_path):
    h,s=setup(client,tmp_path)
    r=upload(client,h,s);assert r.status_code==201,r.text
    source=r.json();again=upload(client,h,s);assert again.json()['id']==source['id']
    data=client.get(f"/api/v1/sources/{source['id']}/content",headers=h)
    assert data.status_code==200 and not Image.open(BytesIO(data.content)).getexif()
    _,other=register(client,'student_b')
    assert client.get(f"/api/v1/sources/{source['id']}",headers=other).status_code==404
    assert client.get(f"/api/v1/sources/{source['id']}/content",headers=other).status_code==404
    assert 'path' not in source


def test_formats_and_duration_are_checked_before_persistence(client,tmp_path):
    h,s=setup(client,tmp_path)
    assert upload(client,h,s,b'not an image').status_code==422
    assert upload(client,h,s,wav(121),'audio').status_code==422
    assert upload(client,h,s,wav(1),'audio').status_code==201


def test_cancelled_job_cannot_publish_late_recognition(client,tmp_path):
    h,s=setup(client,tmp_path);r=upload(client,h,s);assert r.status_code==201
    source=r.json();path=f"/api/v1/sources/{source['id']}"
    queued=client.post(path+'/recognize',headers=h,json={'expected_version':source['version']});assert queued.status_code==202
    from app.media_jobs import claim,publish
    engine=client.app.state.engine;job=claim(engine)
    assert job is not None
    current=client.get(path,headers=h).json()
    assert client.post(path+'/cancel',headers=h,json={'expected_version':current['version']}).status_code==200
    assert not publish(engine,job,{'text':'迟到结果','metadata':{'provider':'test'}})
    assert client.get(path,headers=h).json()['text']==''


def test_expired_lease_is_reclaimed_and_only_new_worker_can_publish(client,tmp_path):
    from sqlalchemy.orm import Session
    from app.models import MediaSource
    from app.media_jobs import claim,publish
    h,s=setup(client,tmp_path);source=upload(client,h,s).json();path=f"/api/v1/sources/{source['id']}"
    client.post(path+'/recognize',headers=h,json={'expected_version':source['version']})
    old=claim(client.app.state.engine)
    with Session(client.app.state.engine) as db:
        row=db.get(MediaSource,source['id']);row.lease_until=0;db.commit()
    new=claim(client.app.state.engine);assert new['token']!=old['token']
    assert not publish(client.app.state.engine,old,{'text':'旧结果'})
    assert publish(client.app.state.engine,new,{'text':'新结果'})
    assert client.get(path,headers=h).json()['text']=='新结果'


def test_source_text_and_item_provenance_survive_original_file_deletion(client,tmp_path):
    h,s=setup(client,tmp_path);source=upload(client,h,s).json();path=f"/api/v1/sources/{source['id']}"
    edited=client.patch(path,headers=h,json={'expected_version':1,'text':'周五交Java报告','reference_at':'2026-09-21T00:00:00Z'}).json()
    client.app.state.text_model=lambda *args:({'intent':'create_item','item':{'kind':'assignment','title':'Java报告','time':{'precision':'unknown'}},'evidence':{},'inferred_fields':['title'],'questions':[]},{'provider':'test'})
    candidate=client.post('/api/v1/capture/text',headers=h,json={'semester_id':s['id'],'text':edited['text'],'reference_at':edited['reference_at'],'source_id':source['id'],'source_version':edited['version']})
    assert candidate.status_code==200,candidate.text
    data={**candidate.json()['item'],'candidate_id':candidate.json()['id']}
    item=client.post('/api/v1/items',headers=h,json=data);assert item.status_code==201,item.text
    assert item.json()['source_id']==source['id']
    removed=client.request('DELETE',path+'/content',headers=h,json={'expected_version':edited['version']});assert removed.status_code==200
    assert client.get(path+'/content',headers=h).status_code==410
    assert client.get(path,headers=h).json()['text']=='周五交Java报告'
    assert client.get('/api/v1/items/'+item.json()['id'],headers=h).json()['source_id']==source['id']


def test_cancel_during_text_model_call_rejects_late_candidate(client,tmp_path):
    from sqlalchemy.orm import Session
    from app.models import MediaSource,TextCandidate
    from sqlalchemy import select,func
    h,s=setup(client,tmp_path);source=upload(client,h,s).json();path=f"/api/v1/sources/{source['id']}"
    edited=client.patch(path,headers=h,json={'expected_version':1,'text':'通知原文','reference_at':'2026-09-21T00:00:00Z'}).json()
    def model(*args):
        with Session(client.app.state.engine) as db:
            row=db.get(MediaSource,source['id']);row.version+=1;row.status='cancelled';db.commit()
        return {'intent':'create_item','item':{'kind':'task','title':'通知原文'},'evidence':{},'inferred_fields':[],'questions':[]},{'provider':'test'}
    client.app.state.text_model=model
    r=client.post('/api/v1/capture/text',headers=h,json={'semester_id':s['id'],'text':edited['text'],'reference_at':edited['reference_at'],'source_id':source['id'],'source_version':edited['version']})
    assert r.status_code==409,r.text
    with Session(client.app.state.engine) as db:assert db.scalar(select(func.count()).select_from(TextCandidate))==0


def test_changed_source_invalidates_unconfirmed_media_candidate(client,tmp_path):
    h,s=setup(client,tmp_path);source=upload(client,h,s).json();path=f"/api/v1/sources/{source['id']}"
    edited=client.patch(path,headers=h,json={'expected_version':1,'text':'报告','reference_at':'2026-09-21T00:00:00Z'}).json()
    client.app.state.text_model=lambda *args:({'intent':'create_item','item':{'kind':'task','title':'报告'},'evidence':{},'questions':[]},{'provider':'test'})
    candidate=client.post('/api/v1/capture/text',headers=h,json={'semester_id':s['id'],'text':edited['text'],'reference_at':edited['reference_at'],'source_id':source['id'],'source_version':edited['version']}).json()
    assert client.post(path+'/cancel',headers=h,json={'expected_version':edited['version']}).status_code==200
    assert client.post('/api/v1/items',headers=h,json={**candidate['item'],'candidate_id':candidate['id']}).status_code==409
