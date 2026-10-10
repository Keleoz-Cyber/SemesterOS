"""School timetable supplied by the user; applied with the course confirmation."""
HAUT_PERIODS = [
    {'number': n, 'start': start, 'end': end}
    for n, (start, end) in enumerate([
        ('08:30', '09:15'), ('09:20', '10:05'), ('10:25', '11:05'), ('11:10', '12:00'),
        ('14:30', '15:15'), ('15:20', '16:05'), ('16:25', '17:10'), ('17:15', '18:00'),
        ('19:30', '20:15'), ('20:20', '21:05'),
    ], 1)
]


def import_periods(source, existing):
    if source != 'haut_webview':
        return None
    # Keep explicitly configured additional periods, never invent their times.
    return [dict(p) for p in HAUT_PERIODS] + [dict(p) for p in existing if p['number'] > 10]
