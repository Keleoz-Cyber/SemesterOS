"""One durable recognition source and conversation turn for a notice's images."""
from hashlib import sha256
from io import BytesIO
from zipfile import ZipFile,ZIP_STORED
from fastapi import APIRouter,Depends,Request
from sqlalchemy import select,func
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool
from .auth import current_user,error
from .database import get_db
from .academics import owned_semester,fingerprint
from .models import User,MediaSource,AgentThread,AgentRun,new_id
from .media import owned_source,value,version,SourceVersion
from .media_files import sanitize,path_for
from .reminder_rules import utcnow
from .agent_api import BrowsingContext

router=APIRouter(prefix='/agent')


def result(db,user,source):
    from .agent_api import owned_thread,public_run
    metadata=source.metadata_json
    if not metadata.get('agent_run_id'):error(404,'NOT_FOUND','找不到这份通知请求')
    thread=owned_thread(db,user,metadata['thread_id'])
    run=db.get(AgentRun,metadata['agent_run_id'])
    return {'id':source.id,'source':value(source),
        'thread':{'id':thread.id,'semester_id':thread.semester_id,'title':thread.title},
        'run':public_run(run) if run and run.status!='recognizing' else None,
        'status':source.status,'stage':metadata.get('stage','正在识别通知'),
        'progress':metadata.get('progress',[]),'error':source.error_code}


@router.post('/media-runs',status_code=202)
async def submit_media(request:Request,user:User=Depends(current_user),db:Session=Depends(get_db)):
    from .capture import admission
    from .agent_api import owned_thread
    try:
        if int(request.headers.get('content-length','0'))>65*1024*1024:
            error(413,'MEDIA_TOO_LARGE','这一组图片超过60MB，请分批选择')
        form=await request.form(max_files=1000,max_fields=8)
    except (ValueError,TypeError):error(422,'INVALID_MEDIA','请重新选择图片或录音')
    sid=str(form.get('semester_id') or '')
    key=str(form.get('client_request_id') or '')
    instruction=str(form.get('instruction') or '').strip()
    browsing_context=None
    if form.get('browsing_context'):
        from pydantic import ValidationError
        try:browsing_context=BrowsingContext.model_validate_json(str(form['browsing_context'])).model_dump(mode='json')
        except (ValidationError,ValueError):error(422,'INVALID_INPUT','请核对当前浏览日期')
    kind=str(form.get('kind') or 'image')
    tid=str(form.get('thread_id') or '')
    if not sid or not 1<=len(key)<=100 or len(instruction)>10000 or kind not in ('image','audio'):
        error(422,'INVALID_INPUT','请核对学期和发送内容')
    uploads=form.getlist('files')+form.getlist('file')
    if not uploads or (kind=='audio' and len(uploads)!=1):
        error(422,'INVALID_MEDIA','请选择通知图片；录音请单独发送')
    owned_semester(db,user,sid)
    parts=[];hashes=[];total=0;clean_total=0
    for upload in uploads:
        if not hasattr(upload,'read'):error(422,'INVALID_MEDIA','请重新选择文件')
        data=await upload.read((10 if kind=='image' else 20)*1024*1024+1)
        await upload.close()
        digest=sha256(data).hexdigest();hashes.append(digest);total+=len(data)
        if total>60*1024*1024:error(413,'MEDIA_TOO_LARGE','这一组图片超过60MB，请分批选择')
        clean,mime,ext,metadata=await run_in_threadpool(sanitize,data,kind)
        clean_total+=len(clean)
        if clean_total>120*1024*1024:error(413,'MEDIA_TOO_LARGE','图片解码后超过存储限制，请压缩后整体重新发送')
        parts.append((digest,clean,mime,ext,metadata))
    signature_data={'images':hashes,'kind':kind,'instruction':instruction,'thread_id':tid}
    if browsing_context is not None:signature_data['browsing_context']=browsing_context
    signature=fingerprint(signature_data)
    thread=owned_thread(db,user,tid,True) if tid else None
    if thread and thread.semester_id!=sid:error(404,'NOT_FOUND','对话不属于当前学期')
    s=owned_semester(db,user,sid,lock=True)
    old=db.scalar(select(MediaSource).where(MediaSource.user_id==user.id,MediaSource.semester_id==sid,
        MediaSource.upload_key=='agent:'+key))
    if old:
        if old.input_hash!=signature:error(409,'IDEMPOTENCY_CONFLICT','这次发送内容已变化，请重新发送')
        return result(db,user,old)
    admission(request,user)
    if tid:
        if db.scalar(select(AgentRun.id).where(AgentRun.thread_id==tid,AgentRun.status.in_(['queued','running','recognizing']))):
            error(409,'RUN_BUSY','请等待当前处理结束，或先停止')
    else:
        thread=AgentThread(user_id=user.id,semester_id=sid,title=instruction[:80] or '图片通知',
            created_at=utcnow().isoformat(),updated_at=utcnow().isoformat())
        db.add(thread);db.flush()
    if len(list(db.scalars(select(AgentRun.id).where(AgentRun.user_id==user.id,
        AgentRun.status.in_(['queued','running','recognizing'])).limit(3))))>=3:
        error(429,'RUN_LIMIT','已有几条请求正在处理，请稍后再发')
    now=utcnow().isoformat()
    run=AgentRun(user_id=user.id,thread_id=thread.id,request_id='media:'+key,
        text=instruction or '请整理这份通知，生成需要我确认的安排。',status='recognizing',created_at=now,
        state={'stage':'正在识别通知','progress':[],'sequence':0,'browsing_context':browsing_context})
    db.add(run);db.flush()
    metadata={'image_count':len(parts),'same_notice':True,'thread_id':thread.id,'agent_run_id':run.id,
        'stage':'等待识别','progress':[]}
    if kind=='image' and len(parts)>1:
        buffer=BytesIO()
        with ZipFile(buffer,'w',compression=ZIP_STORED) as archive:
            for index,part in enumerate(parts):archive.writestr(f'image-{index+1}.png',part[1])
        stored=buffer.getvalue();mime='application/zip';ext='.zip'
        metadata['images']=[{'name':f'image-{i+1}.png',**p[4]} for i,p in enumerate(parts)]
    else:
        _,stored,mime,ext,image_meta=parts[0];metadata.update(image_meta)
    count,size=db.execute(select(func.count(),func.coalesce(func.sum(MediaSource.size),0)).where(
        MediaSource.user_id==user.id,MediaSource.file_deleted==False)).one()
    if count>=500 or size+len(stored)>1024**3:error(422,'MEDIA_QUOTA','来源文件较多，请先删除不需要的原文件')
    folder=request.app.state.media_root;folder.mkdir(parents=True,exist_ok=True)
    source=MediaSource(id=new_id(),user_id=user.id,semester_id=sid,upload_key='agent:'+key,input_hash=signature,
        kind=kind,mime=mime,size=len(stored),storage_key='',reference_at=now,created_at=now,
        status='queued',metadata_json=metadata)
    source.storage_key=source.id+ext;path=path_for(folder,source.storage_key)
    run.state={**run.state,'media_source_id':source.id,
        'source':{'id':source.id,'version':1,'kind':kind,'text':'','original_text':'','reference_at':now}}
    try:
        path.write_bytes(stored);db.add(source);db.flush()
        thread.updated_at=now
        from .agent_api import invalidate_preview
        for pending in db.scalars(select(AgentRun).where(AgentRun.thread_id==thread.id,AgentRun.status=='needs_confirmation')):
            invalidate_preview(db,pending);pending.status='superseded'
        response=result(db,user,source);db.commit();return response
    except Exception:
        path.unlink(missing_ok=True);raise
    finally:
        for upload in uploads:await upload.close()


@router.get('/media-runs/{id}')
def get_media_run(id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    return result(db,user,owned_source(db,user,id))


@router.post('/media-runs/{id}/cancel')
def cancel_media_run(id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    from .agent_api import owned_run
    source=owned_source(db,user,id)
    metadata=source.metadata_json
    if not metadata.get('agent_run_id'):error(404,'NOT_FOUND','找不到这份通知请求')
    run=owned_run(db,user,metadata['agent_run_id'],True)
    source=owned_source(db,user,id,True)
    if source.status in ('queued','running'):
        source.status='cancelled';source.version+=1;source.lease_token=None
    if run.status in ('recognizing','queued','running','needs_confirmation'):
        from .agent_api import invalidate_preview
        invalidate_preview(db,run);run.status='cancelled';run.lease_token=None
        run.state={**run.state,'stage':'已停止','answer_streaming':False}
    db.commit();return result(db,user,source)


class MediaRetryInput(SourceVersion):
    browsing_context: BrowsingContext | None = None


@router.post('/media-runs/{id}/retry',status_code=202)
def retry_media_run(id:str,body:MediaRetryInput,request:Request,user:User=Depends(current_user),db:Session=Depends(get_db)):
    from .agent_api import owned_run,owned_thread
    source=owned_source(db,user,id)
    metadata=source.metadata_json
    if not metadata.get('agent_run_id'):error(404,'NOT_FOUND','找不到这份通知请求')
    thread=owned_thread(db,user,metadata['thread_id'],True)
    run=owned_run(db,user,metadata['agent_run_id'],True)
    source=owned_source(db,user,id,True);version(source,body.expected_version)
    if source.file_deleted or not path_for(request.app.state.media_root,source.storage_key).exists():
        error(410,'SOURCE_DELETED','原文件已删除，请重新选择图片或输入通知文字')
    if source.status in ('queued','running'):return result(db,user,source)
    if source.status not in ('failed','cancelled') or run.status not in ('failed','cancelled','recognizing'):
        error(409,'RETRY_NOT_AVAILABLE','这份通知已完成识别，请查看当前回复或重新提问')
    if db.scalar(select(AgentRun.id).where(AgentRun.thread_id==thread.id,AgentRun.id!=run.id,
        AgentRun.status.in_(['queued','running','recognizing']))):
        error(409,'RUN_BUSY','请等当前请求结束后再重试通知')
    from .capture import admission
    admission(request,user)
    now=utcnow().isoformat()
    browsing_context=(body.browsing_context.model_dump(mode='json') if body.browsing_context is not None else None) if 'browsing_context' in body.model_fields_set else run.state.get('browsing_context')
    source.status='queued';source.version+=1;source.lease_token=None;source.lease_until=0;source.attempts=0;source.error_code=None
    source.metadata_json={**metadata,'stage':'等待重新识别','progress':[
        {'stage':'recognition','message':'等待重新识别','at':now}]}
    run.status='recognizing';run.lease_token=None;run.lease_until=0;run.attempts=0
    run.state={'stage':'等待重新识别','media_source_id':source.id,'progress':[],
        'browsing_context':browsing_context,
        'source':{'id':source.id,'version':source.version,'kind':source.kind,'text':source.text,
            'original_text':source.original_text,'reference_at':source.reference_at},
        'sequence':run.state.get('sequence',0)+1}
    thread.updated_at=now
    db.commit();return result(db,user,source)


def publish_recognized_turn(db,source):
    """Worker publishes recognition and an already-authorized turn atomically."""
    metadata=source.metadata_json
    if not metadata.get('agent_run_id'):return
    run=db.scalar(select(AgentRun).where(AgentRun.id==metadata['agent_run_id']).with_for_update())
    if not run or run.status!='recognizing':return
    if source.status!='recognized':
        run.status='failed';run.state={**run.state,'error':'通知识别没有完成，请重试或输入文字','stage':'识别未完成'}
        return
    from .agent_runtime import initial_state
    import json
    thread=db.get(AgentThread,run.thread_id);user=db.get(User,run.user_id)
    ref={'id':source.id,'version':source.version,'kind':source.kind,'text':source.text,
        'reference_at':source.reference_at,'original_text':source.original_text}
    state=initial_state(db,user,thread,run.text,utcnow().isoformat(),exclude_run_id=run.id,input_kind='notice')
    message={'role':'user','content':json.dumps({'request':run.text,'notice_data':ref},ensure_ascii=False)}
    state['messages'][-1]=message;state['turn_messages'][-1]=message
    from .agent_api import attach_browsing_context
    attach_browsing_context(state,run.state.get('browsing_context'),run.text)
    state.update(run_id=run.id,source=ref,draft_source=source.text,
        media_source_id=source.id,
        progress=metadata.get('progress',[]),stage='识别完成，正在理解通知')
    run.state=state;run.status='queued'
