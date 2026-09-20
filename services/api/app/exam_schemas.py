from datetime import datetime
from typing import Literal
from pydantic import Field,field_validator,model_validator
from .schemas import Input
from .item_schemas import ItemTime


class ReviewInput(Input):
    expected_exam_version:int=Field(ge=1)
    task_id:str|None=Field(default=None,max_length=36)
    expected_task_version:int|None=Field(default=None,ge=1)
    remaining_minutes:int|None=Field(default=None,ge=1,le=525600)
    deadline_mode:Literal['exam','custom','unknown']='unknown'
    deadline_at:datetime|None=None
    start_policy:Literal['now','unconfirmed']='unconfirmed'
    @field_validator('deadline_at')
    @classmethod
    def aware(cls,v):return ItemTime.aware(v)
    @model_validator(mode='after')
    def valid(self):
        if self.task_id:
            if not self.expected_task_version:raise ValueError('缺少任务版本')
            if self.remaining_minutes is not None or self.deadline_mode!='unknown' or self.deadline_at or self.start_policy!='unconfirmed':raise ValueError('关联已有任务不同时覆盖工作量与日期')
        else:
            if self.remaining_minutes is None:raise ValueError('请确认复习工作量')
            if (self.deadline_mode=='custom')!=(self.deadline_at is not None):raise ValueError('请核对自定义截止')
        return self


class ExamChangeInput(Input):
    expected_version:int=Field(ge=1)
    time:ItemTime
    certainty:Literal['formal','tentative','unknown']
    location:str=Field(default='',max_length=120)
    reserve_time:bool=True
    reason:str=Field(min_length=1,max_length=500)
    align_review_deadlines:bool=False
    title:str|None=Field(default=None,min_length=1,max_length=120)
    course_id:str|None=Field(default=None,max_length=36)
    notes:str|None=Field(default=None,max_length=3000)


class ExamChangeApply(ExamChangeInput):
    expected_revision:int=Field(ge=0)
    preview_token:str=Field(min_length=64,max_length=64)
    confirm_fixed_conflicts:bool=False
