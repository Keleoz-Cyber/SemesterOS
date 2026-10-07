"""Device opt-in class reminders from the same effective timetable projection."""
from datetime import timedelta
from hashlib import sha256
import json

from sqlalchemy import select
from .models import Semester
from .occurrences import effective_courses, expand
from .reminder_rules import instant, utcnow
from .course_participation import course_requires_attendance


def course_reminders(db, user, lead_minutes, now=None):
    now = now or utcnow()
    result = []
    for semester in db.scalars(select(Semester).where(Semester.user_id == user.id)):
        calendar = {'first_monday': semester.first_monday, 'periods': semester.periods}
        for event in expand(calendar, effective_courses(db, user, semester)):
            # Independent change additions have no persisted course details to
            # navigate to; their own fixed-event reminders remain authoritative.
            if not event.get('course_id') or not course_requires_attendance(event):
                continue
            start = instant(event['start_at'])
            trigger = start - timedelta(minutes=lead_minutes)
            # This version describes the occurrence itself, so editing an
            # unrelated task or course never invalidates a delivered alarm.
            identity = [event['id'], start.isoformat(), event.get('end_at'),
                        event['title'], event.get('location', '')]
            version = sha256(json.dumps(identity, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()[:20]
            result.append({
                'id': f"course:{event['id']}:before:{lead_minutes}",
                'item_id': 'course:' + event['course_id'],
                'resource_type': 'course', 'resource_id': event['course_id'],
                'occurrence_id': event['id'], 'semester_id': semester.id,
                'version': version, 'item_version': version,
                'title': event['title'], 'start_at': start.isoformat(),
                'place': event.get('location', ''), 'can_complete': False,
                'time_meaning': 'start', 'purpose': 'item', 'mode': 'relative',
                'lead_minutes': lead_minutes, 'enabled': True,
                'trigger_at': trigger.isoformat(),
                'schedule_state': 'expired' if trigger <= now else 'scheduled',
            })
    return sorted(result, key=lambda r: (r['trigger_at'], r['id']))
