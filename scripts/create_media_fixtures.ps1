$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sampleDirectory = Join-Path $projectRoot 'output/verification/media'
New-Item -ItemType Directory -Path $sampleDirectory -Force | Out-Null
$env:PYTHONUTF8 = '1'
@'
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import sys
p=Path(sys.argv[1]);image=Image.new('RGB',(1100,260),'white')
draw=ImageDraw.Draw(image);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',38)
draw.text((30,40),'9月25日23:59前交Java实验报告',font=font,fill='black')
draw.text((30,120),'预计3小时。',font=font,fill='black')
image.save(p/'notice.png')
'@ | & (Join-Path $projectRoot 'services/api/.venv/Scripts/python.exe') - $sampleDirectory
if ($LASTEXITCODE -ne 0) { throw 'Synthetic image generation failed.' }
Add-Type -AssemblyName System.Speech
$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
    $speaker.SelectVoice('Microsoft Huihui Desktop')
    $format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
    $speaker.SetOutputToWaveFile((Join-Path $sampleDirectory 'notice.wav'), $format)
    $speaker.Speak('九月二十五日晚上十一点五十九分之前，交Java实验报告，预计需要三个小时。')
} finally { $speaker.Dispose() }
Write-Output 'Synthetic image and Chinese TTS fixtures generated; no microphone used.'
