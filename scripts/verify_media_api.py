"""Real OCR/ASR -> reviewed transcript -> DeepSeek -> confirmed synthetic item."""
from pathlib import Path
from datetime import datetime,timedelta,timezone
import json,time,secrets,os
import httpx


def main():
    repo=Path(__file__).resolve().parents[1];now=datetime.now(timezone(timedelta(hours=8)))
    username='qa_media_'+secrets.token_hex(4);results=[]
    base=os.environ.get('SEMESTEROS_API_URL','http://127.0.0.1:8871').rstrip('/')
    with httpx.Client(base_url=base+'/api/v1',timeout=65) as api:
        session=api.post('/auth/register',json={'username':username,'password':secrets.token_urlsafe(24)}).json();api.headers['Authorization']='Bearer '+session['access_token']
        monday=now.date()-timedelta(days=now.weekday())
        s=api.post('/semesters',json={'name':'QA多来源录入（合成）','first_monday':monday.isoformat(),'total_weeks':20,'periods':[{'number':1,'start':'08:00','end':'08:50'}]}).json()
        for kind,filename in [('image','notice.png'),('audio','notice.wav')]:
            data=(repo/'output/verification/media'/filename).read_bytes();key=secrets.token_hex(16)
            endpoint=f"/semesters/{s['id']}/sources?kind={kind}";headers={'Content-Type':'application/octet-stream','Idempotency-Key':key}
            r=api.post(endpoint,headers=headers,content=data);assert r.status_code==201,r.status_code
            source=r.json();path='/sources/'+source['id']
            assert api.post(endpoint,headers=headers,content=data).json()['id']==source['id']
            assert api.post(path+'/recognize',json={'expected_version':source['version']}).status_code==202
            deadline=time.monotonic()+60
            while time.monotonic()<deadline:
                source=api.get(path).json()
                if source['status'] not in ('queued','running'):break
                time.sleep(.3)
            assert source['status']=='recognized',{'kind':kind,'status':source['status'],'error':source['error_code']}
            assert '25' in source['text'] and '3' in source['text'],source['text']
            assert source['recognition']['provider']==('RapidOCR' if kind=='image' else 'SenseVoice')
            assert api.get(f"/semesters/{s['id']}/items").json()['items']==[x['item'] for x in reversed(results)]
            edited=api.patch(path,json={'expected_version':source['version'],'text':source['text'],'reference_at':'2026-09-20T00:00:00Z'}).json()
            parsed=api.post('/capture/text',json={'semester_id':s['id'],'text':edited['text'],'reference_at':edited['reference_at'],'source_id':source['id'],'source_version':edited['version']})
            assert parsed.status_code==200,parsed.status_code
            candidate=parsed.json();assert candidate['intent']=='create_item'
            assert candidate['item']['remaining_minutes']==180 and candidate['item']['time']['precision']=='exact'
            at=datetime.fromisoformat(candidate['item']['time']['at']).astimezone(timezone(timedelta(hours=8)))
            assert (at.month,at.day,at.hour,at.minute)==(9,25,23,59)
            item=api.post('/items',json={**candidate['item'],'candidate_id':candidate['id']});assert item.status_code==201,item.status_code
            assert item.json()['source_id']==source['id']
            assert item.json()['parse_evidence']['media_source']['corrected_text']==edited['text']
            results.append({'kind':kind,'provider':source['recognition']['provider'],'recognition_ms':source['recognition']['elapsed_ms'],
                'transcript':source['text'],'parsed_minutes':180,'item':item.json()})
        assert len(api.get(f"/semesters/{s['id']}/items").json()['items'])==2
        api.post('/auth/logout',json={'logout_token':session['logout_token']})
    report={'passed':True,'base_url':base,'source':'synthetic_image_and_windows_tts','account':username,'at':now.isoformat(),
        'cases':[{k:v for k,v in r.items() if k!='item'} for r in results],
        'checks':['private_upload','upload_idempotency','durable_worker','real_ocr','real_asr','no_automatic_item','reviewed_text_saved',
            'real_deepseek','date_and_effort','confirm_required','source_link_preserved','recognition_provenance']}
    out=repo/'output/verification/media-api.json';out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'passed':True,'cases':len(results),'checks':len(report['checks'])}))


if __name__=='__main__':main()
