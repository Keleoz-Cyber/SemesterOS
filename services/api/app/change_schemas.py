from datetime import datetime
from typing import Literal
from pydantic import Field,field_validator,model_validator
from .schemas import Input
from .item_schemas import ItemTime


class ChangeInput(Input):
    kind:Literal['move','cancel','suspend','add','block']
    targets:list[str]=Field(default_factory=list,max_length=100)
    title:str=Field(min_length=1,max_length=160)
    source_text:str=Field(min_length=1,max_length=10000)
    start_at:datetime|None=None
    end_at:datetime|None=None
    location:str=Field(default='',max_length=200)

    @field_validator('start_at','end_at')
    @classmethod
    def aware(cls,v):return ItemTime.aware(v) if v else v

    @model_validator(mode='after')
    def validate(self):
        if len(set(self.targets))!=len(self.targets):raise ValueError('课次不能重复')
        if self.kind in ('move','cancel') and len(self.targets)!=1:raise ValueError('请选择单次课次')
        if self.kind=='suspend' and not self.targets:raise ValueError('请明确选择放假停课范围')
        if self.kind in ('add','block') and self.targets:raise ValueError('新增事项不覆盖旧课次')
        if self.kind in ('move','add','block'):
            if not self.start_at or not self.end_at or self.end_at<=self.start_at:raise ValueError('需明确起止时刻')
        elif self.start_at or self.end_at:raise ValueError('停课不填写新时刻')
        return self


class ChangeApply(Input):
    expected_revision:int=Field(ge=0)
    confirm_fixed_conflicts:bool=False
