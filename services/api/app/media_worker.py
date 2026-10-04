"""Independent durable queue worker. API restart cannot lose queued sources."""
import os,time
from .database import make_engine
from .media_files import root,path_for
from .media_jobs import claim,publish,progress
from .media_recognition import recognize


def parent_alive():
    parent=int(os.environ.get('MEDIA_PARENT_PID','0'))
    if not parent:return True
    if os.name!='nt':return os.getppid()==parent
    import ctypes
    from ctypes import wintypes
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];kernel.OpenProcess.restype=wintypes.HANDLE
    kernel.GetExitCodeProcess.argtypes=[wintypes.HANDLE,ctypes.POINTER(wintypes.DWORD)]
    kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    handle=kernel.OpenProcess(0x1000,False,parent)
    if not handle:return False
    try:
        code=wintypes.DWORD();return bool(kernel.GetExitCodeProcess(handle,ctypes.byref(code))) and code.value==259
    finally:kernel.CloseHandle(handle)


def main():
    engine=make_engine()
    try:
        while parent_alive():
            # Agent state lives in the same durable DB queue; no API request waits
            # on model I/O. Alternate with media jobs so neither queue is starved.
            from .agent_runtime import work_once
            try: agent_work = work_once(engine)
            except Exception: agent_work = False
            try:job=claim(engine)
            except Exception:time.sleep(2);continue
            if job is None:
                if not agent_work:time.sleep(.5)
                continue
            try:publish(engine,job,recognize(path_for(root(),job['storage_key']),job['kind'],
                on_progress=lambda message:progress(engine,job,message)))
            except FileNotFoundError:publish(engine,job,error='MODEL_OR_FILE_MISSING')
            except Exception:publish(engine,job,error='RECOGNITION_FAILED')
    finally:engine.dispose()


if __name__=='__main__':main()
