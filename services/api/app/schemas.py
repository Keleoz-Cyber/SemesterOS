from datetime import date, datetime, time, timezone
from datetime import date as CalendarDate
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Credentials(Input):
    username: str = Field(pattern=r"^[a-zA-Z0-9_]{4,32}$")
    password: str = Field(min_length=8, max_length=128)

    @field_validator("username")
    @classmethod
    def normalize(cls, value):
        return value.lower()


class Refresh(Input):
    refresh_token: str = Field(min_length=20, max_length=200)


class Recovery(Input):
    username: str = Field(min_length=4, max_length=32)
    recovery_code: str = Field(min_length=16, max_length=200)
    new_password: str = Field(min_length=8, max_length=128)


class Logout(Input):
    logout_token: str = Field(min_length=20, max_length=200)


class Period(Input):
    number: int = Field(ge=1, le=30)
    start: str = Field(pattern=r"^\d{2}:\d{2}$")
    end: str = Field(pattern=r"^\d{2}:\d{2}$")

    @model_validator(mode="after")
    def ordered(self):
        if time.fromisoformat(self.start) >= time.fromisoformat(self.end):
            raise ValueError("结束时间必须晚于开始时间")
        return self


class SemesterInput(Input):
    name: str = Field(min_length=1, max_length=80)
    first_monday: date
    total_weeks: int = Field(ge=1, le=30)
    periods: list[Period] = Field(min_length=1, max_length=30)

    @model_validator(mode="after")
    def calendar(self):
        if self.first_monday.weekday() != 0:
            raise ValueError("第一周起始日必须是周一")
        self.periods.sort(key=lambda p: p.number)
        if len({p.number for p in self.periods}) != len(self.periods):
            raise ValueError("节次编号不能重复")
        if any(a.end > b.start for a, b in zip(self.periods, self.periods[1:])):
            raise ValueError("节次时间不能重叠或倒序")
        return self


class SemesterUpdate(SemesterInput):
    expected_revision: int = Field(ge=0)


class CourseInput(Input):
    title: str = Field(min_length=1, max_length=120)
    teacher: str = Field(default="", max_length=120)
    location: str = Field(default="", max_length=120)
    source_id: str = Field(default="", max_length=120)
    weekday: int = Field(ge=1, le=7)
    weeks: list[int] = Field(min_length=1, max_length=30)
    sections: list[int] = Field(min_length=1, max_length=30)
    start_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    end_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    attendance_exempt: bool = False

    @model_validator(mode="after")
    def school_times(self):
        if (self.start_time is None) != (self.end_time is None):
            raise ValueError("课程起止时刻需要一起提供")
        if self.start_time is not None:
            if time.fromisoformat(self.start_time) >= time.fromisoformat(self.end_time):
                raise ValueError("课程结束时刻必须晚于开始时刻")
            if any(b != a + 1 for a, b in zip(self.sections, self.sections[1:])):
                raise ValueError("有明确起止时刻的课次需要连续节次")
        return self

    @field_validator("weeks", "sections")
    @classmethod
    def numbers(cls, values):
        if any(v < 1 or v > 30 for v in values):
            raise ValueError("周次和节次必须在1到30之间")
        return sorted(set(values))


class CourseUpdate(CourseInput):
    expected_revision: int = Field(ge=0)


class ImportExtra(Input):
    kind: Literal["exam", "unplaced_course"]
    source_id: str = Field(min_length=1, max_length=120)
    title: str = Field(min_length=1, max_length=120)
    teacher: str = Field(default="", max_length=120)
    location: str = Field(default="", max_length=120)
    weeks: list[int] = Field(default_factory=list, max_length=30)
    start_at: datetime | None = None
    end_at: datetime | None = None
    date: CalendarDate | None = None
    notes: str = Field(default="", max_length=3000)
    raw_text: str = Field(default="", max_length=10000)

    @field_validator("weeks")
    @classmethod
    def numbers(cls, values):
        return CourseInput.numbers(values)

    @field_validator("start_at", "end_at")
    @classmethod
    def aware(cls, value):
        if value is not None:
            if value.tzinfo is None:
                raise ValueError("考试时刻必须包含时区")
            return value.astimezone(timezone.utc)
        return value

    @model_validator(mode="after")
    def valid_kind(self):
        if self.kind == "exam":
            if self.end_at is not None and (self.start_at is None or self.end_at <= self.start_at):
                raise ValueError("考试结束时间需要晚于已知的开始时间")
        elif self.start_at is not None or self.end_at is not None:
            raise ValueError("未排时段课程不能补造考试时刻")
        return self


class ImportInput(Input):
    semester_id: str = Field(min_length=1, max_length=36)
    source: Literal["haut_webview", "hlju_webview", "manual"]
    source_term: str = Field(default="", max_length=120)
    courses: list[CourseInput] = Field(default_factory=list, max_length=300)
    extras: list[ImportExtra] = Field(default_factory=list, max_length=300)
    source_first_monday: date | None = None

    @model_validator(mode="after")
    def nonempty(self):
        if not self.courses and not self.extras:
            raise ValueError("没有可导入的课程或考试")
        if self.extras and self.source != "hlju_webview":
            raise ValueError("当前来源不支持附加课表记录")
        if self.source_first_monday is not None and self.source_first_monday.weekday() != 0:
            raise ValueError("学校第一周起始日必须是周一")
        return self


class ApplyInput(Input):
    expected_revision: int = Field(ge=0)
    replace_changed: bool = False
    remove_missing: bool = False
