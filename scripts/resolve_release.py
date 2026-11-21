#!/usr/bin/env python3
"""Resolve a release source and optionally allocate today's unused CalVer tag."""
from datetime import datetime
import os
from pathlib import Path
import plistlib
import subprocess
from zoneinfo import ZoneInfo

from calver import CalVer


def next_version(today, tags):
    used = []
    for tag in tags:
        try:
            version = CalVer.parse(tag)
        except ValueError:
            continue
        if tag == f"v{version}" and version.released == today and not version.modifier:
            used.append(version.revision)
    return CalVer(today, max(used) + 1 if used else 0)


def resolve(repo, requested_tag, publish, pushed_tag=None, today=None):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(repo), *args], text=True, stderr=subprocess.PIPE).strip()

    tag = pushed_tag if pushed_tag is not None else requested_tag.strip()
    publish = pushed_tag is not None or publish
    create_tag = False
    if tag:
        version = CalVer.parse(tag)
        if tag != f"v{version}":
            raise ValueError("Use a CalVer tag such as v2026.11.21 or v2026.11.21.1.")
        # A user-supplied tag must already exist; never silently select another source.
        commit = git("rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}")
    else:
        commit = git("rev-parse", "HEAD")
        if publish:
            today = today or datetime.now(ZoneInfo("Asia/Seoul")).date()
            version = next_version(today, git("tag", "--list").splitlines())
            tag = f"v{version}"
            create_tag = True
        else:
            with (Path(repo) / "Resources/Info.plist").open("rb") as source:
                version = CalVer.parse(plistlib.load(source)["NonSleepReleaseVersion"])
    return {"tag": tag, "version": str(version), "app-version": version.app_version,
            "commit": commit, "publish": str(publish).lower(),
            "prerelease": str(bool(version.modifier)).lower(),
            "create-tag": str(create_tag).lower()}


def main():
    try:
        values = resolve(Path.cwd(), os.environ.get("REQUESTED_TAG", ""),
                         os.environ.get("REQUESTED_PUBLISH") == "true",
                         os.environ["GITHUB_REF_NAME"] if os.environ.get("GITHUB_EVENT_NAME") == "push" else None)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Release configuration error: {error}") from error
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")
    print(f"Source: {values['commit']}; version: {values['version']}; publish: {values['publish']}; auto tag: {values['create-tag']}")


if __name__ == "__main__":
    main()
