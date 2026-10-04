"""Local-only backend for real Android workflow tests, with real AI."""
import argparse
from contextlib import asynccontextmanager
import os
from pathlib import Path
import sys
from threading import Event, Thread

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/api'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', required=True)
    parser.add_argument('--port', type=int, default=8874)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error('--port must be between 1024 and 65535')
    out = Path(args.data_dir).resolve()
    assert out.is_relative_to(ROOT / 'output/verification'), 'QA data must stay in verification output'
    out.mkdir(parents=True, exist_ok=True)
    from dotenv import dotenv_values
    for key, value in dotenv_values(ROOT / '.env').items():
        if key in ('DEEPSEEK_API_KEY', 'DEEPSEEK_MODEL', 'DEEPSEEK_BASE_URL') and value:
            os.environ[key] = value
    import json
    (out / 'config-readiness.json').write_text(json.dumps({
        'model_key_ready': bool(os.environ.get('DEEPSEEK_API_KEY')),
        'model_mode': 'real DeepSeek configuration; not stubbed',
        'port': args.port,
    }), encoding='utf-8')
    os.environ['MEDIA_ROOT'] = str(out / 'media')
    os.environ['MEDIA_WORKER_MODE'] = 'external'
    from app.main import create_app
    from app.agent_runtime import work_once
    import uvicorn
    app = create_app('sqlite:///' + str(out / 'qa.sqlite'), initialize=True)
    original = app.router.lifespan_context
    stop = Event()
    def worker():
        while not stop.is_set():
            try: active = work_once(app.state.engine)
            except Exception: active = False
            if not active: stop.wait(.15)
    @asynccontextmanager
    async def lifespan(application):
        async with original(application):
            thread = Thread(target=worker, daemon=True)
            thread.start()
            try: yield
            finally: stop.set(); thread.join(timeout=3)
    app.router.lifespan_context = lifespan
    (out / 'server.pid').write_text(str(os.getpid()), encoding='ascii')
    uvicorn.run(app, host='127.0.0.1', port=args.port, log_level='warning', access_log=False)


if __name__ == '__main__': main()
