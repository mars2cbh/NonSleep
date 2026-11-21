import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
ENTRY = re.compile(r'("(?:\\.|[^"\\])*") = ("(?:\\.|[^"\\])*");')


def catalog(language):
    path = ROOT / f'Sources/NonSleepCore/Resources/{language}.lproj/Localizable.strings'
    pairs = [tuple(map(json.loads, match.groups())) for match in ENTRY.finditer(path.read_text())]
    if len(pairs) != len(dict(pairs)):
        raise ValueError('Duplicate localization keys')
    return dict(pairs)


class LocalizationCatalogTests(unittest.TestCase):
    def test_both_languages_cover_app_strings_and_keep_format_arguments(self):
        english, korean = catalog('en'), catalog('ko')
        self.assertEqual(english.keys(), korean.keys())
        for key in english:
            self.assertEqual(sorted(re.findall(r'%(?:[0-9]+\$)?[@d]', english[key])),
                             sorted(re.findall(r'%(?:[0-9]+\$)?[@d]', korean[key])), key)
        for source in (ROOT / 'Sources').rglob('*.swift'):
            for match in re.finditer(r'L10n\.tr\(("(?:\\.|[^"\\])*")', source.read_text()):
                self.assertIn(json.loads(match[1]), english, str(source))


if __name__ == '__main__':
    unittest.main()
