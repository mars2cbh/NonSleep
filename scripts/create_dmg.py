#!/usr/bin/env python3
"""Package NonSleep in a verified drag-to-Applications disk image, without Finder automation."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

from dmgbuild import build_dmg
from calver import CalVer


def run(*arguments):
    subprocess.run([str(value) for value in arguments], check=True)


def verify_image(image, architecture, expected_version):
    run('hdiutil', 'verify', image)
    with tempfile.TemporaryDirectory(prefix='nonsleep-dmg-verify-') as temporary:
        mount = Path(temporary) / 'volume'
        mount.mkdir()
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(image)],
                       check=True, stdout=subprocess.DEVNULL)
        try:
            app = mount / 'NonSleep.app'
            link = mount / 'Applications'
            if not link.is_symlink() or os.readlink(link) != '/Applications':
                raise ValueError('DMG must contain an Applications shortcut pointing to /Applications')
            if not (mount / '.DS_Store').is_file():
                raise ValueError('DMG Finder layout is missing')
            with (app / 'Contents/Info.plist').open('rb') as stream:
                info = plistlib.load(stream)
            if info.get('NonSleepReleaseVersion') != expected_version:
                raise ValueError('DMG app version does not match the source bundle')
            run('lipo', app / 'Contents/MacOS/NonSleep', '-verify_arch', architecture)
            run('codesign', '--verify', '--deep', '--strict', app)
        finally:
            run('hdiutil', 'detach', mount)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve()
    output = args.output.resolve()
    if app.name != 'NonSleep.app' or output.suffix != '.dmg':
        parser.error('Expected a NonSleep.app bundle and a .dmg output path')
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    version = CalVer.parse(info['NonSleepReleaseVersion'])
    if info.get('CFBundleIdentifier') != 'dev.nonsleep.mac':
        parser.error('Expected the NonSleep app bundle identifier')
    run('lipo', app / 'Contents/MacOS/NonSleep', '-verify_arch', args.arch)
    run('codesign', '--verify', '--deep', '--strict', app)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='nonsleep-dmg-', dir=output.parent) as temporary:
        work = Path(temporary)
        background = work / 'background.tiff'
        run('swift', Path(__file__).with_name('dmg-background.swift'), background)
        image = work / 'NonSleep.dmg'
        build_dmg(str(image), f'NonSleep {version}', settings={
            'format': 'UDZO', 'filesystem': 'HFS+',
            'files': [str(app)], 'symlinks': {'Applications': '/Applications'},
            'icon': str(app / 'Contents/Resources/AppIcon.icns'),
            'background': str(background),
            'window_rect': ((160, 160), (640, 480)),
            'default_view': 'icon-view', 'include_icon_view_settings': True,
            'show_toolbar': False, 'show_status_bar': False, 'show_sidebar': False,
            'show_tab_view': False, 'show_pathbar': False,
            'arrange_by': None, 'icon_size': 100, 'text_size': 13,
            'icon_locations': {'NonSleep.app': (160, 190), 'Applications': (480, 190)},
        })
        verify_image(image, args.arch, str(version))
        os.replace(image, output)
    print(f'Created and verified: {output}')


if __name__ == '__main__':
    main()
