"""Local calendar context for providers; stored timestamps stay unchanged."""
from copy import deepcopy
from datetime import datetime
import json
from .reminder_rules import SHANGHAI

MODEL_TIME_RULE='日期和星期统一按Asia/Shanghai解释。today_local是对应reference_at的上海本地日期；“明天”是该本地日期的次日，不能使用UTC字符串的日期部分。通知原文明确的原始发布日期仍优先。'


def model_reference(value):
    at=value if isinstance(value,datetime) else datetime.fromisoformat(value.replace('Z','+00:00'))
    if at.tzinfo is None:raise ValueError('Model reference requires timezone')
    local=at.astimezone(SHANGHAI)
    return {'reference_at':local.isoformat(),'today_local':str(local.date()),'timezone':'Asia/Shanghai'}


def localize_reference_data(value):
    if isinstance(value,list):return [localize_reference_data(part) for part in value]
    if not isinstance(value,dict):return value
    result={key:localize_reference_data(part) for key,part in value.items()}
    if isinstance(value.get('reference_at'),str):
        try:result.update(model_reference(value['reference_at']))
        except (ValueError,TypeError):pass
    # Conversation wrappers can contain a previous JSON request as a string.
    # Only that wrapper is decoded; raw source/text/notes stay byte-for-byte text.
    if isinstance(value.get('request'),str):
        try:
            request=json.loads(value['request'])
            if isinstance(request,dict):result['request']=json.dumps(localize_reference_data(request),ensure_ascii=False)
        except (ValueError,TypeError):pass
    return result


def model_messages(messages):
    result=deepcopy(messages)
    for message in result:
        content=message.get('content')
        if not isinstance(content,str):continue
        try:
            data=json.loads(content)
            if isinstance(data,(dict,list)):message['content']=json.dumps(localize_reference_data(data),ensure_ascii=False)
        except (ValueError,TypeError):pass
    first=next((message for message in result if message.get('role')=='system'),None)
    if first is not None and MODEL_TIME_RULE not in (first.get('content') or ''):
        first['content']=(first.get('content') or '')+'\n'+MODEL_TIME_RULE
    return result
