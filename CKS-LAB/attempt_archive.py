#!/usr/bin/env python3
"""Keep completed attempts before the controller creates a fresh lab."""
from datetime import datetime
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent
STATE = ROOT / '.cks-state'
JUMPBOX = STATE / 'jumpbox'
METADATA = ('cluster-uid', 'deadline', 'setup-complete', 'mode', 'exam-expected.json')


def inventory(root):
    result = {}
    for path in sorted(root.rglob('*')):
        name = str(path.relative_to(root))
        if path.is_symlink():
            result[name] = ['link', os.readlink(path)]
        elif path.is_file():
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
            result[name] = ['file', digest.hexdigest()]
        elif path.is_dir():
            result[name] = ['directory']
        else:
            raise ValueError('Unsupported answer file; previous attempt was retained.')
    return result


def prepare(include_node=False):
    if JUMPBOX.is_symlink():
        raise ValueError('Jumpbox is a symbolic link; archive it manually before restarting.')
    prior = JUMPBOX.exists() or any((STATE / name).exists() for name in METADATA)
    if not prior and not include_node:
        return ''
    archives = STATE / 'archives'
    archives.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix=datetime.now().strftime('%Y-%m-%d_%H-%M-%S_'), dir=archives))
    # A failed snapshot is kept for diagnosis but cannot be used to clear answers.
    if JUMPBOX.exists():
        shutil.copytree(JUMPBOX, directory / 'jumpbox', symlinks=True)
        if inventory(JUMPBOX) != inventory(directory / 'jumpbox'):
            raise ValueError('Answers changed during backup; original files were retained.')
    for name in METADATA:
        path = STATE / name
        if path.exists():
            shutil.copy2(path, directory / name)
    if include_node:
        try:
            resources = 'namespaces,nodes,pods,deployments,replicasets,services,networkpolicies,ingresses,serviceaccounts,roles,rolebindings,secrets,configmaps'
            with (directory / 'cluster-resources.json').open('wb') as stream:
                p = subprocess.run(['kubectl', '--context=cks-lab', 'get', resources,
                    '--all-namespaces', '-o', 'json', '--request-timeout=15s'],
                    stdout=stream, stderr=subprocess.PIPE, timeout=45)
            if p.returncode:
                raise ValueError('Could not archive cluster answers; existing lab was retained.')
            resources = json.loads((directory / 'cluster-resources.json').read_text())
            if not isinstance(resources, dict) or not isinstance(resources.get('items'), list):
                raise ValueError('Invalid cluster answer snapshot; existing lab was retained.')
            # Native Minikube SSH uses a PTY. Encode the tar stream before it
            # reaches that terminal, then remove CRLF while decoding locally.
            script = ('if sudo test -d /opt/cks-lab; then sudo tar -C /opt -czf - cks-lab; '
                      'else tar -czf - -T /dev/null; fi | base64')
            remote = 'bash -o pipefail -c ' + shlex.quote(script)
            encoded = directory / 'node-files.tar.gz.base64'
            with encoded.open('wb') as stream:
                p = subprocess.run(['minikube', '-p', 'cks-lab', 'ssh', '--', remote],
                                   stdout=stream, stderr=subprocess.PIPE, timeout=60)
            (directory / 'node-backup.log').write_bytes(p.stderr)
            if p.returncode:
                raise ValueError(f'Node backup command failed (exit {p.returncode}); existing lab was retained. '
                                 f'Diagnostics: {directory / "node-backup.log"}')
            try:
                with encoded.open('rb') as source, (directory / 'node-files.tar.gz').open('wb') as target:
                    for line in source:
                        data = line.strip()
                        if data:
                            target.write(base64.b64decode(data, validate=True))
            except binascii.Error as e:
                raise ValueError(f'Invalid node backup transfer; existing lab was retained. '
                                 f'Diagnostics: {directory}') from e
            # Read the whole stream to catch truncated/corrupt compressed output.
            with tarfile.open(directory / 'node-files.tar.gz', 'r:gz') as archive:
                members = archive.getmembers()
                for member in members:
                    if member.isfile():
                        with archive.extractfile(member) as stream:
                            while stream.read(1024 * 1024):
                                pass
            encoded.unlink()
        except (OSError, tarfile.TarError, subprocess.TimeoutExpired, EOFError) as e:
            raise ValueError(f'Could not verify node backup; existing lab was retained. Diagnostics: {directory}') from e
    (directory / 'archive-complete.json').write_text(json.dumps({'format': 1, 'node_snapshot': include_node}) + '\n')
    return str(directory)


def finish(name):
    if not name:
        return
    directory = Path(name).resolve()
    if directory.parent != (STATE / 'archives').resolve() or not (directory / 'archive-complete.json').is_file():
        raise ValueError('Unverified archive; original answers were retained.')
    if JUMPBOX.exists() or JUMPBOX.is_symlink():
        if JUMPBOX.is_symlink() or not (directory / 'jumpbox').is_dir() or inventory(JUMPBOX) != inventory(directory / 'jumpbox'):
            raise ValueError('Answers changed after backup; original files were retained.')
        shutil.rmtree(JUMPBOX)


def main():
    try:
        if sys.argv[1:] in (['prepare'], ['prepare', '--node']):
            print(prepare('--node' in sys.argv[2:]))
        elif len(sys.argv) == 3 and sys.argv[1] == 'finish':
            finish(sys.argv[2])
        else:
            raise ValueError('Use prepare [--node] or finish ARCHIVE_PATH.')
    except (OSError, ValueError) as e:
        print(f'Archive failed: {e}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
