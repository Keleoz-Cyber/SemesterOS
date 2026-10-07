"""Deterministic necessary-condition checks, not a schedule or a prediction of grades."""
from bisect import bisect_right
from datetime import datetime, timedelta, timezone
from math import floor

from .reminder_rules import SHANGHAI, anchor_at, instant, reservation_enabled
from .plan_rules import classify, occupied_seconds, future_minutes
from .task_readiness import start_policy
from .course_participation import course_requires_attendance


def merge(spans):
    result = []
    for start, end in sorted((a, b) for a, b in spans if b > a):
        if result and start <= result[-1][1]:
            result[-1] = (result[-1][0], max(end, result[-1][1]))
        else:
            result.append((start, end))
    return result


def subtract(spans, blocked):
    result, index = [], 0
    for start, end in merge(spans):
        while index < len(blocked) and blocked[index][1] <= start:
            index += 1
        cursor, j = start, index
        while j < len(blocked) and blocked[j][0] < end:
            a, b = blocked[j]
            if a > cursor:
                result.append((cursor, min(a, end)))
            cursor = max(cursor, b)
            if cursor >= end:
                break
            j += 1
        if cursor < end:
            result.append((cursor, end))
    return result


class CapacityIndex:
    def __init__(self, spans):
        self.spans = merge(spans)
        self.starts = [a for a, _ in self.spans]
        self.prefix = [0.0]
        for a, b in self.spans:
            self.prefix.append(self.prefix[-1] + b - a)

    def before(self, point):
        i = bisect_right(self.starts, point) - 1
        if i < 0:
            return 0.0
        a, b = self.spans[i]
        return self.prefix[i] + min(point - a, b - a)

    def minutes(self, start, end):
        return max(0, floor((self.before(end) - self.before(start)) / 60)) if end > start else 0

    def longest(self, start, end):
        return max([0] + [max(0, floor((min(end, b) - max(start, a)) / 60)) for a, b in self.spans])


def local_day(value):
    return datetime.fromisoformat(value).replace(tzinfo=SHANGHAI)


def minute(value):
    hour, minute = map(int, value.split(':'))
    return hour * 60 + minute


def iso(stamp):
    return datetime.fromtimestamp(stamp, timezone.utc).isoformat()


def uncertainty_affects_window(warning, start, end):
    """Avoidance boundaries do not establish when an unfinished record ends."""
    return start < end and (warning['unbounded'] or
        instant(warning['start_at']).timestamp() < end and
        (warning.get('end_unknown', False) or instant(warning['end_at']).timestamp() > start))


def course_intervals(semester, courses):
    from .occurrences import expand
    return [(instant(e['start_at']).timestamp(),instant(e['end_at']).timestamp(),e['id'],e['title'])
            for e in expand(semester,courses) if course_requires_attendance(e)]


def exam_window(exam, semester_start, semester_end):
    t = exam['time']
    if t['precision'] == 'exact':
        return instant(t['at']).timestamp(), instant(t['end_at']).timestamp() if t.get('end_at') else semester_end
    if t['precision'] == 'week':
        start = semester_start + (t['week'] - 1) * 7 * 86400
        return start, start + 7 * 86400
    if t['precision'] in ('date', 'range'):
        return local_day(t['date']).timestamp(), (local_day(t.get('end_date') or t['date']) + timedelta(days=1)).timestamp()
    return semester_start, semester_end


def calendar_context(semester, availability, courses, items, now, *, query_dates=None):
    from .reminder_rules import notice_arrival_at
    current = now.timestamp()
    semester_start = local_day(semester['first_monday']).timestamp()
    semester_end = semester_start + semester['total_weeks'] * 7 * 86400
    available_start, available_end = semester_start, semester_end
    if query_dates is not None:
        available_start = local_day(query_dates[0].isoformat()).timestamp()
        available_end = local_day((query_dates[1] + timedelta(days=1)).isoformat()).timestamp()
    begin = max(current, available_start)
    available = []
    for day in range(round((available_end - available_start) / 86400)):
        base = available_start + day * 86400
        weekday = datetime.fromtimestamp(base, SHANGHAI).isoweekday()
        for w in availability.get('weekly', []):
            if weekday == w['weekday']:
                available.append((max(begin, base + minute(w['start']) * 60), min(available_end, base + minute(w['end']) * 60)))
    available = merge(available)
    school = course_intervals(semester, courses)
    exams = [i for i in items if i['kind'] == 'exam' and i['lifecycle'] == 'active']
    uncertain = [];uncertainty_exclusions=[];uncertainty_warnings=[]
    def note_uncertainty(record,a,b,missing,eid):
        t=record['time'];unbounded=t['precision']=='unknown'
        end_unknown=missing and t['precision']=='exact' and not t.get('end_at')
        # This is an avoidance policy for the solver, never an inferred record
        # end. A stated start with no end affects the remainder of that local day.
        if missing and t['precision']=='exact':
            day=instant(t['at']).astimezone(SHANGHAI).date()
            b=(local_day(str(day))+timedelta(days=1)).timestamp()
        uncertain.append((a,b,missing,eid))
        if missing and not unbounded:uncertainty_exclusions.append((a,b))
        if unbounded:
            message=f'「{record["title"]}」日期未说明，未据此封锁其他学习时段；具体时间明确后需核对已有计划。'
        elif end_unknown:
            message=f'「{record["title"]}」缺少结束时间，开始当天的剩余时段暂不排学习；其他日期按已知安排核对。'
        elif missing:
            message=f'「{record["title"]}」起止时间未完整说明，排程只避开其已知日期范围，其他日期仍可安排。'
        else:message=f'「{record["title"]}」是参考或暂定安排，按已记录的预留选择计算。'
        uncertainty_warnings.append({'id':eid,'title':record['title'],'message':message,
            'scope':'undated' if unbounded else 'known_dates',
            'start_at':None if unbounded else iso(a),'end_at':None if unbounded else iso(b),
            'exclusion_applied':missing and not unbounded,'unbounded':unbounded,
            'end_unknown':bool(end_unknown),'could_affect_occupancy':missing})
    for exam in exams:
        if exam['time'].get('meaning') in ('window', 'candidate', 'course_anchor'):
            continue
        a, b = exam_window(exam, semester_start, semester_end)
        arrival = notice_arrival_at(exam)
        if arrival: a = arrival.timestamp()
        reserved = reservation_enabled(exam, 'exam')
        complete = exam['time']['precision'] == 'exact' and exam['time'].get('end_at') is not None
        if reserved and complete:
            school.append((a, b, exam['id'], exam['title'] + ('（暂定预留）' if exam.get('certainty') != 'formal' else '')))
        if not complete or exam.get('certainty') != 'formal':
            note_uncertainty(exam,a,b,reserved and not complete,exam['id'])
    for event in semester.get('fixed_events', []):
        if not reservation_enabled(event, 'event'):
            continue
        if event['time'].get('meaning') in ('window', 'candidate', 'course_anchor'):
            continue
        a, b = exam_window(event, semester_start, semester_end)
        arrival = notice_arrival_at(event)
        if arrival: a = arrival.timestamp()
        complete = event['time']['precision'] == 'exact' and event['time'].get('end_at') is not None
        eid = 'event:' + event['id']
        if complete:
            school.append((a, b, eid, event['title']))
        if not complete or event.get('certainty') != 'formal':
            note_uncertainty(event,a,b,not complete,eid)
    school = sorted(r for r in school if r[1] > begin and r[0] < available_end)
    conflicts, active = [], []
    for row in school:
        a, b, id, title = row
        active = [old for old in active if old[1] > a]
        for old in active:
            conflicts.append({'start_at': iso(max(a, old[0])), 'end_at': iso(min(b, old[1])),
                              'titles': [old[3], title], 'item_ids': [old[2], id]})
        active.append(row)
    blocked = [(a, b) for a, b, _, _ in school]
    blocked += [(instant(r['start_at']).timestamp(), instant(r['end_at']).timestamp()) for r in availability.get('exclusions', [])]
    total = CapacityIndex(available)
    known_free=CapacityIndex(subtract(available,merge(blocked)))
    free = CapacityIndex(subtract(available, merge(blocked+uncertainty_exclusions)))
    return {'current':current,'begin':begin,'semester_end':semester_end,'total':total,'free':free,
            'uncertain':uncertain,'conflicts':conflicts,'known_free':known_free,
            'uncertainty_warnings':uncertainty_warnings}


def analyze(semester, availability, courses, items, now, plans=()):
    context=calendar_context(semester,availability,courses,items,now)
    current,begin,semester_end=(context[k] for k in ('current','begin','semester_end'))
    total,free,uncertain,conflicts=(context[k] for k in ('total','free','uncertain','conflicts'))
    valid_plans,plan_issues=classify(plans,items,free.spans,begin)
    tasks = [i for i in items if i['kind'] != 'exam' and i['lifecycle'] == 'active']
    limit = len(tasks) > 200
    result, ready = [], []
    for item in tasks:
        reasons = []
        due_value = anchor_at(item)
        due = due_value.timestamp() if due_value else None
        policy = start_policy(item)
        release = max(begin, instant(item['earliest_start_at']).timestamp()) if policy == 'at' and item.get('earliest_start_at') else begin
        remaining = item.get('remaining_minutes')
        if not availability.get('configured'):
            reasons.append('needs_availability')
        if remaining is None:
            reasons.append('needs_estimate')
        if due is None:
            reasons.append('needs_deadline')
        if item.get('certainty') != 'formal':
            reasons.append('needs_deadline_confirmation')
        if policy == 'unconfirmed':
            reasons.append('needs_start')
        if due is not None and due > semester_end:
            reasons.append('outside_semester')
        if limit:
            reasons.append('analysis_limit')
        affected=[w for w in context['uncertainty_warnings'] if due is not None and uncertainty_affects_window(w,release,due)]
        occupancy_incomplete=any(w['could_affect_occupancy'] for w in affected)
        tentative_exam = bool(affected)
        if tentative_exam:
            reasons.append('uncertain_fixed' if any(w['id'].startswith('event:') for w in affected) else 'uncertain_exam')
        missing = any(r.startswith('needs_') or r in ('outside_semester', 'analysis_limit') for r in reasons)
        can_count = availability.get('configured') and due is not None and due <= semester_end and policy != 'unconfirmed' and remaining is not None and item.get('certainty') == 'formal' and not limit
        before = total.minutes(release, due) if can_count else None
        calendar_capacity=free.minutes(release,due) if can_count else None
        known_capacity=context['known_free'].minutes(release,due) if can_count else None
        unbounded=any(w['could_affect_occupancy'] and (w['unbounded'] or
            w.get('end_unknown') and instant(w['end_at']).timestamp() <= release) for w in affected)
        other_seconds=occupied_seconds(valid_plans,release,due,{item['id']}) if can_count and due>release else 0
        capacity=max(0,floor((free.before(due)-free.before(release)-other_seconds)/60)) if can_count and due>release else 0 if can_count else None
        slack = capacity - remaining if can_count and not occupancy_incomplete else None
        other_spans=merge([(instant(b['start_at']).timestamp(),instant(b['end_at']).timestamp()) for b in valid_plans if b['item_id']!=item['id']])
        longest = CapacityIndex(subtract(free.spans,other_spans)).longest(release,due) if can_count else None
        own_coverage=sum(future_minutes(b,current) for b in valid_plans if b['item_id']==item['id'])
        plan_problem=any(p['item_id']==item['id'] for p in plan_issues)
        if plan_problem:reasons.append('plan_conflict')
        if remaining is not None and own_coverage>remaining:reasons.append('plan_overcoverage');plan_problem=True
        hard = due is not None and any(instant(c['start_at']).timestamp() < due and instant(c['end_at']).timestamp() > release for c in conflicts)
        if hard:
            reasons.append('fixed_conflict')
        overdue = due is not None and due <= current and remaining is not None and remaining > 0 and item.get('certainty') == 'formal'
        if overdue:
            reasons.append('overdue')
        inverted = can_count and release >= due and not overdue
        if inverted:
            reasons.append('start_after_deadline')
        proven_longest=CapacityIndex(subtract(context['known_free'].spans,other_spans)).longest(release,due) if can_count and occupancy_incomplete else longest
        no_slot = can_count and not item.get('splittable', True) and proven_longest < remaining
        if no_slot:
            reasons.append('no_contiguous_slot')
        row = {'item_id':item['id'], 'item_version':item.get('version', 1), 'title':item['title'],
               'remaining_minutes':remaining, 'release_at':iso(release) if policy != 'unconfirmed' else None,
               'deadline_at':iso(due) if due is not None else None, 'reason_codes':reasons,
               'capacity_before_fixed_minutes':before,
               'fixed_occupied_minutes':None if before is None else before-known_capacity,
               'uncertainty_excluded_minutes':None if known_capacity is None else known_capacity-calendar_capacity,
               'capacity_after_fixed_minutes':calendar_capacity, 'other_plan_minutes':None if calendar_capacity is None else calendar_capacity-capacity,
               'planned_minutes':own_coverage,'unplanned_minutes':max(0,remaining-own_coverage) if remaining is not None else None,
               'task_slack_minutes':slack, 'max_contiguous_minutes':longest,'capacity_is_upper_bound':unbounded,
               'window_gap_minutes':0, 'critical_window':None, 'data_complete':not missing,
               'level':'high' if overdue or hard or no_slot or inverted or plan_problem else 'unknown' if missing else
                       'medium' if tentative_exam or slack < max(30, .2*remaining) else 'low'}
        result.append(row)
        if can_count and due > current:
            ready.append((release, due, remaining, row))
    critical = None
    # Each [release, deadline] window gets one shared capacity; overlapping
    # deficits are never added together. This is a lower bound, not a solver.
    for a in sorted({begin, *(r[0] for r in ready)}):
        for b in sorted({r[1] for r in ready}):
            if b <= a:
                continue
            subset = [r for r in ready if r[0] >= a and r[1] <= b]
            demand = sum(r[2] for r in subset)
            other_seconds=occupied_seconds(valid_plans,a,b,{r[3]['item_id'] for r in subset})
            occupancy_incomplete=any(w['could_affect_occupancy'] and uncertainty_affects_window(w,a,b) for w in context['uncertainty_warnings'])
            # A conservative avoidance interval cannot prove an actual shortage.
            window_free=context['known_free'] if occupancy_incomplete else free
            capacity = max(0,floor((window_free.before(b)-window_free.before(a)-other_seconds)/60))
            gap = max(0, demand-capacity)
            if not gap:
                continue
            window = {'start_at':iso(a), 'end_at':iso(b), 'demand_minutes':demand, 'capacity_minutes':capacity,
                      'gap_minutes':gap, 'item_ids':[r[3]['item_id'] for r in subset],
                      'capacity_is_upper_bound':occupancy_incomplete,
                      'uses_uncertainty_exclusions':False}
            if critical is None or gap > critical['gap_minutes']:
                critical = window
            for _, _, _, row in subset:
                if gap > row['window_gap_minutes']:
                    row['window_gap_minutes'], row['critical_window'] = gap, window
                row['level'] = 'high'
                if 'window_overload' not in row['reason_codes']:
                    row['reason_codes'].append('window_overload')
    incomplete = sum(not r['data_complete'] for r in result)
    if incomplete:
        for row in result:
            if row['data_complete'] and row['level'] != 'high':
                row['level'] = 'unknown'
                row['reason_codes'].append('other_tasks_incomplete')
    uncertain_count = sum(a < semester_end and b > begin for a,b,_,_ in uncertain)
    level = 'high' if conflicts or plan_issues or any(r['level']=='high' for r in result) else 'unknown' if incomplete or not availability.get('configured') else 'medium' if uncertain_count or any(r['level']=='medium' for r in result) else 'low'
    return {'items':result, 'summary':{'level':level, 'active_task_count':len(tasks), 'incomplete_count':incomplete,
        'window_gap_minutes':critical['gap_minutes'] if critical else 0, 'critical_window':critical,
        'fixed_conflict_count':len(conflicts), 'configured':availability.get('configured', False),
        'uncertain_exam_count':sum(a < semester_end and b > begin and not id.startswith('event:') for a,b,_,id in uncertain),
        'uncertain_event_count':sum(a < semester_end and b > begin and id.startswith('event:') for a,b,_,id in uncertain),
        'plan_conflict_count':len(plan_issues),
        'analysis_limited':limit, 'is_schedule':False}, 'fixed_conflicts':conflicts[:30],
        'plan_issues':plan_issues[:30], 'scope_end':iso(semester_end), 'computed_at':now.astimezone(timezone.utc).isoformat(),
        'uncertainty_warnings':context['uncertainty_warnings'],
        'valid_until':(now+timedelta(minutes=1)).astimezone(timezone.utc).isoformat(), 'rule_version':'risk-v1', 'time_resolution_minutes':1}
