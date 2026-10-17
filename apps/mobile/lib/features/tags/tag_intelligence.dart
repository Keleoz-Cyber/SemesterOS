import 'dart:convert';
import 'tag_rules.g.dart';

class TagSuggestion {
  final String? category;
  final List<String> tags;
  const TagSuggestion(this.category, this.tags);
}

/// The same vocabulary as the backend, available offline and on older servers.
abstract final class TagIntelligence {
  static final _data = jsonDecode(tagRuleJson) as Map<String, dynamic>;
  static final groups = (_data['groups'] as List)
      .map((r) => Map<String, String>.from(r as Map))
      .toList(growable: false);
  static final _rules = (_data['rules'] as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList(growable: false);
  static final _patterns = <String, RegExp>{};

  static String normalize(String text) => String.fromCharCodes(
    text.runes.map(
      (c) => c == 0x3000
          ? 32
          : c >= 0xFF01 && c <= 0xFF5E
          ? c - 0xFEE0
          : c,
    ),
  ).toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _positive(String value) => normalize(value)
      .replaceAll(RegExp(r'(?:不是|并非)([^，。；;\n]{0,40}?)而是'), '')
      .replaceAll(RegExp(r'(?:不是|并非|不涉及)[^，。；;\n]*'), '');

  static List<String> _names(Map<String, dynamic> r) => [
    r['name'] as String,
    ...List<String>.from(r['aliases'] as List),
    ...List<String>.from(
      (_data['equivalents'] as Map)[r['name']] as List? ?? [],
    ),
  ];
  static bool _matches(String text, Map<String, dynamic> rule) =>
      _names(rule).any((value) {
        final term = normalize(value);
        final pattern = _patterns.putIfAbsent(term, () {
          final left = RegExp(r'^[a-z0-9]').hasMatch(term)
              ? r'(?<![a-z0-9])'
              : '';
          final right = term.codeUnitAt(term.length - 1) < 128
              ? r'(?![a-z0-9])'
              : '';
          return RegExp('$left${RegExp.escape(term)}$right');
        });
        return pattern.hasMatch(text);
      });

  static String canonicalName(String name) {
    final key = normalize(name);
    for (final entry in (_data['equivalents'] as Map).entries) {
      if ([
        '${entry.key}',
        ...List<String>.from(entry.value as List),
      ].any((s) => normalize(s) == key)) {
        return '${entry.key}';
      }
    }
    for (final rule in _rules) {
      if (normalize('${rule['name']}') == key) {
        return rule['name'] as String;
      }
    }
    return key;
  }

  static String standardName(String name) {
    final canonical = canonicalName(name);
    return _rules.any((r) => r['name'] == canonical)
        ? canonical
        : name.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static TagSuggestion suggest({
    String title = '',
    String notes = '',
    String kind = '',
    String courseTitle = '',
  }) {
    final text = _positive('$title $courseTitle');
    final found = _rules.where((r) => _matches(text, r)).toList();
    final suppressed = <String>{
      for (final r in found)
        ...List<String>.from(r['suppresses'] as List? ?? []),
    };
    found.removeWhere((r) => suppressed.contains(r['name']));
    found.sort((a, b) {
      final rank = (b['priority'] as int).compareTo(a['priority'] as int);
      return rank == 0
          ? (a['name'] as String).compareTo(b['name'] as String)
          : rank;
    });
    var tags = found
        .map((r) => standardName(r['name'] as String))
        .toSet()
        .take(3)
        .toList();
    if (kind == 'exam' && !tags.contains('考试')) tags = [...tags.take(2), '考试'];
    if (kind == 'assignment' &&
        !tags.any({'作业', '实验作业', '课程设计', '毕业设计'}.contains)) {
      tags = [...tags.take(2), '作业'];
    }
    String? category;
    if (kind == 'assignment' || kind == 'exam' || courseTitle.isNotEmpty) {
      category = 'study';
    } else {
      final votes = <String, int>{};
      for (final r in found) {
        final key = r['category'] as String?;
        if (key != null) {
          votes[key] = (votes[key] ?? 0) + (r['priority'] as int);
        }
      }
      final ranked = votes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (ranked.isNotEmpty &&
          (ranked.length == 1 || ranked[0].value > ranked[1].value)) {
        category = ranked[0].key;
      }
      final contextualMeeting =
          found.any((r) => r['group'] == 'meetings') &&
          found.every(
            (r) =>
                r['group'] == 'campus' ||
                {'会议', '组会', '座谈会'}.contains(r['name']),
          );
      if (category == null || contextualMeeting) {
        final context = _positive(notes);
        final hints = Map<String, dynamic>.from(_data['category_hints'] as Map);
        final scores = {
          for (final entry in hints.entries)
            entry.key:
                (entry.value as List)
                        .where((h) => text.contains(h as String))
                        .length *
                    4 +
                (entry.value as List)
                    .where((h) => context.contains(h as String))
                    .length,
        };
        final top = scores.values.fold(0, (a, b) => a > b ? a : b);
        final winners = scores.entries
            .where((e) => e.value == top && top > 0)
            .toList();
        if (winners.length == 1) category = winners.single.key;
      }
    }
    return TagSuggestion(category, tags);
  }

  static String groupFor(String name, {List<String> contexts = const []}) {
    final value = normalize(name);
    for (final r in _rules) {
      if (_names(r).any((s) => normalize(s) == value)) {
        return r['group'] as String;
      }
    }
    final own = _rules.where((r) => _matches(value, r)).toList()
      ..sort((a, b) => (b['priority'] as int).compareTo(a['priority'] as int));
    if (own.isNotEmpty) return own.first['group'] as String;
    final votes = <String, int>{};
    for (final title in contexts) {
      final hits = _rules
          .where((r) => _matches(_positive(title), r))
          .map((r) => r['group'] as String)
          .toSet();
      if (hits.length == 1) votes[hits.single] = (votes[hits.single] ?? 0) + 1;
    }
    final ranked = votes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isNotEmpty &&
        (ranked.length == 1 || ranked[0].value >= 2 * ranked[1].value)) {
      return ranked[0].key;
    }
    return 'other';
  }

  static List<Map<String, dynamic>> organize(List<Map<String, dynamic>> tags) =>
      tags.map((tag) {
        final supplied = tag['group_id'];
        return {
          ...tag,
          'group_id': groups.any((g) => g['id'] == supplied)
              ? supplied
              : groupFor(
                  '${tag['name']}',
                  contexts: (tag['examples'] as List? ?? [])
                      .map((s) => '$s')
                      .toList(),
                ),
        };
      }).toList();
}
