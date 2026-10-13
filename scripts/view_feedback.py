"""Read submitted feedback through the developer's SSH access and render a local list.

Run from the project directory: python scripts/view_feedback.py
Optional: --limit 100 --category reminder --no-open
Uses the existing keleoz-tencent SSH alias. No API keys or database passwords
are exported, and the remote query never modifies feedback or user records.
"""
import argparse
import base64
from datetime import datetime, timedelta, timezone
from html import escape
import json
from pathlib import Path
import subprocess
import sys
import webbrowser

ROOT = Path(__file__).resolve().parents[1]
CATEGORIES = {'wrong_answer': '理解错误', 'save': '保存问题', 'reminder': '提醒问题',
              'interface': '界面问题', 'other': '其他'}
REMOTE = '''import base64,json
from sqlalchemy import select,func
from sqlalchemy.orm import Session
from app.database import make_engine
from app.models import UserFeedback,User
p=json.loads(base64.b64decode("PARAMETERS"))
engine=make_engine()
try:
    with Session(engine) as db:
        conditions=[]
        if p['category']: conditions.append(UserFeedback.payload['category'].as_string()==p['category'])
        query=select(UserFeedback,User.username).join(User,User.id==UserFeedback.user_id).where(*conditions)
        total=db.scalar(select(func.count()).select_from(UserFeedback).where(*conditions))
        rows=[{'id':row.id,'username':username,'created_at':row.created_at,**row.payload}
            for row,username in db.execute(query.order_by(UserFeedback.created_at.desc(),UserFeedback.id.desc()).limit(p['limit']))]
    print(json.dumps({'total':total,'rows':rows},ensure_ascii=False))
finally: engine.dispose()
'''


def local_time(value):
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(
            timezone(timedelta(hours=8))).strftime('%Y-%m-%d %H:%M')
    except (ValueError, AttributeError):
        return str(value or '')


def render(data):
    def text(value): return escape(str(value or ''))
    cards = []
    for row in data['rows']:
        cards.append('''<article><div class="meta"><strong>{category}</strong><span>{time}</span></div>
<div class="account">用户：{user}　·　版本：{version}</div>
<h2>遇到的问题</h2><p>{description}</p>{expected}
<div class="id">反馈编号：{id}</div></article>'''.format(
            category=text(CATEGORIES.get(row.get('category'), '其他')),
            time=text(local_time(row.get('created_at'))), user=text(row.get('username')),
            version=text(row.get('app_version') or '未提供'), description=text(row.get('description')),
            expected='<h2>期望的处理</h2><p>'+text(row['expected'])+'</p>' if row.get('expected') else '',
            id=text(row.get('id'))))
    now = local_time(datetime.now(timezone.utc).isoformat())
    return '''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>拾日用户反馈</title>
<style>body{margin:0;background:#f2f6fc;color:#17283f;font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif}
main{max-width:860px;margin:40px auto;padding:0 24px}h1{font-size:28px;margin-bottom:4px}
.summary,.account,.id{color:#60718a}.summary{margin-bottom:24px}article{background:white;border:1px solid #dce5f1;border-radius:18px;padding:24px;margin:16px 0}
.meta{display:flex;gap:16px;justify-content:space-between;flex-wrap:wrap}.meta strong{color:#245fc6}h2{font-size:15px;margin:18px 0 4px}
p{margin:0;white-space:pre-wrap;overflow-wrap:anywhere}.id{font-size:12px;margin-top:20px;overflow-wrap:anywhere}
.empty{padding:40px 0}.note{font-size:14px;color:#60718a}</style><main>
<h1>拾日用户反馈</h1><div class="summary">共 {total} 条 · 本次显示最近 {shown} 条 · 更新于 {now}（北京时间）</div>
    {cards}<p class="note">这是本次读取的结果。重新运行查看工具可刷新；这里只包含用户主动提交的文字。</p></main></html>'''.replace(
        '{total}', str(int(data['total']))).replace('{shown}', str(len(data['rows']))).replace(
        '{now}', text(now)).replace('{cards}', ''.join(cards) or '<p class="empty">目前还没有收到用户反馈。</p>')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--limit', type=int, default=50)
    parser.add_argument('--category', choices=list(CATEGORIES))
    parser.add_argument('--no-open', action='store_true')
    args = parser.parse_args()
    if not 1 <= args.limit <= 200: parser.error('--limit must be 1..200')
    parameters = base64.b64encode(json.dumps({'limit': args.limit, 'category': args.category}).encode()).decode()
    try:
        response = subprocess.run(['ssh', '-o', 'BatchMode=yes', 'keleoz-tencent',
            'sudo', '-n', 'docker', 'exec', '-i', 'semesteros-cloud-api-1', 'python', '-'],
            input=REMOTE.replace('PARAMETERS', parameters).encode(), capture_output=True, timeout=45)
        if response.returncode: raise RuntimeError('SSH或服务端查询失败')
        data = json.loads(response.stdout.decode('utf-8'))
        destination = ROOT / 'output/feedback/latest.html'
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(render(data), encoding='utf-8')
    except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as exc:
        print('未能读取反馈，请检查服务器和本机SSH连接。原因：'+str(exc), file=sys.stderr)
        return 1
    print(json.dumps({'total': data['total'], 'shown': len(data['rows']), 'report': str(destination)}, ensure_ascii=False))
    if not args.no_open: webbrowser.open(destination.as_uri())
    return 0


if __name__ == '__main__': raise SystemExit(main())
