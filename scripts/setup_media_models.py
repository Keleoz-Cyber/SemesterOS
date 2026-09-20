"""Download the documented SenseVoice int8 release; never execute archive contents."""
from pathlib import Path
import hashlib,json,tarfile,urllib.request,shutil

ROOT=Path(__file__).resolve().parents[1]/'.local-data/models'
NAME='sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17'
URL='https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'+NAME+'.tar.bz2'
EXPECTED='c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51'


def main():
    ROOT.mkdir(parents=True,exist_ok=True);archive=ROOT/(NAME+'.tar.bz2');folder=ROOT/NAME
    if not (folder/'model.int8.onnx').exists() or hashlib.sha256((folder/'model.int8.onnx').read_bytes()).hexdigest()!=EXPECTED:
        if not archive.exists():
            temporary=archive.with_suffix('.download')
            with urllib.request.urlopen(URL,timeout=30) as response,temporary.open('wb') as out:shutil.copyfileobj(response,out)
            temporary.replace(archive)
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                target=(ROOT/member.name).resolve()
                if not target.is_relative_to(ROOT.resolve()) or not (member.isfile() or member.isdir()):raise ValueError('Unexpected archive member')
            bundle.extractall(ROOT,filter='data')
    digest=hashlib.sha256((folder/'model.int8.onnx').read_bytes()).hexdigest()
    if digest!=EXPECTED or not (folder/'tokens.txt').exists():raise ValueError('Model integrity check failed')
    (ROOT/'sensevoice-manifest.json').write_text(json.dumps({'url':URL,'model_sha256':digest,'model_directory':NAME},indent=2),encoding='utf-8')
    print(json.dumps({'ready':True,'model_directory':str(folder),'model_sha256':digest}))


if __name__=='__main__':main()
