"""Shared ADB/UI primitives for the opt-in Android QA runners.

The caller selects and guards the isolated QA package. Importing this module
does not contact a device, inspect the UI, or change application data.
"""
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ADB = Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/platform-tools/adb.exe'
DEVICE = 'emulator-5554'
DUMP = '/sdcard/semesteros-items-qa.xml'


def shell(*args):
    return subprocess.run([str(ADB), '-s', DEVICE, 'shell', *args], check=True,
                          capture_output=True, text=True, encoding='utf-8',
                          errors='replace').stdout


def nodes():
    shell('uiautomator', 'dump', DUMP)
    return list(ET.fromstring(shell('cat', DUMP)).iter('node'))


def label(node):
    return (node.get('text', '') + '\n' + node.get('content-desc', '')).strip()


def tap(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
    shell('input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
