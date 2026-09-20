from datetime import datetime
from pydantic import Field, field_validator, model_validator

from .schemas import Input
from .item_schemas import ItemTime
from .capacity import minute, merge


class LearningWindow(Input):
    weekday: int = Field(ge=1,le=7)
    start: str = Field(pattern=r'^\d{2}:\d{2}$')
    end: str = Field(pattern=r'^\d{2}:\d{2}$')

    @model_validator(mode='after')
    def ordered(self):
        for value in (self.start,self.end):
            h,m=map(int,value.split(':'))
            if m>59 or h>24 or (h==24 and m!=0):
                raise ValueError('时刻格式不正确')
        if not 0 <= minute(self.start) < minute(self.end) <= 1440:
            raise ValueError('同日时段结束须晚于开始；跨天请分两天设置')
        return self


class Exclusion(Input):
    start_at: datetime
    end_at: datetime
    label: str = Field(default='',max_length=120)

    @field_validator('start_at','end_at')
    @classmethod
    def aware(cls,value):
        return ItemTime.aware(value)

    @model_validator(mode='after')
    def ordered(self):
        if self.end_at <= self.start_at:
            raise ValueError('禁排结束必须晚于开始')
        return self


class AvailabilityInput(Input):
    expected_version: int = Field(ge=0)
    weekly: list[LearningWindow] = Field(default_factory=list,max_length=70)
    exclusions: list[Exclusion] = Field(default_factory=list,max_length=200)

    def normalized(self):
        weekly=[]
        def hhmm(n):
            return f'{int(n)//60:02}:{int(n)%60:02}'
        for day in range(1,8):
            for a,b in merge([(minute(r.start),minute(r.end)) for r in self.weekly if r.weekday==day]):
                weekly.append({'weekday':day,'start':hhmm(a),'end':hhmm(b)})
        return {'weekly':weekly,'exclusions':[e.model_dump(mode='json') for e in self.exclusions]}


class AvailabilityApply(AvailabilityInput):
    expected_revision: int = Field(ge=0)
    confirm_plan_conflicts: bool = False


class ProgressInput(Input):
    expected_version: int = Field(ge=1)
    remaining_minutes: int = Field(ge=0,le=525600)
    actual_minutes: int | None = Field(default=None,ge=0,le=525600)
    note: str = Field(default='',max_length=500)


class ProgressApply(ProgressInput):
    expected_revision: int = Field(ge=0)
    confirm_complete: bool = False
    cancel_plan_ids:list[str]=Field(default_factory=list,max_length=300)
    confirm_locked_cancellation:bool=False
