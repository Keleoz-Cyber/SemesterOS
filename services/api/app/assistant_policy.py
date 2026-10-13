"""Cross-scenario correction rules; concrete date/time checks live in domain code."""
import re

CORRECTION_POLICY = '''用户质疑已有记录、时间、地点、日期或保存状态时，先核对当前记录或预览及其依据，再解释。
不能把自己上一次回答当作核对证据。发现错误直接说明改了哪个字段，其余信息保留；原记录正确时简要解释依据，不使用“没有记错”等防御措辞。
只有一个必要缺项会改变操作对象时才询问。时间不完整可以记录；只有开始时刻不补结束，不把一次请假扩展成整天。
课程节点按学期节次解析，所有写入由预览确认完成；说明、查询和纠正问句本身不等于确认保存。'''


def needs_fact_check(text, has_context, input_kind):
    return bool(input_kind == 'message' and has_context and re.search(
        r'不是|不应该|不对|错了|记错|写错|确定吗|保存了吗|存了吗|为什么.*(?:时间|日期|地点|节|课|保存)', text))


FACT_TOOLS = {'resolve_class_time', 'query_calendar', 'find_records', 'query_course_occurrences',
              'list_recent_actions', 'find_free_windows', 'analyze_schedule'}
