from io import BytesIO
from pathlib import Path
import os,wave
from PIL import Image,ImageOps,UnidentifiedImageError
from .auth import error
from .runtime_paths import PROJECT_ROOT

DEFAULT_ROOT=PROJECT_ROOT/'.local-data/media'


def root():return Path(os.environ.get('MEDIA_ROOT',DEFAULT_ROOT)).resolve()


def path_for(folder,key):
    base=Path(folder).resolve();path=(base/key).resolve()
    if not path.is_relative_to(base) or path.parent!=base:raise ValueError('Invalid storage key')
    return path


def sanitize(data,kind):
    if kind=='image':
        if len(data)>10*1024*1024:error(413,'MEDIA_TOO_LARGE','图片最多10MB，请先裁剪需要识别的通知')
        try:
            image=Image.open(BytesIO(data))
            if image.format not in ('JPEG','PNG','WEBP') or image.width*image.height>20_000_000 or getattr(image,'n_frames',1)!=1:raise ValueError()
            image=ImageOps.exif_transpose(image).convert('RGB')
            clean=Image.new('RGB',image.size);clean.paste(image);out=BytesIO();clean.save(out,format='PNG')
            if out.tell()>30*1024*1024:raise ValueError()
            return out.getvalue(),'image/png','.png',{'width':clean.width,'height':clean.height,'metadata_removed':True}
        except (OSError,ValueError,UnidentifiedImageError,Image.DecompressionBombError):error(422,'INVALID_MEDIA','请使用单张JPEG/PNG/WebP图片，最多2000万像素')
    if len(data)>20*1024*1024:error(413,'MEDIA_TOO_LARGE','录音最多20MB')
    try:
        with wave.open(BytesIO(data),'rb') as w:
            if w.getnchannels()!=1 or w.getsampwidth()!=2 or w.getframerate()!=16000 or w.getcomptype()!='NONE':raise ValueError()
            count=w.getnframes();duration=count/16000
            if not 0<duration<=120:raise ValueError()
            frames=w.readframes(count)
            if len(frames)!=count*2:raise ValueError()
        out=BytesIO()
        with wave.open(out,'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000);w.writeframes(frames)
        return out.getvalue(),'audio/wav','.wav',{'duration_seconds':duration,'sample_rate':16000}
    except (OSError,EOFError,wave.Error,ValueError):error(422,'INVALID_MEDIA','请使用App录制的16kHz单声道WAV，时长不超过120秒')
