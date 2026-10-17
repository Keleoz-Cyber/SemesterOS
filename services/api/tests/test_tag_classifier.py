import json
from pathlib import Path

import pytest
from sqlalchemy.orm import Session

from app.models import CalendarTag
from app.tag_classifier import RULES, automatic_fields, canonical_name, group_for, infer
from test_foundation import client, register, semester
from test_insights import event, item


@pytest.mark.parametrize('name,group', [
    ('Python', 'study'), ('实验作业', 'study'), ('会议', 'meetings'), ('座谈会', 'meetings'),
    ('组会', 'meetings'), ('合唱', 'arts'), ('排练', 'arts'), ('联排', 'arts'),
    ('彩排', 'arts'), ('演出', 'arts'), ('集合', 'other'), ('自定义内容', 'other'),
])
def test_original_screenshot_labels_have_useful_groups(name, group):
    assert group_for(name) == group


@pytest.mark.parametrize('title,kind,category,tags', [
    ('交Python实验报告', 'assignment', 'study', ['Python', '实验作业']),
    ('准备JavaScript课后作业', 'assignment', 'study', ['JavaScript', '作业']),
    ('完成Ｃ＋＋作业', 'assignment', 'study', ['C++', '作业']),
    ('合唱团联合排练', 'event', 'affairs', ['合唱', '排练']),
    ('合唱带妆排练', 'event', 'affairs', ['合唱', '排练']),
    ('参加学院座谈会', 'event', 'affairs', ['会议']),
    ('导师组会', 'event', 'research', ['会议']),
    ('学生会组会', 'event', 'affairs', ['会议', '学生工作']),
    ('不是考试，而是合唱彩排', 'event', 'affairs', ['合唱', '排练']),
    ('明天下午集合', 'event', None, []),
    ('JavaScript复习', 'task', 'study', ['JavaScript', '复习']),
    ('公司笔试', 'event', 'life', ['笔试']),
    ('部门碰头会', 'event', None, ['会议']),
])
def test_suggestions_use_specific_titles_without_topic_spam(title, kind, category, tags):
    result = infer(title, kind=kind)
    assert result['category_id'] == category
    assert result['tags'] == tags


def test_source_context_disambiguates_meeting_without_importing_other_topics():
    assert infer('会议', source='辅导员通知周五开会')['category_id'] == 'affairs'
    assert infer('会议', notes='与导师讨论课题')['category_id'] == 'research'
    assert infer('合唱彩排', notes='通知里另外还提到了Python作业和科研组会')['tags'] == ['合唱', '排练']
    assert infer('写报告', kind='assignment', course_title='Python程序设计')['category_id'] == 'study'
    assert group_for('集合', ['合唱联排集合']) == 'arts'
    assert group_for('集合', ['合唱集合', '导师组会集合']) == 'other'


def test_rehearsal_variants_share_one_filter_but_performance_stays_separate():
    assert {canonical_name(s) for s in ['排练', '联排', '彩排', '联合排练', '带妆排练']} == {'排练'}
    assert canonical_name('演出') != canonical_name('排练')
    assert canonical_name('开会') == canonical_name('会议')
    assert canonical_name('联合排练') == canonical_name('联排')
    assert canonical_name('实验报告') == canonical_name('实验作业')
    assert canonical_name('会议') == canonical_name('座谈会')
    assert canonical_name('Python') == canonical_name('Python程序设计')


@pytest.mark.parametrize('canonical,names', [
    ('会议', ['会议', '组会', '座谈会', '班会', '例会', '讨论会', '部门例会']),
    ('讲座', ['分享会', '学术讲座', '学术交流', '报告会']),
    ('实验作业', ['实验报告', '实验课作业', '上机作业']),
    ('运动', ['篮球', '足球', '羽毛球', '健身', '跑步', '游泳']),
])
def test_coarse_purpose_tags_are_canonical(canonical, names):
    assert {canonical_name(s) for s in names} == {canonical}


def test_distinct_subjects_actions_and_custom_names_are_not_merged():
    names = ['Python', 'Java', '面试', '笔试', '排练', '演出', '会议', '讲座', '我的项目']
    assert len({canonical_name(n) for n in names}) == len(names)


def test_model_generated_tags_are_ignored_but_direct_user_labels_are_preserved():
    fields = {'title': '合唱联排', 'category_id': 'research', 'tags': ['集合', '今晚', '会议', '合唱联排']}
    assert automatic_fields(fields)['tags'] == ['合唱', '排练']
    assert automatic_fields(fields)['category_id'] == 'affairs'
    custom = automatic_fields(fields, '合唱联排，标签设为社团、重要。分类设为生活')
    assert custom['tags'] == ['社团', '重要']
    assert custom['category_id'] == 'life'


def test_mobile_and_server_share_exactly_the_same_vocabulary():
    root = Path(__file__).resolve().parents[3]
    dart = (root / 'apps/mobile/lib/features/tags/tag_rules.g.dart').read_text(encoding='utf-8')
    assert json.loads(dart.split("r'''", 1)[1].split("'''", 1)[0]) == RULES


def test_tag_grouping_is_read_only_with_owned_context(client, monkeypatch):
    monkeypatch.delenv('DEEPSEEK_API_KEY', raising=False)
    _, owner = register(client); _, other = register(client, 'another')
    sid = semester(client, owner)['id']; foreign = semester(client, other)['id']
    for title, tags in [
        ('Python实验报告', ['Python', '实验作业']), ('合唱联排', ['合唱', '联排', '集合']),
        ('演出彩排', ['排练', '彩排', '演出']), ('学院座谈会', ['座谈会']),
        ('导师组会', ['组会']), ('项目会议', ['会议', '开会']),
    ]:
        item(client, owner, sid, title=title, tags=tags)
    item(client, other, foreign, title='科研组会集合', tags=['集合', '其他账号'])
    with Session(client.app.state.engine) as db:
        before = [(t.id, t.name, t.version, t.merged_into) for t in db.query(CalendarTag).order_by(CalendarTag.id)]
    data = client.get('/api/v1/tags', headers=owner).json()
    tags = {t['name']: t for t in data['tags']}
    assert tags['集合']['group_id'] == 'arts'
    assert tags['集合']['usage_count'] == 1
    assert tags['集合']['examples'] == ['合唱联排']
    assert '其他账号' not in tags
    assert 'suggestions' not in data
    assert '联排' not in tags and '彩排' not in tags
    assert tags['排练']['usage_count'] == 2
    with Session(client.app.state.engine) as db:
        assert before == [(t.id, t.name, t.version, t.merged_into) for t in db.query(CalendarTag).order_by(CalendarTag.id)]
