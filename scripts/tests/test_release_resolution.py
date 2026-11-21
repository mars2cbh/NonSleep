from datetime import date
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from resolve_release import next_version, resolve


class ReleaseResolutionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repo = Path(self.directory.name)
        self.git('init', '-q')
        resources = self.repo / 'Resources'
        resources.mkdir()
        (resources / 'Info.plist').write_bytes(plistlib.dumps({'NonSleepReleaseVersion': '2026.11.20'}))
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'Initial')
        self.commit = self.git('rev-parse', 'HEAD')
        self.today = date(2026, 11, 21)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True, stderr=subprocess.PIPE).strip()

    def test_blank_tag_and_publish_allocates_today_without_modifying_repository(self):
        result = resolve(self.repo, '', True, today=self.today)
        self.assertEqual(result['tag'], 'v2026.11.21')
        self.assertEqual(result['version'], '2026.11.21')
        self.assertEqual(result['commit'], self.commit)
        self.assertEqual(result['create-tag'], 'true')
        self.assertEqual(result['publish'], 'true')
        self.assertEqual(self.git('tag', '--list'), '')

    def test_same_day_uses_next_revision_and_ignores_other_dates_and_prereleases(self):
        tags = ['v2026.11.20.99', 'v2026.11.21', 'v2026.11.21.3',
                'v2026.11.21.9-beta.1', 'v0.2.0', 'invalid']
        for tag in tags:
            self.git('tag', tag)
        result = resolve(self.repo, '', True, today=self.today)
        self.assertEqual(result['tag'], 'v2026.11.21.4')
        self.assertEqual(result['app-version'], '2026.11.21')
        self.assertEqual(str(next_version(date(2026, 11, 22), tags)), '2026.11.22')

    def test_build_only_keeps_bundle_version_and_creates_no_tag(self):
        result = resolve(self.repo, '', False, today=self.today)
        self.assertEqual(result['version'], '2026.11.20')
        self.assertEqual(result['tag'], '')
        self.assertEqual(result['create-tag'], 'false')
        self.assertEqual(result['publish'], 'false')

    def test_explicit_tag_uses_its_source_and_missing_tag_is_rejected(self):
        self.git('tag', 'v2026.11.20-beta.1')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '--allow-empty', '-qm', 'Later')
        result = resolve(self.repo, 'v2026.11.20-beta.1', True, today=self.today)
        self.assertEqual(result['commit'], self.commit)
        self.assertEqual(result['create-tag'], 'false')
        self.assertEqual(result['prerelease'], 'true')
        with self.assertRaises(subprocess.CalledProcessError):
            resolve(self.repo, 'v2026.11.21', True, today=self.today)

    def test_push_tag_overrides_dispatch_and_always_publishes(self):
        self.git('tag', 'v2026.11.21')
        result = resolve(self.repo, 'unused', False, pushed_tag='v2026.11.21')
        self.assertEqual(result['publish'], 'true')
        self.assertEqual(result['tag'], 'v2026.11.21')
        self.assertEqual(result['create-tag'], 'false')


if __name__ == '__main__':
    unittest.main()
