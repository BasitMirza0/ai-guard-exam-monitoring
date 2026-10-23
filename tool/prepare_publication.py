#!/usr/bin/env python3
"""Create a source-only review snapshot. Never initializes Git or publishes."""
import argparse
from pathlib import Path
import shutil
import subprocess
from security_audit import run

BLOCKING = {'private_key', 'github_token', 'google_api_key', 'aws_access_key',
            'bearer_literal', 'credential_literal', 'email', 'machine_path', 'tunnel_url'}


def prepare(output):
    root = Path(__file__).resolve().parent.parent
    output = Path(output).resolve()
    if output.exists():
        raise SystemExit('Destination already exists; choose a new empty destination.')
    if output == root or root.is_relative_to(output):
        raise SystemExit('Destination cannot contain the development repository.')
    report = run()
    findings = [f for f in report['findings'] if f['category'] in BLOCKING]
    if findings or report['review_required']:
        raise SystemExit('Review security scan findings before creating the snapshot (values withheld).')
    raw = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z',
                                   '--cached', '--others', '--exclude-standard'])
    paths = sorted(set(Path(p.decode()) for p in raw.split(b'\0') if p))
    ignored = subprocess.run(['git', '-C', str(root), 'check-ignore', '--no-index', '-z', '--stdin'], input=b'\0'.join(str(p).encode() for p in paths) + b'\0', stdout=subprocess.PIPE, check=False)
    if ignored.stdout:
        raise SystemExit('A tracked file is excluded by publication policy; review it before copying.')
    if not paths:
        raise SystemExit('No publication candidates found.')
    for path in paths:
        source = root / path
        if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(root):
            raise SystemExit('Unsafe/non-file candidate; inspect publication paths.')
        if source.stat().st_size > 50 * 1024 * 1024:
            raise SystemExit('A candidate exceeds 50 MiB; review model/artifact distribution first.')
    output.mkdir(parents=True)
    for path in paths:
        target = output / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / path, target)
    print(f'Created review snapshot: {len(paths)} files. No Git metadata, commit or push created.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    prepare(parser.parse_args().output)
