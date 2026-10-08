"""School facts that do not belong in recurring CourseMeeting rows."""
import re
from sqlalchemy import select

from .models import CalendarEvent, StudyItem
from .reminder_rules import utcnow


def extra_key(extra):
    return extra['kind'], extra['source_id']


def imported_extras(db, batch):
    result = {}
    for model in (StudyItem, CalendarEvent):
        for row in db.scalars(select(model).where(
                model.user_id == batch.user_id, model.semester_id == batch.semester_id)):
            origin = row.payload.get('import_origin', {})
            if (origin.get('source') == batch.source and
                    origin.get('source_term', '') == batch.source_term):
                result[(origin.get('kind'), origin.get('source_id'))] = row
    return result


def classify_extras(db, batch):
    if not batch.extras:
        return [], [], 0, []
    existing = imported_extras(db, batch)
    changes, fresh, protected = [], [], []
    unchanged = 0
    for extra in batch.extras or []:
        old = existing.get(extra_key(extra))
        if old is None:
            fresh.append(extra)
            continue
        origin = old.payload['import_origin']
        if extra == origin.get('last_source'):
            unchanged += 1
        elif old.version != origin.get('imported_version') or old.lifecycle != 'active':
            # A school reimport must not silently undo a personal edit or
            # cancellation. Independently stored reminders are retained below.
            protected.append({'resource_id': old.id, 'kind': extra['kind'],
                'before': origin.get('last_source'), 'after': extra,
                'reason': 'manually_edited'})
        else:
            changes.append({'resource_id': old.id, 'kind': extra['kind'],
                'before': origin.get('last_source'), 'after': extra})
    return changes, fresh, unchanged, protected


def extra_payload(db, user, semester, extra):
    from .item_schemas import ItemCreate
    from .event_schemas import EventFields
    from .event_store import tag_ids
    raw = extra.get('raw_text', '')
    note_lines = []
    for line in extra.get('notes', '').splitlines():
        line = line.strip()
        content = re.sub(r'^备注\s*[:：]\s*', '', line).casefold()
        if content not in ('', '无', 'none', 'null', '暂无', '无备注'):
            note_lines.append(line)
    if extra.get('teacher'):
        note_lines.append('教师：' + extra['teacher'])
    if extra['kind'] == 'exam':
        from .items import checked_payload
        when = {'precision': 'unknown', 'meaning': 'start'}
        if extra.get('start_at'):
            when = {'precision': 'exact', 'meaning': 'start', 'at': extra['start_at']}
            if extra.get('end_at'):
                when['end_at'] = extra['end_at']
        elif extra.get('date'):
            when = {'precision': 'date', 'meaning': 'start', 'date': extra['date']}
        body = ItemCreate(semester_id=semester.id, kind='exam', title=extra['title'],
            location=extra.get('location', ''), certainty='formal',
            time=when, source_text=raw, notes='\n'.join(note_lines)[:3000],
            category_id='study', tags=['考试'])
        value, _ = checked_payload(db, user, body)
        return value
    weeks = extra.get('weeks', [])
    groups = []
    for week in weeks:
        if not groups or groups[-1][-1] + 1 != week:
            groups.append([])
        groups[-1].append(week)
    week_text = '、'.join(str(g[0]) if len(g) == 1 else f'{g[0]}—{g[-1]}' for g in groups)
    notes = f'第{week_text}周' if weeks else ''
    notes = '\n'.join(v for v in (notes, *note_lines) if v)[:3000]
    body = EventFields(semester_id=semester.id, expected_revision=semester.revision,
        title=extra['title'], category_id='study', tags=['课程', '实践课'],
        time={'precision': 'unknown'}, reserve_time=False,
        location=extra.get('location', ''), notes=notes, source_text=raw)
    value = body.model_dump(mode='json', exclude={'semester_id', 'expected_revision', 'tags',
        'confirm_fixed_conflicts', 'course_leave_targets'})
    value['tag_ids'] = tag_ids(db, user, body.tags)
    return value


def apply_extras(db, user, semester, batch, changes, fresh):
    if not changes and not fresh:
        return 0, 0
    from .items import audit
    from .calendar_events import record
    existing = imported_extras(db, batch)
    now = utcnow().isoformat()
    for extra in [*fresh, *(change['after'] for change in changes)]:
        row = existing.get(extra_key(extra))
        value = extra_payload(db, user, semester, extra)
        if row is None:
            model = StudyItem if extra['kind'] == 'exam' else CalendarEvent
            row = model(user_id=user.id, semester_id=semester.id, version=1,
                        payload=value, lifecycle='active', created_at=now, updated_at=now)
            db.add(row)
        else:
            row.version += 1
            row.updated_at = now
            if extra['kind'] == 'exam':
                from .items import rules_for
                for rule in rules_for(db, row):
                    rule.version += 1
                    rule.updated_at = now
            # Imports have no reminder defaults: retain personal reminder rules.
            # A recurring school update is not a request to remove them.
            if extra['kind'] == 'unplaced_course':
                value['reminder_minutes'] = row.payload.get('reminder_minutes', [])
        value['import_origin'] = {'source': batch.source, 'source_term': batch.source_term,
            'source_id': extra['source_id'], 'kind': extra['kind'],
            'last_source': extra, 'imported_version': row.version}
        row.payload = value
        db.flush()
        if extra['kind'] == 'exam':
            audit(db, row, '导入教务考试' if row.version == 1 else '重新导入教务考试')
        else:
            record(db, row, '导入未排时段课程' if row.version == 1 else '重新导入未排时段课程')
    return len(fresh), len(changes)
