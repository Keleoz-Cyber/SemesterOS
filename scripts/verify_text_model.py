"""Opt-in live smoke checks, synthetic inputs only. Does not print configuration or credentials."""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/api'))
from dotenv import dotenv_values
from app.text_model import deepseek_text
from app.item_schemas import ItemFields


def main():
    for key, value in dotenv_values(ROOT / '.env').items():
        if key.startswith('DEEPSEEK_') and value:
            os.environ[key] = value
    cases = [
        ('2026年9月25日23:59前交Java报告，预计3小时', 'assignment', 'exact', 180),
        ('周五交Java报告', 'assignment', 'date', None),
        ('概率论暂定第14周考试', 'exam', 'week', None),
    ]
    results = []
    for text, kind, precision, minutes in cases:
        value, metadata = deepseek_text(text, '2026-09-20T12:00:00+08:00', [])
        item = ItemFields.model_validate({**value['item'], 'semester_id': 'synthetic'})
        assert value['intent'] == 'create_item'
        assert item.kind == kind and item.time.precision == precision
        assert item.remaining_minutes == minutes
        if precision == 'week':
            assert item.time.week == 14 and item.certainty == 'tentative'
        assert all(quote in text for quote in value['evidence'].values())
        results.append({'case': text, 'passed': True, 'kind': item.kind,
                        'precision': item.time.precision, 'metadata': metadata})
    directory = ROOT / 'output/verification'
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'text-model-smoke.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'passed': len(results), 'model': results[0]['metadata']['model']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
