import unicodedata
from typing import Literal
from pydantic import Field, field_validator, model_validator
from .schemas import Input
from .item_schemas import ItemTime, NoticeDetails


class EventFields(Input):
    semester_id: str = Field(min_length=1, max_length=36)
    title: str = Field(min_length=1, max_length=120)
    time: ItemTime = Field(default_factory=ItemTime)
    certainty: Literal['formal', 'tentative', 'unknown'] = 'formal'
    reserve_time: bool = True
    location: str = Field(default='', max_length=120)
    notes: str = Field(default='', max_length=3000)
    source_text: str = Field(default='', max_length=10000)
    details: NoticeDetails = Field(default_factory=NoticeDetails)
    category_id: Literal['study', 'research', 'affairs', 'life'] | None = None
    tags: list[str] = Field(default_factory=list, max_length=12)
    reminder_minutes: list[int] = Field(default_factory=list, max_length=12)
    expected_revision: int = Field(ge=0)
    candidate_id: str | None = Field(default=None, max_length=36)

    @field_validator('tags')
    @classmethod
    def normalize_tags(cls, tags):
        result = []; seen = set()
        for raw in tags:
            name = ' '.join(unicodedata.normalize('NFKC', raw).split())
            if not name or len(name) > 24:
                raise ValueError('标签需要1至24个字符')
            if name.casefold() not in seen:
                seen.add(name.casefold()); result.append(name)
        return result

    @field_validator('reminder_minutes')
    @classmethod
    def leads(cls, values):
        if any(v < 0 or v > 525600 for v in values):
            raise ValueError('请核对提醒提前时间')
        return sorted(set(values), reverse=True)

    @model_validator(mode='after')
    def no_deadline_policy(self):
        if self.time.day_end_confirmed:
            raise ValueError('活动时间不是任务截止时间')
        if ('reserve_time' not in self.model_fields_set
                and self.details.participation_status in ('optional', 'conditional', 'other')):
            # Preserve the distinction between a derived default and an explicit
            # user flag, so old edit clients cannot overwrite stored choices.
            object.__setattr__(self, 'reserve_time', False)
        return self


class EventEdit(EventFields):
    expected_version: int = Field(ge=1)
    change_reason: str = Field(default='用户修改日程', min_length=1, max_length=500)


class EventCancel(Input):
    expected_version: int = Field(ge=1)
    expected_revision: int = Field(ge=0)
