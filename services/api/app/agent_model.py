"""Provider protocol adapter; only a bounded tool registry is exposed."""
import os
import json
import httpx
from .auth import error
from .model_context import model_messages


def model_turn(messages, tools, on_delta=None):
    key=os.environ.get('DEEPSEEK_API_KEY')
    if not key:error(503,'MODEL_UNAVAILABLE','AI暂时不可用，可以继续手动记录和查看日程')
    body={'model':os.environ.get('DEEPSEEK_MODEL','deepseek-flash'), 'thinking':{'type':'disabled'},
          'messages':model_messages(messages),'tools':tools,'temperature':0,'max_tokens':2400,
          'stream':True,'stream_options':{'include_usage':True}}
    try:
        with httpx.Client(timeout=httpx.Timeout(25,connect=8)) as client:
            with client.stream('POST',os.environ.get('DEEPSEEK_BASE_URL','https://api.deepseek.com').rstrip('/')+'/chat/completions',
                               headers={'Authorization':'Bearer '+key},json=body) as response:
                if response.status_code!=200:error(503,'MODEL_UNAVAILABLE','AI暂时没有响应，请稍后重新发送')
                content=[];calls={};usage={};finished=False
                for line in response.iter_lines():
                    if not line.startswith('data:'):continue
                    payload=line[5:].strip()
                    if payload=='[DONE]':break
                    data=json.loads(payload)
                    if data.get('usage'):usage=data['usage']
                    for choice in data.get('choices',[]):
                        if choice.get('finish_reason')=='length':error(502,'MODEL_OUTPUT_LIMIT','这次内容较多，请分成两次处理')
                        if choice.get('finish_reason'):finished=True
                        delta=choice.get('delta') or {}
                        part=delta.get('content') or ''
                        if part:
                            content.append(part)
                            if sum(map(len,content))>16000:raise ValueError('Reply too long')
                            if on_delta:on_delta(part)
                        for fragment in delta.get('tool_calls') or []:
                            index=fragment['index']
                            current=calls.setdefault(index,{'id':'','type':'function','function':{'name':'','arguments':''}})
                            if fragment.get('id'):current['id']=fragment['id']
                            function=fragment.get('function') or {}
                            for field in ('name','arguments'):
                                current['function'][field]+=function.get(field) or ''
                            if len(calls)>12 or len(current['function']['arguments'])>20000:raise ValueError('Tool output too long')
                if not finished:raise ValueError('Interrupted stream')
        return {'role':'assistant','content':''.join(content) or None,
                **({'tool_calls':[calls[i] for i in sorted(calls)]} if calls else {}),'_usage':usage}
    except httpx.HTTPError:error(503,'MODEL_UNAVAILABLE','连接AI超时，内容已保留，可以稍后重新发送')
    except (KeyError,ValueError,TypeError,IndexError):error(502,'INVALID_MODEL_OUTPUT','AI返回的内容不完整，请重新发送')
