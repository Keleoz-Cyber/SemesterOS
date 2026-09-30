"""Opt-in localhost-only backend for an isolated Android QA application.

Run with --directory pointing to a new local QA data folder. No production DB
is touched. Test credentials are supplied by the device smoke runner, not logged.
"""
import argparse
import os
import sys
import threading
import time
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/api'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', required=True)
    parser.add_argument('--port', type=int, default=8872)
    args = parser.parse_args()
    directory = Path(args.directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    from dotenv import dotenv_values
    for key, value in dotenv_values(ROOT / '.env').items():
        if key in {'DEEPSEEK_API_KEY', 'DEEPSEEK_MODEL', 'DEEPSEEK_BASE_URL', 'SENSEVOICE_MODEL_DIR'} and value:
            os.environ[key] = value
    os.environ['MEDIA_ROOT'] = str(directory / 'media')
    from app.main import create_app
    from app.agent_runtime import work_once
    from app.media_jobs import claim, publish
    from app.media_recognition import recognize
    from app.media_files import path_for
    app = create_app('sqlite:///' + str(directory / 'qa.sqlite'), initialize=True)
    # Local QA observability: paths and completion times only, never bodies,
    # query strings, credentials or production traffic.
    requests = deque(maxlen=100)
    @app.middleware('http')
    async def observe_request(request, call_next):
        response = await call_next(request)
        if request.url.path.startswith('/api/v1/'):
            requests.append({'method': request.method, 'path': request.url.path,
                             'completed_at': time.time(), 'status': response.status_code})
        return response
    @app.get('/qa/requests')
    def request_log():
        return list(requests)
    stop = threading.Event()
    def worker():
        while not stop.is_set():
            try:
                worked = work_once(app.state.engine)
                job = claim(app.state.engine)
                if job:
                    try:
                        publish(app.state.engine, job, recognize(path_for(app.state.media_root, job['storage_key']), job['kind']))
                    except Exception:
                        publish(app.state.engine, job, error='RECOGNITION_FAILED')
                if not worked and not job: stop.wait(.5)
            except Exception:
                stop.wait(1)
    thread = threading.Thread(target=worker, daemon=True)
    thread.start()
    import uvicorn
    try:
        uvicorn.run(app, host='127.0.0.1', port=args.port, access_log=False)
    finally:
        stop.set(); thread.join(timeout=3)


if __name__ == '__main__':
    main()
