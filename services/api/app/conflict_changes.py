"""Only newly introduced overlaps require another acknowledgement."""
from .reminder_rules import instant


def is_blocking_conflict(conflict):
    """Unknown comparison windows are never attendance or consent targets."""
    if 'blocking' in conflict:
        return conflict['blocking'] is True
    return (conflict.get('certainty', 'confirmed') == 'confirmed'
            or conflict.get('overlap_at_start') is True
            or conflict.get('overlap_at_arrival') is True
            or conflict.get('evidence_kind') in ('start_point', 'arrival_interval', 'interval_overlap'))


def introduced_conflicts(before, after):
    def same_pair(a, b):
        return set(a['item_ids']) == set(b['item_ids'])
    before = [c for c in before if is_blocking_conflict(c)]
    return [c for c in after if is_blocking_conflict(c) and not any(same_pair(c, old)
        and (old.get('certainty', 'confirmed') == c.get('certainty', 'confirmed')
             or old.get('certainty', 'confirmed') == 'confirmed')
        and instant(old['start_at']) <= instant(c['start_at'])
        and instant(old['end_at']) >= instant(c['end_at']) for old in before)]


def introduced_time_warnings(before, after):
    def key(warning):
        return (frozenset(warning.get('item_ids', [])),
                tuple(warning.get('uncertainty_reasons', [])),
                warning.get('event_start_at'), warning.get('start_at'), warning.get('end_at'))
    existing = {key(w) for w in before}
    return [w for w in after if not is_blocking_conflict(w) and key(w) not in existing]
