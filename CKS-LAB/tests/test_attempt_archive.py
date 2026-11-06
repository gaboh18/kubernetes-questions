"""Verify previous work is recoverable before automatic restart clears it."""
import base64
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import tarfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('attempt_archive', Path(__file__).resolve().parents[1] / 'attempt_archive.py')
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(); self.addCleanup(tmp.cleanup)
        self.state = Path(tmp.name) / '.cks-state'; self.state.mkdir()
        self.jump = self.state / 'jumpbox'; self.jump.mkdir()
        (self.jump / 'answer').write_text('keep this work')
        for key, value in [('STATE', self.state), ('JUMPBOX', self.jump)]:
            p = patch.object(archive, key, value); p.start(); self.addCleanup(p.stop)

    def test_snapshot_retains_source_until_finish_and_keeps_private_backup(self):
        (self.jump / 'link').symlink_to('answer')
        directory = Path(archive.prepare())
        self.assertEqual((self.jump / 'answer').read_text(), 'keep this work')
        self.assertEqual((directory / 'jumpbox' / 'answer').read_text(), 'keep this work')
        self.assertTrue((directory / 'jumpbox' / 'link').is_symlink())
        self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        archive.finish(str(directory))
        self.assertFalse(self.jump.exists())
        self.assertEqual((directory / 'jumpbox' / 'answer').read_text(), 'keep this work')

    def test_answers_edited_after_snapshot_are_kept(self):
        directory = archive.prepare()
        (self.jump / 'answer').write_text('new edit')
        with self.assertRaises(ValueError): archive.finish(directory)
        self.assertEqual((self.jump / 'answer').read_text(), 'new edit')

    def test_unverified_directory_cannot_clear_answers(self):
        with self.assertRaises(ValueError): archive.finish(str(self.state))
        self.assertTrue((self.jump / 'answer').exists())

    def test_repeated_archives_are_unique(self):
        first, second = Path(archive.prepare()), Path(archive.prepare())
        self.assertNotEqual(first, second)
        for directory in [first, second]:
            self.assertEqual((directory / 'jumpbox' / 'answer').read_text(), 'keep this work')

    def test_corrupt_node_stream_never_completes_backup(self):
        def export(args, stdout, **kw):
            stdout.write(b'{"items":[]}' if args[0] == 'kubectl' else b'not a valid archive')
            return subprocess.CompletedProcess(args, 0, None, b'')
        with patch.object(archive.subprocess, 'run', side_effect=export):
            with self.assertRaises(ValueError): archive.prepare(include_node=True)
        self.assertTrue((self.jump / 'answer').exists())
        self.assertFalse(list((self.state / 'archives').glob('*/archive-complete.json')))


    def test_node_archive_survives_terminal_crlf_without_binary_output(self):
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode='w:gz') as node:
            member = tarfile.TarInfo('cks-lab/answer.txt'); member.size = 6
            node.addfile(member, io.BytesIO(b'answer'))
        encoded = base64.encodebytes(buffer.getvalue()).replace(b'\n', b'\r\n')
        def export(args, stdout, **kw):
            if args[0] == 'kubectl':
                stdout.write(b'{"items":[]}')
            else:
                self.assertIn('bash -o pipefail -c ', args[-1])
                self.assertIn('| base64', args[-1])
                stdout.write(encoded)
            return subprocess.CompletedProcess(args, 0, None, b'')
        with patch.object(archive.subprocess, 'run', side_effect=export):
            directory = Path(archive.prepare(include_node=True))
        with tarfile.open(directory / 'node-files.tar.gz', 'r:gz') as node:
            self.assertEqual(node.extractfile('cks-lab/answer.txt').read(), b'answer')
        self.assertTrue((directory / 'archive-complete.json').exists())
        self.assertFalse((directory / 'node-files.tar.gz.base64').exists())
        self.assertTrue((self.jump / 'answer').exists())

    def test_valid_encoding_of_invalid_tar_is_rejected(self):
        def export(args, stdout, **kw):
            stdout.write(b'{"items":[]}' if args[0] == 'kubectl' else base64.encodebytes(b'not gzip'))
            return subprocess.CompletedProcess(args, 0, None, b'')
        with patch.object(archive.subprocess, 'run', side_effect=export):
            with self.assertRaises(ValueError): archive.prepare(include_node=True)
        self.assertTrue((self.jump / 'answer').exists())
        self.assertFalse(list((self.state / 'archives').glob('*/archive-complete.json')))

    def test_ssh_failure_retains_diagnostics_and_current_work(self):
        def export(args, stdout, **kw):
            if args[0] == 'kubectl':
                stdout.write(b'{"items":[]}')
                return subprocess.CompletedProcess(args, 0, None, b'')
            return subprocess.CompletedProcess(args, 1, None, b'ssh: Process exited with status 2')
        with patch.object(archive.subprocess, 'run', side_effect=export):
            with self.assertRaisesRegex(ValueError, 'node-backup.log'):
                archive.prepare(include_node=True)
        log = next((self.state / 'archives').glob('*/node-backup.log'))
        self.assertIn('status 2', log.read_text())
        self.assertTrue((self.jump / 'answer').exists())
        self.assertFalse(list((self.state / 'archives').glob('*/archive-complete.json')))


if __name__ == '__main__':
    unittest.main()
