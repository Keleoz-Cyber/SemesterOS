from datetime import datetime
from hashlib import sha256
from typing import Literal
from fastapi import APIRouter,Depends,Header,Request,Query
from fastapi.responses import FileResponse,Response
from pydantic import Field,field_validator
from sqlalchemy import select,func
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool
from .database import get_db
from .models import MediaSource,User,new_id
from .auth import current_user,error
from .academics import owned_semester
from .schemas import Input
from .item_schemas import ItemTime
from .reminder_rules import utcnow
from .media_files import sanitize,path_for

router=APIRouter()


class SourceVersion(Input):expected_version:int=Field(ge=1)


class SourceEdit(SourceVersion):
    text:str=Field(max_length=10000)
    reference_at:datetime
    @field_validator('reference_at')
    @classmethod
    def aware(cls,v):return ItemTime.aware(v)


def owned_source(db,user,id,lock=False):
    q=select(MediaSource).where(MediaSource.id==id,MediaSource.user_id==user.id)
    row=db.scalar(q.with_for_update().execution_options(populate_existing=True) if lock else q)
    if row is None:error(404,'NOT_FOUND','找不到这份来源')
    return row


def value(row):
    return {k:getattr(row,k) for k in ('id','semester_id','kind','mime','size','file_deleted','version','status','text','original_text','reference_at','error_code','created_at')}|{
        'recognition':row.metadata_json,'image_count':row.metadata_json.get('image_count',1 if row.kind=='image' else 0),
        'is_image_batch':row.mime=='application/zip'}


def version(row,expected):
    if row.version!=expected:error(409,'SOURCE_STALE','来源已更新，请刷新后核对')


@router.post('/semesters/{sid}/sources',status_code=201)
async def upload(sid:str,request:Request,kind:Literal['image','audio'],user:User=Depends(current_user),db:Session=Depends(get_db),idempotency_key:str=Header(min_length=1,max_length=120)):
    owned_semester(db,user,sid)
    limit=(10 if kind=='image' else 20)*1024*1024
    data=bytearray()
    async for part in request.stream():
        if len(data)+len(part)>limit:error(413,'MEDIA_TOO_LARGE','来源文件超出大小限制')
        data.extend(part)
    digest=sha256(data).hexdigest()
    owned_semester(db,user,sid,lock=True)
    old=db.scalar(select(MediaSource).where(MediaSource.user_id==user.id,MediaSource.semester_id==sid,MediaSource.upload_key==idempotency_key))
    if old:
        if old.input_hash!=digest or old.kind!=kind:error(409,'UPLOAD_KEY_CONFLICT','上传的文件已变化，请重新选择文件后上传')
        return value(old)
    sanitized,mime,ext,metadata=await run_in_threadpool(sanitize,bytes(data),kind)
    count,size=db.execute(select(func.count(),func.coalesce(func.sum(MediaSource.size),0)).where(MediaSource.user_id==user.id,MediaSource.file_deleted==False)).one()
    if count>=500 or size+len(sanitized)>1024**3:error(422,'MEDIA_QUOTA','已保存来源较多，请删除不需要的原文件后再上传')
    id=new_id();key=id+ext;folder=request.app.state.media_root;folder.mkdir(parents=True,exist_ok=True)
    path=path_for(folder,key)
    now=utcnow().isoformat()
    row=MediaSource(id=id,user_id=user.id,semester_id=sid,upload_key=idempotency_key,input_hash=digest,kind=kind,mime=mime,size=len(sanitized),storage_key=key,
        reference_at=now,created_at=now,metadata_json=metadata)
    try:
        path.write_bytes(sanitized)
        db.add(row);db.flush();result=value(row);db.commit()
    except Exception:
        path.unlink(missing_ok=True);raise
    return result


@router.get('/semesters/{sid}/sources')
def sources(sid:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    owned_semester(db,user,sid)
    return [value(r) for r in db.scalars(select(MediaSource).where(MediaSource.user_id==user.id,MediaSource.semester_id==sid).order_by(MediaSource.created_at.desc()).limit(50))]


@router.get('/sources/{id}')
def get_source(id:str,user:User=Depends(current_user),db:Session=Depends(get_db)):return value(owned_source(db,user,id))


@router.get('/sources/{id}/content')
def content(id:str,request:Request,user:User=Depends(current_user),db:Session=Depends(get_db)):
    row=owned_source(db,user,id);path=path_for(request.app.state.media_root,row.storage_key)
    if row.file_deleted or not path.exists():error(410,'SOURCE_DELETED','原文件已删除，文本和历史仍保留')
    return FileResponse(path,media_type=row.mime,headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'})


@router.get('/sources/{id}/images/{index}')
def source_image(id:str,index:int,request:Request,expected_version:int|None=Query(default=None,ge=1),
                 user:User=Depends(current_user),db:Session=Depends(get_db)):
    row=owned_source(db,user,id)
    if expected_version is not None:version(row,expected_version)
    if row.kind!='image' or index<0 or index>=row.metadata_json.get('image_count',1):
        error(404,'NOT_FOUND','找不到这张来源图片')
    path=path_for(request.app.state.media_root,row.storage_key)
    if row.file_deleted or not path.exists():error(410,'SOURCE_DELETED','原图片已删除，文本和历史仍保留')
    headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','X-Source-Version':str(row.version)}
    if row.mime!='application/zip':return FileResponse(path,media_type=row.mime,headers=headers)
    from zipfile import ZipFile,BadZipFile
    try:
        with ZipFile(path) as archive:image=archive.read(f'image-{index+1}.png')
    except FileNotFoundError:error(410,'SOURCE_DELETED','原图片已删除，文本和历史仍保留')
    except (KeyError,BadZipFile):error(404,'NOT_FOUND','这张来源图片暂时无法读取')
    return Response(image,media_type='image/png',headers=headers)


@router.patch('/sources/{id}')
def edit(id:str,body:SourceEdit,user:User=Depends(current_user),db:Session=Depends(get_db)):
    row=owned_source(db,user,id,True);version(row,body.expected_version)
    if row.status in ('queued','running'):error(409,'SOURCE_BUSY','请先取消识别，再修改文字')
    row.text=body.text;row.reference_at=body.reference_at.isoformat();row.version+=1
    db.commit();return value(row)


@router.post('/sources/{id}/recognize',status_code=202)
def recognize(id:str,body:SourceVersion,user:User=Depends(current_user),db:Session=Depends(get_db)):
    row=owned_source(db,user,id,True);version(row,body.expected_version)
    if row.file_deleted:error(410,'SOURCE_DELETED','原文件已删除，不能重新识别')
    if row.status not in ('queued','running'):
        row.status='queued';row.version+=1;row.lease_token=None;row.lease_until=0;row.attempts=0;row.error_code=None
    db.commit();return value(row)


@router.post('/sources/{id}/cancel')
def cancel(id:str,body:SourceVersion,user:User=Depends(current_user),db:Session=Depends(get_db)):
    row=owned_source(db,user,id,True);version(row,body.expected_version)
    row.status='cancelled';row.version+=1;row.lease_token=None;row.lease_until=0
    db.commit();return value(row)


@router.delete('/sources/{id}/content')
def delete_file(id:str,body:SourceVersion,request:Request,user:User=Depends(current_user),db:Session=Depends(get_db)):
    row=owned_source(db,user,id,True);version(row,body.expected_version)
    try:path_for(request.app.state.media_root,row.storage_key).unlink(missing_ok=True)
    except OSError:error(409,'SOURCE_IN_USE','原文件正在使用，请稍后重试删除')
    row.file_deleted=True;row.version+=1;row.lease_token=None;row.lease_until=0
    if row.status in ('running','queued'):row.status='cancelled'
    db.commit();return value(row)
