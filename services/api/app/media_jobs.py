import time
from sqlalchemy import select,or_,and_
from sqlalchemy.orm import Session
from .models import MediaSource,AgentRun,new_id


def claim(engine):
    now=int(time.time())
    with Session(engine,expire_on_commit=False) as db:
        row=db.scalar(select(MediaSource).where(MediaSource.file_deleted==False,or_(MediaSource.status=='queued',
            and_(MediaSource.status=='running',MediaSource.lease_until<now))).order_by(MediaSource.created_at).with_for_update(skip_locked=True).limit(1))
        if row is None:return None
        if row.attempts>=3:
            source_id=row.id;rid=row.metadata_json.get('agent_run_id')
            # Release the queue's source lock before taking the same run ->
            # source order as cancellation and publish. Recheck after waiting.
            db.rollback()
            if rid:db.scalar(select(AgentRun).where(AgentRun.id==rid).with_for_update())
            row=db.scalar(select(MediaSource).where(MediaSource.id==source_id)
                .with_for_update().execution_options(populate_existing=True))
            now=int(time.time())
            if (row is None or row.file_deleted or row.attempts<3 or
                    not (row.status=='queued' or row.status=='running' and row.lease_until<now)):
                return None
            row.status='failed';row.error_code='WORKER_INTERRUPTED';row.version+=1
            row.lease_token=None;row.lease_until=0
            from .agent_media import publish_recognized_turn
            publish_recognized_turn(db,row)
            db.commit();return None
        row.status='running';row.lease_token=new_id();row.lease_until=now+300;row.attempts+=1
        result={'id':row.id,'kind':row.kind,'storage_key':row.storage_key,'token':row.lease_token,'version':row.version,
                'metadata':row.metadata_json}
        db.commit();return result


def publish(engine,job,result=None,error=None):
    with Session(engine) as db:
        # Cancellation/revision own the conversation run first. Use that same
        # order before locking its media source, avoiding a cross-queue deadlock.
        source=db.get(MediaSource,job['id'])
        rid=(source.metadata_json if source else {}).get('agent_run_id')
        if rid:db.scalar(select(AgentRun).where(AgentRun.id==rid).with_for_update())
        row=db.scalar(select(MediaSource).where(MediaSource.id==job['id']).with_for_update().execution_options(populate_existing=True))
        if not row or row.file_deleted or row.status!='running' or row.lease_token!=job['token'] or row.version!=job['version'] or row.lease_until<int(time.time()):return False
        row.status='failed' if error else 'recognized';row.error_code=error;row.lease_token=None;row.lease_until=0;row.version+=1
        if result is not None:
            text=result['text'].strip()
            if not text or len(text)>10000:row.status='failed';row.error_code='NO_USABLE_TEXT' if not text else 'TEXT_TOO_LONG'
            else:row.text=text;row.original_text=text;row.metadata_json={**row.metadata_json,**result.get('metadata',{})}
        from .agent_media import publish_recognized_turn
        publish_recognized_turn(db,row)
        db.commit();return True


def progress(engine,job,message):
    from .reminder_rules import utcnow
    with Session(engine) as db:
        row=db.scalar(select(MediaSource).where(MediaSource.id==job['id']).with_for_update())
        if not row or row.status!='running' or row.lease_token!=job['token'] or row.version!=job['version']:return False
        metadata=row.metadata_json
        row.metadata_json={**metadata,'stage':message,'progress':(metadata.get('progress',[])+[
            {'stage':'recognition','message':message,'at':utcnow().isoformat()}])[-12:]}
        row.lease_until=int(time.time())+300
        db.commit();return True
