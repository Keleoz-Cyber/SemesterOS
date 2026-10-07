from datetime import datetime
from typing import Literal
from pydantic import Field,field_validator
from .schemas import Input
from .capture import CaptureInput
from .item_schemas import ItemTime,ReminderInput
from .schedule_schemas import TaskTarget


class TaskPatch(Input):
    title:str|None=Field(default=None,min_length=1,max_length=120)
    remaining_minutes:int|None=Field(default=None,ge=1,le=525600)
    splittable:bool|None=None


class ReminderPatch(Input):
    mode:Literal['relative','absolute']|None=None
    lead_minutes:int|None=Field(default=None,ge=0,le=525600)
    trigger_at:datetime|None=None
    purpose:Literal['item','start_review','check_notice']|None=None
    @field_validator('trigger_at')
    @classmethod
    def aware(cls,v):return ItemTime.aware(v)


class OperationSuggestion(Input):
    intent:Literal['update_task','update_reminder','request_plan','clarify','unsupported']
    target_query:str=Field(default='',max_length=120)
    task_patch:TaskPatch=Field(default_factory=TaskPatch)
    reminder_action:Literal['add','edit','disable']='edit'
    reminder_patch:ReminderPatch=Field(default_factory=ReminderPatch)
    plan_mode:Literal['schedule','replan']='schedule'
    target_minutes:int|None=Field(default=None,ge=1,le=525600)
    window_start_at:datetime|None=None
    window_end_at:datetime|None=None
    needs_window:bool=False
    questions:list[str]=Field(default_factory=list,max_length=12)
    evidence:dict[str,str]=Field(default_factory=dict,max_length=20)
    @field_validator('window_start_at','window_end_at')
    @classmethod
    def aware(cls,v):return ItemTime.aware(v)


class OperationParse(CaptureInput):
    context_item_id:str|None=Field(default=None,max_length=36)


class OperationResolve(Input):
    expected_version:int=Field(ge=1)
    target_item_id:str|None=Field(default=None,max_length=36)
    task_patch:TaskPatch|None=None
    reminder_action:Literal['add','edit','disable']|None=None
    reminder_id:str|None=Field(default=None,max_length=36)
    reminder:ReminderInput|None=None
    expected_item_version:int|None=Field(default=None,ge=1)
    expected_reminder_version:int|None=Field(default=None,ge=1)
    plan_mode:Literal['schedule','replan']|None=None
    tasks:list[TaskTarget]=Field(default_factory=list,max_length=100)
    days:int=Field(default=7,ge=1,le=210)
    chunk_minutes:int=Field(default=45,ge=1,le=1440)
    lead_minutes:int=Field(default=5,ge=0,le=1440)
    window_start_at:datetime|None=None
    window_end_at:datetime|None=None
    use_default_window:bool=False
    confirm_direct_request:bool=False
    @field_validator('tasks')
    @classmethod
    def unique_tasks(cls,v):
        if len({t.item_id for t in v})!=len(v):raise ValueError('任务不能重复选择')
        return v
    @field_validator('window_start_at','window_end_at')
    @classmethod
    def aware(cls,v):return ItemTime.aware(v)


class OperationAction(Input):
    expected_version:int=Field(ge=1)
    cancel_plan_ids:list[str]=Field(default_factory=list,max_length=300)
    confirm_locked_cancellation:bool=False
