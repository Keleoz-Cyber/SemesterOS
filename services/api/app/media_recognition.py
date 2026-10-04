from functools import lru_cache
from pathlib import Path
import os,re,time,wave
import numpy as np
from .runtime_paths import PROJECT_ROOT


@lru_cache(maxsize=1)
def ocr_engine():
    from rapidocr import RapidOCR
    params={'EngineConfig.onnxruntime.intra_op_num_threads':2,'EngineConfig.onnxruntime.inter_op_num_threads':1}
    folder=os.environ.get('RAPIDOCR_MODEL_DIR')
    if folder:params['Global.model_root_dir']=folder
    return RapidOCR(params=params)


@lru_cache(maxsize=1)
def asr_engine():
    import sherpa_onnx
    folder=Path(os.environ.get('SENSEVOICE_MODEL_DIR',PROJECT_ROOT/'.local-data/models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17'))
    if not (folder/'model.int8.onnx').exists() or not (folder/'tokens.txt').exists():raise FileNotFoundError('ASR_MODEL_MISSING')
    return sherpa_onnx.OfflineRecognizer.from_sense_voice(model=str(folder/'model.int8.onnx'),tokens=str(folder/'tokens.txt'),
        num_threads=2,language='auto',use_itn=True,debug=False,provider='cpu')


def recognize(path,kind,on_progress=None):
    if kind=='image' and Path(path).suffix=='.zip':
        from zipfile import ZipFile
        from tempfile import TemporaryDirectory
        pages=[];combined=[]
        with ZipFile(path) as archive,TemporaryDirectory(prefix='semester-notice-') as folder:
            names=archive.namelist()
            if not names:raise ValueError('Empty image group')
            for index,name in enumerate(names):
                if not re.fullmatch(r'image-[1-9]\d*\.png',name):raise ValueError('Invalid image group entry')
                if on_progress and on_progress(f'正在识别第{index+1}/{len(names)}张图片') is False:raise RuntimeError('Recognition stopped')
                target=Path(folder)/name;target.write_bytes(archive.read(name))
                page=recognize(target,'image');pages.append(page)
                lines=[line.strip() for line in page['text'].splitlines() if line.strip()]
                # Consecutive screenshots often overlap. Remove only an exact
                # tail/prefix overlap; other repeated lines keep their context.
                overlap=0
                for count in range(1,min(len(combined),len(lines))+1):
                    if combined[-count:]==lines[:count]:overlap=count
                combined.extend(lines[overlap:])
        return {'text':'\n'.join(combined),'metadata':{'provider':'RapidOCR','same_notice':True,
            'image_count':len(pages),'pages':pages,'stage':'图片识别完成'}}
    if on_progress and on_progress('正在识别图片' if kind=='image' else '正在转写录音') is False:raise RuntimeError('Recognition stopped')
    started=time.monotonic()
    if kind=='image':
        import importlib.metadata
        result=ocr_engine()(str(path))
        lines=list(result.txts) if result.txts is not None else []
        scores=list(result.scores) if result.scores is not None else []
        return {'text':'\n'.join(lines),'metadata':{'provider':'RapidOCR','version':importlib.metadata.version('rapidocr'),
            'elapsed_ms':round((time.monotonic()-started)*1000),'lines':[{'text':t,'score':float(s)} for t,s in zip(lines,scores)]}}
    import sherpa_onnx
    with wave.open(str(path),'rb') as f:samples=np.frombuffer(f.readframes(f.getnframes()),dtype=np.int16).astype(np.float32)/32768
    if samples.size==0 or np.max(np.abs(samples))<0.001:return {'text':'','metadata':{'provider':'SenseVoice'}}
    engine=asr_engine();stream=engine.create_stream();stream.accept_waveform(16000,samples);engine.decode_stream(stream)
    text=re.sub(r'<\|[^>]*\|>','',stream.result.text).strip()
    return {'text':text,'metadata':{'provider':'SenseVoice','model':'sense-voice-int8-2024-07-17','runtime_version':sherpa_onnx.__version__,
        'elapsed_ms':round((time.monotonic()-started)*1000)}}
