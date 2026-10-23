#!/usr/bin/env python3
"""Check first-party documentation links and heuristic publication findings."""
from pathlib import Path
import re
from security_audit import run

ROOT = Path(__file__).resolve().parent.parent


def check():
    report = run(all_files=not (ROOT / '.git').exists())
    errors = []
    for finding in report['findings']:
        errors.append(f"{finding['category']}: {finding['location']}:{finding['line']} (value withheld)")
    errors.extend('Review unreadable/oversized file: ' + p for p in report['review_required'])
    documents = [ROOT / 'README.md', ROOT / 'CONTRIBUTING.md']
    documents += list((ROOT / 'docs').rglob('*.md'))
    documents += [ROOT / 'backend/README.md', ROOT / 'colab/README.md']
    for document in documents:
        if not document.exists():
            errors.append(f'Missing document: {document.relative_to(ROOT)}')
            continue
        text = document.read_text()
        for target in re.findall(r'\]\(([^)]+)\)', text):
            if target.startswith(('https://', 'http://', '#', 'mailto:')):
                continue
            target = target.split('#')[0]
            if target and not (document.parent / target).exists():
                errors.append(f'Broken local link in {document.relative_to(ROOT)}: {target}')
        for target in re.findall(r'<img[^>]+src="([^"]+)"', text):
            if not target.startswith('https://') and not (document.parent / target).is_file():
                errors.append(f'Broken image in {document.relative_to(ROOT)}')
    if errors:
        print('\n'.join(errors))
        return 1
    print(f'Publication checks passed: {report["counts"]["files_inspected"]} candidates; local documentation links resolve.')
    return 0


if __name__ == '__main__':
    raise SystemExit(check())
