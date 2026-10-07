"""One useful match between a real study gap and known unfinished work."""
from math import ceil, floor
from .capacity import subtract, merge, iso, local_day, uncertainty_affects_window
from .plan_rules import classify, future_minutes
from .reminder_rules import anchor_at, instant
from .task_readiness import start_policy


def study_opportunity(source, context, now, day_start, day_end, entries):
    if not source[1].get('configured'): return None
    valid, issues = classify(source[4], source[3], context['free'].spans, context['begin'])
    if issues: return None  # Existing broken plans need a real decision first.
    occupied = merge([(instant(p['start_at']).timestamp(), instant(p['end_at']).timestamp())
                      for p in source[4] if p['status'] == 'active'])
    gaps = subtract(context['free'].spans, occupied)
    matches = []
    for a, b in gaps:
        start = ceil(max(a, now.timestamp(), day_start) / 60) * 60
        end = floor(min(b, day_end) / 60) * 60
        if end <= start: continue
        for item in source[3]:
            if item['kind'] not in ('task', 'assignment') or item['lifecycle'] != 'active': continue
            remaining = item.get('remaining_minutes')
            policy = start_policy(item)
            if remaining is None or policy == 'unconfirmed': continue
            release = max(start, ceil(instant(item['earliest_start_at']).timestamp()/60)*60) if policy == 'at' else start
            booked = sum(future_minutes(p, now.timestamp()) for p in valid if p['item_id'] == item['id'])
            needed = remaining - booked
            due = anchor_at(item) if item.get('certainty') == 'formal' else None
            limit = min(end, due.timestamp()) if due else end
            time=item.get('time') or {}
            if time.get('meaning') in ('candidate','course_anchor'):continue
            if time.get('meaning')=='window':
                if time.get('at'):release=max(release,instant(time['at']).timestamp())
                if time.get('end_at'):limit=min(limit,instant(time['end_at']).timestamp())
                if time.get('date') and day_start<local_day(time['date']).timestamp():continue
                if time.get('date') and day_start>local_day(time.get('end_date') or time['date']).timestamp():continue
            if needed <= 0 or release + needed * 60 > limit: continue
            if not item.get('splittable', True) and booked: continue
            next_fixed = next((e for e in entries if e.get('fixed') and e.get('start_at') and
                               instant(e.get('occupancy_start_at') or e['start_at']).timestamp() >= limit and
                               instant(e.get('occupancy_start_at') or e['start_at']).timestamp()-limit <= 5*60), None)
            rank=due.timestamp() if due else local_day(time['date']).timestamp() if time.get('date') and time.get('meaning')!='window' else float('inf')
            matches.append((release, rank,
                {'high':0,'normal':1,'low':2}.get(item.get('priority'),1), needed, item['id'], {
                'item_id':item['id'],'item_version':item['version'],'title':item['title'],
                'target_minutes':needed,'remaining_minutes':remaining,'already_planned_minutes':booked,
                'start_at':iso(release),'end_at':iso(limit),'gap_minutes':floor((limit-release)/60),
                'latest_start_at':iso(limit-needed*60),
                'before_kind':next_fixed['resource_type'] if next_fixed else None,
                'needs_check':(time.get('meaning')=='window' and not(time.get('at') and time.get('end_at'))) or
                    any(w['could_affect_occupancy'] and uncertainty_affects_window(w,release,limit)
                        for w in context['uncertainty_warnings']),
            }))
    return min(matches, key=lambda m:m[:5])[-1] if matches else None
