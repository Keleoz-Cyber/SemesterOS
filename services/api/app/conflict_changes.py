"""Only newly introduced overlaps require another acknowledgement."""
from .reminder_rules import instant


def introduced_conflicts(before, after):
    def same_pair(a, b):
        return set(a['item_ids']) == set(b['item_ids'])
    return [c for c in after if not any(same_pair(c, old)
        and (old.get('certainty', 'confirmed') == c.get('certainty', 'confirmed')
             or old.get('certainty', 'confirmed') == 'confirmed')
        and instant(old['start_at']) <= instant(c['start_at'])
        and instant(old['end_at']) >= instant(c['end_at']) for old in before)]
