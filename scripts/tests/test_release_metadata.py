import plistlib
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from calver import CalVer
from generate_appcasts import archive_metadata


class ReleaseMetadataTests(unittest.TestCase):
    def test_calver_dates_revisions_and_prereleases(self):
        version = CalVer.parse('v2026.11.21.2-beta.1')
        self.assertEqual(str(version), '2026.11.21.2-beta.1')
        self.assertEqual(version.app_version, '2026.11.21')
        self.assertEqual(str(CalVer.parse('2028.02.29')), '2028.02.29')
        for invalid in ('0.2.0', '2026.02.29', '2026.04.31', '2026.1.01',
                        '2026.11.21.0', '2026.11.21.01', '2026.11.21-beta.',
                        '2026.11.21-beta-', '2026.11.21/evil'):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                CalVer.parse(invalid)

    def test_metadata_rejects_mismatched_bundle_version_and_key(self):
        version = CalVer.parse('2026.11.21.1')
        info = dict(CFBundleIdentifier='dev.nonsleep.mac',
                    CFBundleShortVersionString='2026.11.21',
                    NonSleepReleaseVersion='2026.11.21.1',
                    SUPublicEDKey='trusted-public-key', CFBundleVersion='12')
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / 'test.zip'
            def write(values):
                with zipfile.ZipFile(archive, 'w') as bundle:
                    bundle.writestr('NonSleep.app/Contents/Info.plist', plistlib.dumps(values))
            write(info)
            self.assertEqual(archive_metadata(archive, version, 'trusted-public-key'), info)
            for key, value in [('CFBundleIdentifier', 'other.app'),
                               ('NonSleepReleaseVersion', '2026.11.20'),
                               ('SUPublicEDKey', 'rotated-key'), ('CFBundleVersion', '0')]:
                with self.subTest(key=key):
                    write({**info, key: value})
                    with self.assertRaises(ValueError):
                        archive_metadata(archive, version, 'trusted-public-key')


if __name__ == '__main__':
    unittest.main()
