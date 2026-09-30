"""Summarize exclusive widget-build time from sanitized timeline events."""

import argparse
import json
from collections import defaultdict
from pathlib import Path


def main(path: Path):
    events = json.loads(path.read_text(encoding="utf-8"))
    stacks = defaultdict(list)
    totals = defaultdict(lambda: [0, 0.0, 0.0])
    for event in events:
        thread = (event.get("pid"), event.get("tid"))
        stack = stacks[thread]
        phase = event.get("ph")
        if phase == "B":
            stack.append([event.get("name"), event.get("ts", 0), 0.0])
        elif phase == "E" and stack:
            name, start, children = stack.pop()
            duration = max(0.0, event.get("ts", 0) - start)
            exclusive = max(0.0, duration - children) / 1000
            if name == "ShellPage" or any(row[0] == "ShellPage" for row in stack):
                row = totals[name]
                row[0] += 1
                row[1] += exclusive
                row[2] = max(row[2], exclusive)
            if stack:
                stack[-1][2] += duration
    for name, (count, total, maximum) in sorted(
        totals.items(), key=lambda item: item[1][1], reverse=True
    )[:50]:
        print(f"{total:7.3f} ms total {maximum:7.3f} max {count:4d} {name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    main(parser.parse_args().path)
