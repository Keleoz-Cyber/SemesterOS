"""Recording an activity never invents attendance permission or a clock."""
import pytest

from app.agent_education import has_leave_record_intent
from app.notice_event_time import normalize_notice_event_time
from app.reminder_rules import anchor_at


@pytest.mark.parametrize('text', [
    '我明天全天外出，一整天都不在学校，帮我记录并核对课程',
    '明天9点班主任会议',
    '我准备请假去参会',
    '我要请好假后去开会',
    '我已经申请请假，等待老师批准',
    '已经提交了请假申请，还没批',
])
def test_activity_and_pending_application_are_not_excused_attendance(text):
    assert not has_leave_record_intent(text)


@pytest.mark.parametrize('text', [
    '我明天软件工程已经请假了',
    '请给软件工程记录为已请假',
    '我请过这节课的假了',
    '老师已经允许我这次不去上课',
    '请假申请已经通过',
])
def test_explicit_personal_attendance_record_needs_no_school_proof(text):
    assert has_leave_record_intent(text)


def test_explicit_all_day_stays_a_date_without_a_midnight_reminder_anchor():
    fields = {'title': '全天外出', 'time': {'precision': 'date', 'date': '2026-10-09',
        'expression': '明天全天'}}
    value = normalize_notice_event_time(fields, '我明天全天外出，一整天都不在学校')
    assert value['time']['precision'] == 'date'
    assert value['time']['meaning'] == 'all_day'
    assert not value['time'].get('at') and not value['time'].get('end_at')
    assert anchor_at(value) is None
    assert 'meaning' not in fields['time']


@pytest.mark.parametrize('time,source', [
    ({'precision': 'date', 'date': '2026-10-09', 'expression': '明天有个活动'}, '明天有个活动'),
    ({'precision': 'date', 'date': '2026-10-09', 'expression': '明天下午'}, '另一项活动是全天，会议只有日期'),
    ({'precision': 'date', 'date': '2026-10-09', 'expression': '明天不是全天'}, '明天不是全天'),
    ({'precision': 'date', 'date': '2026-10-09', 'expression': '全天开放', 'meaning': 'window'}, '办理窗口全天开放'),
    ({'precision': 'exact', 'at': '2026-10-09T09:00:00+08:00', 'expression': '明天9点'}, '明天9点会议，整天还另有其他活动'),
])
def test_plain_date_or_another_activity_does_not_fabricate_day_occupancy(time, source):
    fields = {'title': '本项通知', 'time': time}
    assert normalize_notice_event_time(fields, source) == fields
