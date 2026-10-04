from datetime import date,datetime
from typing import Literal
from pydantic import Field,field_validator,ValidationError
from fastapi import APIRouter,Depends,Request
from sqlalchemy.orm import Session
from .schemas import Input
from .capture import CaptureInput
from .academics import owned_semester
from .models import User
from .database import get_db
from .auth import current_user,error
from .occurrences import effective_courses,expand
from .item_schemas import ItemTime
from .reminder_rules import instant,SHANGHAI
from .text_model import deepseek_text
from .model_context import model_reference

router=APIRouter()
PROMPT='''你是个人课表变更提取器。可以解析学校通知，也可以解析用户明确给出的个人记录更正。source是待解析原文，只提取变更建议，不直接保存。
questions直接面向普通学生，使用简短自然的中文，说明需要补什么信息；不要出现模型供应商品牌、字段名、接口、口径等技术术语。只输出JSON：
{"kind":"move|cancel|suspend|add|block|clarify","title":"课程或活动标题",
"original_date":null,"start_at":null,"end_at":null,"location":"",
"evidence":{},"questions":[]}
move是调课；cancel是单次停课；suspend是放假导致多次停课；add是补课；block是活动固定占用。
考试改期请返回clarify并提示进入已有考试详情修改，不能当作新增活动而重复占用时间。
original_date表示原课次日期YYYY-MM-DD，start_at/end_at表示新起止ISO时刻（+08:00）。
没有明确日期/时刻不补造，保持null并提问。不可从“晚上”猜20点，不从课名猜时长。
context.courses给出可参考的真实课程名，但不允许输出对象ID或修改指令。
用户明确说停课、改期或更正自己的安排时可生成建议，不要求学校通知证明。询问假设或确实缺少所需日期时再clarify；所有建议待用户确认。
evidence的值必须是原文逐字片段。模糊课名、相对日期、多个变更请在questions说明核对或拆开处理。
不输出其他字段。'''


class Suggestion(Input):
    kind:Literal['move','cancel','suspend','add','block','clarify']
    title:str=Field(default='',max_length=160)
    original_date:date|None=None
    start_at:datetime|None=None
    end_at:datetime|None=None
    location:str=Field(default='',max_length=200)
    evidence:dict[str,str]=Field(default_factory=dict,max_length=20)
    questions:list[str]=Field(default_factory=list,max_length=12)
    @field_validator('start_at','end_at')
    @classmethod
    def aware(cls,v):return ItemTime.aware(v) if v else v


@router.post('/changes/parse')
def parse(body:CaptureInput,request:Request,user:User=Depends(current_user),db:Session=Depends(get_db)):
    s=owned_semester(db,user,body.semester_id)
    events=expand({'first_monday':s.first_monday,'periods':s.periods},effective_courses(db,user,s))
    courses=[{'title':t} for t in sorted({e['title'] for e in events})]
    # The same per-user admission guard as text capture, without logging source content.
    from .capture import admission
    admission(request,user)
    model=getattr(request.app.state,'change_model',None)
    reference=model_reference(body.reference_at)['reference_at']
    raw,metadata=model(body.text,reference,courses) if model else deepseek_text(
        body.text,reference,courses,system_prompt=PROMPT,prompt_version='reality-change-v2')
    try:
        suggestion=Suggestion.model_validate(raw)
        if any(v not in body.text for v in suggestion.evidence.values()):raise ValueError('证据不在原文')
        if suggestion.start_at and suggestion.end_at and suggestion.end_at<=suggestion.start_at:raise ValueError('结束早于开始')
    except (ValidationError,ValueError,TypeError):error(502,'INVALID_MODEL_OUTPUT','AI暂时没能整理好这条通知，请检查原文或手动填写')
    matches=[e['id'] for e in events if e['title']==suggestion.title and suggestion.original_date
        and instant(e['start_at']).astimezone(SHANGHAI).date()==suggestion.original_date]
    return {'suggestion':suggestion.model_dump(mode='json'),'target_candidates':matches,'metadata':metadata,'review_state':'pending'}
