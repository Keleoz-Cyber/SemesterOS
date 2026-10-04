from math import floor
from .reminder_rules import instant, anchor_at
from .task_readiness import start_policy


def future_minutes(block, now, start=None, end=None):
    a=max(instant(block['start_at']).timestamp(),now,start if start is not None else now)
    b=min(instant(block['end_at']).timestamp(),end if end is not None else float('inf'))
    return max(0,floor((b-a)/60))


def classify(plans, items, free_spans, now):
    tasks={i['id']:i for i in items}
    future=[b for b in plans if b['status']=='active' and instant(b['end_at']).timestamp()>now]
    valid,issues=[],[]
    for b in future:
        item=tasks.get(b['item_id']);reasons=[]
        start,end=instant(b['start_at']).timestamp(),instant(b['end_at']).timestamp()
        tail=max(start,now)
        if not item or item['kind']=='exam' or item['lifecycle']!='active':reasons.append('inactive_task')
        if end<=start or b['minutes']*60!=end-start:reasons.append('invalid_duration')
        if not any(a<=tail and end<=z for a,z in free_spans):reasons.append('outside_free_time')
        if item:
            if not item.get('splittable',True) and sum(o['item_id']==b['item_id'] for o in future)>1:reasons.append('unsplittable_multiple_blocks')
            if item.get('remaining_minutes') is None:reasons.append('needs_estimate')
            if start_policy(item)=='unconfirmed':reasons.append('needs_start')
            if item.get('start_policy')=='at' and item.get('earliest_start_at') and tail<instant(item['earliest_start_at']).timestamp():reasons.append('before_release')
            due=anchor_at(item) if item.get('certainty')=='formal' else None
            if due and end>due.timestamp():reasons.append('after_deadline')
        if any(o['id']!=b['id'] and instant(o['start_at']).timestamp()<end and start<instant(o['end_at']).timestamp() for o in future):reasons.append('plan_overlap')
        if reasons:issues.append({'block_id':b['id'],'item_id':b['item_id'],'reason_codes':reasons})
        else:valid.append(b)
    return valid,issues


def occupied_seconds(plans, start, end, excluded_items=()):
    # classify() excludes mutual overlaps; valid spans are disjoint and contained
    # in calendar free time, so their intersections can be summed exactly once.
    return sum(max(0,min(end,instant(b['end_at']).timestamp())-max(start,instant(b['start_at']).timestamp()))
               for b in plans if b['item_id'] not in excluded_items)
