"""Temporary emulator-only InputConnection helper, never a product dependency."""
from pathlib import Path
import subprocess
import zipfile
import os

source=Path(__file__).resolve().parent/'ime'
project=next((parent for parent in Path(__file__).resolve().parents
    if (parent/'services/api/app').is_dir() and (parent/'apps/mobile/lib').is_dir()),None)
assert project is not None,'Place this helper inside a SemesterOS checkout'
root=project/'tmp/aic_validation/ime_build'
root.mkdir(parents=True,exist_ok=True)
sdk=Path(os.environ.get('ANDROID_HOME',str(Path(os.environ['LOCALAPPDATA'])/'Android/Sdk')))
tools=sdk/'build-tools/36.1.0'
jdk=Path(os.environ.get('JAVA_HOME','C:/Program Files/Microsoft/jdk-21.0.4.7-hotspot'))
jar=sdk/'platforms/android-36/android.jar'
assert jar.is_file(), 'Android API reference JAR missing'
classes=root/'classes';dex=root/'dex'
classes.mkdir(exist_ok=True);dex.mkdir(exist_ok=True)
def run(args,stdin=None):
    p=subprocess.run([str(a) for a in args],input=stdin,capture_output=True,text=True)
    assert p.returncode==0,p.stderr[-1000:]
run([jdk/'bin/javac.exe','-source','8','-target','8','-classpath',jar,'-d',classes,source/'src/InputService.java'])
run([jdk/'bin/java.exe','-cp',tools/'lib/d8.jar','com.android.tools.r8.D8','--min-api','33','--output',dex,*classes.rglob('*.class')])
unsigned=root/'unsigned.apk';signed=root/'input.apk'
run([tools/'aapt.exe','package','-f','-M',source/'AndroidManifest.xml','-S',source/'res','-I',jar,'-F',unsigned])
with zipfile.ZipFile(unsigned,'a') as apk:apk.write(dex/'classes.dex','classes.dex')
run([jdk/'bin/java.exe','-jar',tools/'lib/apksigner.jar','sign','--ks',Path.home()/'.android/debug.keystore','--ks-key-alias','androiddebugkey','--ks-pass','stdin','--key-pass','stdin','--out',signed,unsigned],stdin='android\nandroid\n')
print('Emulator-only Unicode input helper built')
