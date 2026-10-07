"""Personal attendance for one occurrence, independent of the school timetable."""


def course_requires_attendance(occurrence):
    return not occurrence.get('attendance_exempt') and occurrence.get('attendance_status') != 'leave'


def course_attendance_label(occurrence):
    if occurrence.get('attendance_status') == 'leave':
        return '已请假'
    if occurrence.get('attendance_status') == 'plan_leave':
        return '待请假'
    return '免听' if occurrence.get('attendance_exempt') else ''
