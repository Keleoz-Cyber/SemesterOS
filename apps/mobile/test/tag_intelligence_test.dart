import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/tags/tag_intelligence.dart';

void main() {
  test('campus labels are grouped offline with concise standard names', () {
    for (final name in ['合唱', '排练', '联排', '彩排', '演出']) {
      expect(TagIntelligence.groupFor(name), 'arts');
    }
    for (final name in ['会议', '组会', '座谈会']) {
      expect(TagIntelligence.groupFor(name), 'meetings');
    }
    expect(TagIntelligence.groupFor('Python'), 'study');
    expect(TagIntelligence.groupFor('实验作业'), 'study');
    expect(TagIntelligence.groupFor('集合'), 'other');
    expect(TagIntelligence.groupFor('集合', contexts: ['合唱联排']), 'arts');
    expect(TagIntelligence.groupFor('集合', contexts: ['合唱排练', '导师组会']), 'other');
    expect(['排练', '联排', '彩排'].map(TagIntelligence.canonicalName).toSet(), {
      '排练',
    });
    expect(
      TagIntelligence.canonicalName('实验报告'),
      TagIntelligence.canonicalName('实验作业'),
    );
  });

  test('recommendations prioritize specific content over unrelated notes', () {
    final assignment = TagIntelligence.suggest(
      title: '完成Ｐｙｔｈｏｎ实验报告',
      kind: 'assignment',
    );
    expect(assignment.category, 'study');
    expect(assignment.tags, ['Python', '实验作业']);
    final rehearsal = TagIntelligence.suggest(
      title: '合唱团联合排练',
      notes: '另有Python作业和导师组会',
    );
    expect(rehearsal.category, 'affairs');
    expect(rehearsal.tags, ['合唱', '排练']);
    expect(TagIntelligence.suggest(title: 'JavaScript复习').tags, [
      'JavaScript',
      '复习',
    ]);
    expect(TagIntelligence.suggest(title: '明天下午集合').tags, isEmpty);
    expect(TagIntelligence.suggest(title: '不是考试，而是合唱彩排').tags, ['合唱', '排练']);
    expect(
      TagIntelligence.suggest(title: '会议', notes: '导师讨论课题').category,
      'research',
    );
  });

  test('new labels directly use the standard name', () {
    for (final name in ['彩排', '联排', '联合排练', '带妆排练']) {
      expect(TagIntelligence.standardName(name), '排练');
    }
    expect(TagIntelligence.standardName('演出'), '演出');
    expect(TagIntelligence.standardName('Project Alpha'), 'Project Alpha');
    for (final name in ['会议', '座谈会', '组会', '例会', '班会', '课题组例会']) {
      expect(TagIntelligence.standardName(name), '会议');
    }
    for (final name in ['分享会', '学术讲座', '学术交流']) {
      expect(TagIntelligence.standardName(name), '讲座');
    }
    expect(TagIntelligence.standardName('羽毛球'), '运动');
    expect(TagIntelligence.suggest(title: '学院班会').tags, ['会议']);
    expect(TagIntelligence.suggest(title: '导师组会').tags, ['会议']);
    expect(
      TagIntelligence.standardName('面试'),
      isNot(TagIntelligence.standardName('笔试')),
    );
  });
}
