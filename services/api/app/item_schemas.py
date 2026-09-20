from datetime import date as CalendarDate, datetime, timezone
from typing import Literal

from pydantic import Field, field_validator, model_validator

from .schemas import Input


class ItemTime(Input):
    precision: Literal['exact', 'date', 'week', 'range', 'unknown'] = 'unknown'
    at: datetime | None = None
    date: CalendarDate | None = None
    week: int | None = Field(default=None, ge=1, le=30)
    end_date: CalendarDate | None = None
    day_end_confirmed: bool = False

    @field_validator('at')
    @classmethod
    def aware(cls, value):
        if value is not None:
            if value.tzinfo is None:
                raise ValueError('具体时间必须包含时区')
            return value.astimezone(timezone.utc)
        return value

    @model_validator(mode='after')
    def valid_precision(self):
        required = {'exact': 'at', 'date': 'date', 'week': 'week', 'range': 'date'}
        if self.precision in required and getattr(self, required[self.precision]) is None:
            raise ValueError('请补充与精度对应的日期或时间')
        if self.at is not None and self.precision != 'exact':
            raise ValueError('部分日期不能携带虚构的具体时刻')
        if self.week is not None and self.precision != 'week':
            raise ValueError('周次与时间精度不一致')
        if self.date is not None and self.precision not in ('date', 'range'):
            raise ValueError('日期与时间精度不一致')
        if self.precision == 'range' and (self.end_date is None or self.end_date < self.date):
            raise ValueError('请核对日期范围')
        if self.end_date is not None and self.precision != 'range':
            raise ValueError('只有日期范围允许结束日期')
        if self.day_end_confirmed and self.precision != 'date':
            raise ValueError('日末口径仅用于只有日期的截止')
        return self


class ReminderInput(Input):
    mode: Literal['relative', 'absolute']
    lead_minutes: int | None = Field(default=None, ge=0, le=525600)
    trigger_at: datetime | None = None
    purpose: Literal['item', 'start_review', 'check_notice'] = 'item'
    enabled: bool = True

    @field_validator('trigger_at')
    @classmethod
    def aware(cls, value):
        return ItemTime.aware(value)

    @model_validator(mode='after')
    def mode_fields(self):
        if self.mode == 'relative' and (self.lead_minutes is None or self.trigger_at is not None):
            raise ValueError('相对提醒需要提前分钟数')
        if self.mode == 'absolute' and (self.trigger_at is None or self.lead_minutes is not None):
            raise ValueError('指定时刻提醒需要具体时间')
        if self.purpose == 'check_notice' and self.mode != 'absolute':
            raise ValueError('核实通知提醒需要独立指定日期')
        return self


class ItemFields(Input):
    semester_id: str = Field(min_length=1, max_length=36)
    kind: Literal['assignment', 'task', 'exam']
    title: str = Field(min_length=1, max_length=120)
    course_id: str | None = Field(default=None, max_length=36)
    time: ItemTime = Field(default_factory=ItemTime)
    certainty: Literal['formal', 'tentative', 'unknown'] = 'unknown'
    remaining_minutes: int | None = Field(default=None, ge=1, le=525600)
    splittable: bool = True
    priority: Literal['normal', 'high', 'low'] = 'normal'
    location: str = Field(default='', max_length=120)
    notes: str = Field(default='', max_length=3000)
    source_text: str = Field(default='', max_length=10000)
    candidate_id: str | None = Field(default=None, max_length=36)

    @model_validator(mode='after')
    def exam_fields(self):
        if self.kind == 'exam' and (self.remaining_minutes is not None or self.time.day_end_confirmed):
            raise ValueError('考试开始时间不能使用任务截止口径，复习耗时应单独建任务')
        return self


class ItemCreate(ItemFields):
    reminders: list[ReminderInput] = Field(default_factory=list, max_length=20)


class ItemEdit(ItemFields):
    expected_version: int = Field(ge=1)
    change_reason: str = Field(min_length=1, max_length=500)


class LifecycleInput(Input):
    expected_version: int = Field(ge=1)
    lifecycle: Literal['active', 'completed', 'cancelled']


class ReminderCreate(ReminderInput):
    expected_item_version: int = Field(ge=1)


class ReminderEdit(ReminderCreate):
    expected_version: int = Field(ge=1)
