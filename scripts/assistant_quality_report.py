"""Report measured assistant processing results, without exporting message content."""
import argparse
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/api'))


def report(engine, days=7):
    from sqlalchemy import select
    from sqlalchemy.orm import Session
    from app.models import AgentRun
    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    with Session(engine) as db:
        values = list(db.execute(select(AgentRun.status, AgentRun.state).where(AgentRun.created_at >= since)).all())
    durations = sorted(s['metrics']['worker_ms'] for _,s in values if isinstance(s.get('metrics', {}).get('worker_ms'), (int,float)))
    def percentile(p): return durations[round((len(durations)-1)*p)] if durations else None
    return {'days': days, 'runs': len(values), 'failed': sum(status == 'failed' for status,_ in values),
        'saved': sum(status == 'applied' for status,_ in values),
        'measured_runs': len(durations), 'worker_p50_ms': percentile(.5), 'worker_p95_ms': percentile(.95),
        'runs_with_repairs': sum(s.get('repairs',0) > 0 for _,s in values),
        'note': '服务端处理耗时，不包含排队和手机网络；没有采集的历史耗时留空。失败率不等于理解准确率。'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--days', type=int, default=7)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 1 <= args.days <= 366: parser.error('days must be 1..366')
    from app.database import make_engine
    engine = make_engine()
    try: result = report(engine, args.days)
    finally: engine.dispose()
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    else: print(text)
