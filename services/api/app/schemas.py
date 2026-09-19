from datetime import date, time
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Credentials(Input):
    username: str = Field(pattern=r"^[a-zA-Z0-9_]{4,32}$")
    password: str = Field(min_length=12, max_length=128)

    @field_validator("username")
    @classmethod
    def normalize(cls, value):
        return value.lower()


class Refresh(Input):
    refresh_token: str = Field(min_length=20, max_length=200)


class Recovery(Input):
    username: str = Field(min_length=4, max_length=32)
    recovery_code: str = Field(min_length=16, max_length=200)
    new_password: str = Field(min_length=12, max_length=128)


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


class CourseInput(Input):
    title: str = Field(min_length=1, max_length=120)
    teacher: str = Field(default="", max_length=120)
    location: str = Field(default="", max_length=120)
    source_id: str = Field(default="", max_length=120)
    weekday: int = Field(ge=1, le=7)
    weeks: list[int] = Field(min_length=1, max_length=30)
    sections: list[int] = Field(min_length=1, max_length=30)

    @field_validator("weeks", "sections")
    @classmethod
    def numbers(cls, values):
        if any(v < 1 or v > 30 for v in values):
            raise ValueError("周次和节次必须在1到30之间")
        return sorted(set(values))


class ImportInput(Input):
    semester_id: str = Field(min_length=1, max_length=36)
    source: Literal["haut_webview", "manual"]
    source_term: str = Field(default="", max_length=120)
    courses: list[CourseInput] = Field(min_length=1, max_length=300)


class ApplyInput(Input):
    expected_revision: int = Field(ge=0)
