"""Provider protocol adapter; only a bounded tool registry is exposed."""
import os
import httpx
from .auth import error


def model_turn(messages, tools):
    key=os.environ.get('DEEPSEEK_API_KEY')
    if not key:error(503,'MODEL_UNAVAILABLE','AI暂时不可用，可以继续手动记录和查看日程')
    body={'model':os.environ.get('DEEPSEEK_MODEL','deepseek-flash'), 'thinking':{'type':'disabled'},
          'messages':messages,'tools':tools,'temperature':0,'max_tokens':2400}
    try:
        with httpx.Client(timeout=httpx.Timeout(25,connect=8)) as client:
            response=client.post(os.environ.get('DEEPSEEK_BASE_URL','https://api.deepseek.com').rstrip('/')+'/chat/completions',
                                 headers={'Authorization':'Bearer '+key},json=body)
        if response.status_code!=200:error(503,'MODEL_UNAVAILABLE','AI暂时没有响应，请稍后重新发送')
        data=response.json()
        choice=data['choices'][0]
        if choice.get('finish_reason')=='length':error(502,'MODEL_OUTPUT_LIMIT','这次内容较多，请分成两次处理')
        return {**choice['message'], '_usage': data.get('usage', {})}
    except httpx.HTTPError:error(503,'MODEL_UNAVAILABLE','连接AI超时，内容已保留，可以稍后重新发送')
    except (KeyError,ValueError,TypeError,IndexError):error(502,'INVALID_MODEL_OUTPUT','AI返回的内容不完整，请重新发送')
