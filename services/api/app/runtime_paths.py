from pathlib import Path

API_ROOT=Path(__file__).resolve().parents[1]
PROJECT_ROOT=API_ROOT.parent.parent if API_ROOT.name=='api' and API_ROOT.parent.name=='services' else API_ROOT
