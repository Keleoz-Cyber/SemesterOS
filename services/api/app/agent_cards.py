"""Read-only, bounded snapshots for lazy cards. No confirmation authority."""
from copy import deepcopy
from .models import new_id

COLLECTIONS = {
    'calendar': ('entries', 'undated'),
    'records': ('records',),
    'course_occurrences': ('occurrences',),
    'windows': ('windows',),
    'insights': ('records', 'undated'),
    'recent_actions': ('actions',),
    'planning_result': ('tasks', 'blocks'),
}
CACHE_LIMIT = 200


def page(cache, offset, limit):
    fields = cache['collections']; full = cache['data']
    data = deepcopy({k:v for k,v in full.items() if k not in fields})
    data.update({key:[] for key in fields})
    position = 0; used = 0
    for key in fields:
        rows = full.get(key, [])
        begin = max(0, offset - position)
        end = max(0, min(len(rows), offset + limit - position))
        if begin < end:
            data[key] = deepcopy(rows[begin:end]); used += end - begin
        position += len(rows)
    more = offset + used < cache['cached_count']
    value = {'card_id':cache['card_id'], 'kind':cache['kind'],
             'total_count':cache['total_count'], 'data':data}
    return {'card':value, 'has_more':more, 'next_offset':offset + used if more else None}


def append_card(state, kind, data):
    fields = COLLECTIONS.get(kind, ())
    complete_count = sum(len(data.get(key, [])) for key in fields)
    total = data.get('total_count', data.get('records_total', complete_count))
    if not fields and isinstance(data.get('counts'), dict): total = sum(data['counts'].values())
    cached = {k:deepcopy(v) for k,v in data.items() if k not in fields}
    remaining = CACHE_LIMIT
    for key in fields:
        cached[key] = deepcopy(data.get(key, [])[:remaining]); remaining -= len(cached[key])
    cached_count = CACHE_LIMIT - remaining
    if complete_count > CACHE_LIMIT: cached['truncated'] = True
    cached.update(total_count=total, cached_count=cached_count)
    card_id = new_id()
    cache = {'card_id':card_id, 'kind':kind, 'total_count':total, 'data':cached,
             'collections':list(fields), 'cached_count':cached_count}
    state['card_pages'] = {**state.get('card_pages', {}), card_id:cache}
    first = page(cache, 0, 5)
    value = {**first['card'], 'has_more':first['has_more'], 'next_offset':first['next_offset']}
    state['cards'].append(value)
    return value
