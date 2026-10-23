#!/usr/bin/env python3
"""Location-only heuristic scan. Never prints matched credential/identity values.

Default: publication candidates (tracked + unignored files).
--all-files: include ignored working-tree files, excluding .git internals.
--git-objects: additionally inspect every readable Git blob/commit, even unreachable.
This is not a proof of absence: binary files, oversized text and unknown formats
need separate review. Reports are local artifacts, not publication content.
"""
import argparse
import collections
import json
import os
from pathlib import Path
import re
import subprocess

PATTERNS = {
    'private_key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'github_token': rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})',
    'google_api_key': rb'AIza[0-9A-Za-z_-]{35}',
    'aws_access_key': rb'(?:AKIA|ASIA)[A-Z0-9]{16}',
    'bearer_literal': rb'Bearer [A-Za-z0-9_.-]{24,}',
    'credential_literal': rb'''(?i)(?:ngrok_authtoken|authtoken|client_secret|storePassword|keyPassword|password|api_secret)\s*[=:]\s*["']([^"'\s]{8,})["']''',
    'email': rb'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
    'machine_path': rb'(?:/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/|[A-Z]:\\Users\\[A-Za-z0-9._-]+)',
    'tunnel_url': rb'https?://[a-zA-Z0-9.-]+\.ngrok(?:-free)?\.(?:app|dev|io)',
}
COMPILED = {k: re.compile(v) for k, v in PATTERNS.items()}
LIMIT = 16 * 1024 * 1024


def scan(data, location, findings):
    for category, pattern in COMPILED.items():
        seen = set()
        for match in pattern.finditer(data):
            if category == 'email' and re.search(rb'@[123]x\.png$', match.group()):
                continue
            if category == 'email' and match.group().lower().endswith((b'@example.com', b'@example.org', b'@users.noreply.github.com')):
                continue
            line = data.count(b'\n', 0, match.start()) + 1
            if line in seen:
                continue
            seen.add(line)
            findings.append({'location': location, 'line': line, 'category': category})


def run(all_files=False, git_objects=False):
    root = Path(__file__).resolve().parent.parent
    os.chdir(root)
    report = {'scope': 'all working files' if all_files else 'publication candidates',
              'counts': collections.Counter(), 'findings': [], 'review_required': []}
    if all_files or not (root / '.git').exists():
        def working_files():
            for parent, dirs, files in os.walk('.'):
                dirs[:] = [d for d in dirs if d != '.git']
                for name in files:
                    yield Path(parent) / name
        paths = working_files()
    else:
        raw = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'])
        paths = (Path(os.fsdecode(p)) for p in raw.split(b'\0') if p)
    for path in paths:
        if path.is_symlink():
            report['counts']['symlinks_not_followed'] += 1
            continue
        try:
            with path.open('rb') as handle:
                data = handle.read(LIMIT + 1)
            report['counts']['files_inspected'] += 1
            if b'\0' in data[:8192]:
                report['counts']['binary_not_scanned'] += 1
                continue
            if len(data) > LIMIT:
                report['review_required'].append(str(path))
                report['counts']['oversized_text_not_scanned'] += 1
                continue
            report['counts']['text_scanned'] += 1
            scan(data, str(path), report['findings'])
        except OSError:
            report['review_required'].append(str(path))
    if git_objects:
        index = subprocess.check_output(['git', 'cat-file', '--batch-all-objects', '--batch-check=%(objectname) %(objecttype) %(objectsize)'], stderr=subprocess.DEVNULL)
        process = subprocess.Popen(['git', 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        for row in index.splitlines():
            oid, kind, length = row.split()
            report['counts']['git_' + kind.decode()] += 1
            if kind not in (b'blob', b'commit'):
                continue
            if int(length) > LIMIT:
                report['counts']['git_oversized_not_scanned'] += 1
                continue
            process.stdin.write(oid + b'\n')
            process.stdin.flush()
            header = process.stdout.readline().split()
            data = process.stdout.read(int(header[2]))
            process.stdout.read(1)
            if b'\0' in data[:8192]:
                report['counts']['git_binary_not_scanned'] += 1
                continue
            report['counts']['git_text_scanned'] += 1
            scan(data, 'git-object:' + oid.decode()[:12], report['findings'])
            if kind == b'commit':
                report['counts']['commit_identity_headers'] += len(re.findall(rb'^(?:author|committer) ', data, re.M))
        process.stdin.close()
        process.wait()
    report['categories'] = dict(collections.Counter(f['category'] for f in report['findings']))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--all-files', action='store_true')
    parser.add_argument('--git-objects', action='store_true')
    args = parser.parse_args()
    print(json.dumps(run(args.all_files, args.git_objects), indent=2))
