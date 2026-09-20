from typing import Literal
from pydantic import Field, model_validator
from .schemas import Input


class TaskTarget(Input):
    item_id:str=Field(min_length=1,max_length=36)
    target_minutes:int|None=Field(default=None,ge=1,le=525600)


class ScheduleInput(Input):
    days:Literal[7,14,28]=7
    lead_minutes:int=Field(default=5,ge=0,le=60)
    chunk_minutes:int=Field(default=45,ge=15,le=120)
    allow_partial:bool=False
    tasks:list[TaskTarget]=Field(min_length=1,max_length=100)

    @model_validator(mode='after')
    def unique(self):
        if len({t.item_id for t in self.tasks})!=len(self.tasks):raise ValueError('不能重复选择任务')
        return self


class ProposalAction(Input):
    expected_version:int=Field(ge=1)
    expected_revision:int=Field(ge=0)
    confirm_partial:bool=False
    unarranged_minutes:int=Field(default=0,ge=0)


class BlockLock(Input):
    expected_version:int=Field(ge=1)
    locked:bool


class BlockCancel(Input):
    expected_version:int=Field(ge=1)
    confirm_locked:bool=False
