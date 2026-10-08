from datetime import date as CalendarDate, datetime, timezone
from typing import Literal, Annotated, ClassVar

from pydantic import Field, field_validator, model_validator

from .schemas import Input


class CourseAnchor(Input):
    course_id: str | None = Field(default=None, max_length=36)
    title: str = Field(default='', max_length=120)
    week: int | None = Field(default=None, ge=1, le=30)
    weekday: int | None = Field(default=None, ge=1, le=7)
    sections: list[Annotated[int, Field(ge=1, le=30)]] = Field(default_factory=list, max_length=30)


class NoticeDetails(Input):
    recipient: str = Field(default='', max_length=200,
        description='材料或办理结果实际提交给谁；通知面向的人群请用applicability，没有提交接收方时留空。')
    materials: list[Annotated[str, Field(min_length=1, max_length=300)]] = Field(default_factory=list, max_length=30)
    submission_channel: str = Field(default='', max_length=300)
    participation: str = Field(default='', max_length=500)
    participation_status: Literal['unspecified', 'confirmed', 'optional', 'conditional', 'other'] = 'unspecified'
    conditions: list[Annotated[str, Field(min_length=1, max_length=300)]] = Field(default_factory=list, max_length=30)
    early_arrival_minutes: int | None = Field(default=None, ge=0, le=1440)
    applicability: str = Field(default='', max_length=500)
    responsibility: str = Field(default='', max_length=500)


class ItemTime(Input):
    precision: Literal['exact', 'date', 'week', 'range', 'unknown'] = Field(default='unknown',
        description='exact表示已知含时区的时刻；即使是办理窗口，只要小时起止明确也用exact与at/end_at。range仅用于日期范围，不承载小时。没有钟点不补造。')
    at: datetime | None = None
    end_at: datetime | None = None
    date: CalendarDate | None = None
    week: int | None = Field(default=None, ge=1, le=30)
    end_date: CalendarDate | None = None
    day_end_confirmed: bool = False
    expression: str = Field(default='', max_length=500)
    meaning: Literal['unspecified', 'deadline', 'start', 'window', 'candidate', 'course_anchor'] = Field(default='unspecified',
        description='时间用途；未说明用途时省略或unspecified。unknown仅属于precision，不能填写为meaning。')
    candidate_dates: list[CalendarDate] = Field(default_factory=list, max_length=12)
    course_anchor: CourseAnchor | None = None

    @field_validator('at', 'end_at')
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
        if self.end_at is not None and (self.precision != 'exact' or self.at is None or self.end_at <= self.at):
            raise ValueError('结束时间必须晚于明确的开始时间')
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
        if self.candidate_dates and self.meaning != 'candidate':
            raise ValueError('候选日期需要保留候选口径')
        if self.course_anchor is not None and self.meaning != 'course_anchor':
            raise ValueError('课程节点需要保留课节口径')
        if self.meaning in ('candidate', 'course_anchor') and self.precision != 'unknown':
            raise ValueError('候选日期或课节节点不能同时作为已经确定的时间')
        if self.day_end_confirmed and self.meaning not in ('unspecified', 'deadline'):
            raise ValueError('只有明确截止可以使用日末口径')
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
    _allow_legacy_window_end: ClassVar[bool] = False
    semester_id: str = Field(min_length=1, max_length=36)
    expected_revision: int | None = Field(default=None, ge=0)
    confirm_fixed_conflicts: bool = False
    course_leave_targets: list[str] = Field(default_factory=list, max_length=100)
    kind: Literal['assignment', 'task', 'exam']
    title: str = Field(min_length=1, max_length=120)
    course_id: str | None = Field(default=None, max_length=36)
    time: ItemTime = Field(default_factory=ItemTime)
    certainty: Literal['formal', 'tentative', 'unknown'] = 'unknown'
    remaining_minutes: int | None = Field(default=None, ge=1, le=525600)
    start_policy: Literal['unconfirmed', 'now', 'at'] = 'unconfirmed'
    earliest_start_at: datetime | None = None
    reserve_time: bool = True
    splittable: bool = True
    priority: Literal['normal', 'high', 'low'] = 'normal'
    location: str = Field(default='', max_length=120)
    notes: str = Field(default='', max_length=3000)
    source_text: str = Field(default='', max_length=10000)
    details: NoticeDetails = Field(default_factory=NoticeDetails)
    candidate_id: str | None = Field(default=None, max_length=36)
    source_id:str|None=Field(default=None,max_length=36)
    category_id: Literal['study', 'research', 'affairs', 'life'] | None = None
    tags: list[str] = Field(default_factory=list, max_length=12)

    @field_validator('tags')
    @classmethod
    def normalize_tags(cls, tags):
        # Import lazily: event time schemas already depend on ItemTime.
        from .event_schemas import EventFields
        return EventFields.normalize_tags(tags)

    @field_validator('earliest_start_at')
    @classmethod
    def aware_start(cls, value):
        return ItemTime.aware(value)

    @model_validator(mode='after')
    def exam_fields(self):
        if self.kind == 'exam' and (self.remaining_minutes is not None or self.time.day_end_confirmed):
            raise ValueError('考试开始时间不能使用任务截止口径，复习耗时应单独建任务')
        if (self.kind != 'exam' and self.time.end_at is not None and self.time.meaning != 'window'
                and not (self._allow_legacy_window_end and self.time.meaning == 'unspecified')):
            raise ValueError('任务截止不需要考试结束时刻')
        if self.start_policy == 'at' and self.earliest_start_at is None:
            raise ValueError('请明确任务最早开始时间')
        if self.start_policy != 'at' and self.earliest_start_at is not None:
            raise ValueError('指定最早开始时间时请使用对应口径')
        if self.kind == 'exam' and (self.start_policy != 'unconfirmed' or self.earliest_start_at is not None):
            raise ValueError('考试使用固定开始时间，不使用任务最早开始口径')
        return self


class ItemCreate(ItemFields):
    reminders: list[ReminderInput] = Field(default_factory=list, max_length=20)


class ItemEdit(ItemFields):
    # Old clients can send back a window end without knowing its new meaning.
    # Persistence verifies the merged meaning against the actual stored record.
    _allow_legacy_window_end: ClassVar[bool] = True
    expected_version: int = Field(ge=1)
    change_reason: str = Field(min_length=1, max_length=500)


class ItemConflictPreview(ItemCreate):
    item_id: str | None = Field(default=None, max_length=36)
    expected_version: int | None = Field(default=None, ge=1)
    change_reason: str = Field(default='', max_length=500)


class LifecycleInput(Input):
    expected_version: int = Field(ge=1)
    lifecycle: Literal['active', 'completed', 'cancelled']
    expected_revision:int|None=Field(default=None,ge=0)
    cancel_plan_ids:list[str]=Field(default_factory=list,max_length=300)
    confirm_locked_cancellation:bool=False
    confirm_fixed_conflicts: bool = False
    course_leave_targets: list[str] = Field(default_factory=list, max_length=100)


class ReminderCreate(ReminderInput):
    expected_item_version: int = Field(ge=1)


class ReminderEdit(ReminderCreate):
    expected_version: int = Field(ge=1)
