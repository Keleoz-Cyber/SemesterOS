"""Ordinary personal tasks are available now; stated dependencies remain real."""
import re


def start_policy(item):
    policy=item.get('start_policy','unconfirmed')
    if policy!='unconfirmed':return policy
    if item.get('earliest_start_at'):return 'at'
    details=item.get('details') or {}
    text='。'.join([*(str(item.get(k) or '') for k in ('title','notes','source_text')),
        *(str(condition) for condition in details.get('conditions') or [])])
    if re.search(r'等待(?:资料|材料|审批|批准|审核|确认|通知|回复|结果|数据)|等(?:待)?[^。\n]{0,30}(?:后|通知|确认|批准|结果)|待[^。\n]{0,20}(?:后|确认|批准)|收到[^。\n]{0,20}后|(?:开始时间|何时开始)(?:待定|未定)|还不能开始|暂不能开始|(?:下课|考完|结束|审批|批准|确认)[^。\n]{0,8}后(?:再|才能|开始)',text):
        return 'unconfirmed'
    return 'now'
