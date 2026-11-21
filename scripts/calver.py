#!/usr/bin/env python3
"""Shared version policy for app bundles, release tags, and signed appcasts."""
import argparse
from dataclasses import dataclass
from datetime import date
import re


@dataclass(frozen=True)
class CalVer:
    released: date
    revision: int = 0
    modifier: str = ""

    @classmethod
    def parse(cls, value):
        match = re.fullmatch(
            r"v?([2-9][0-9]{3})\.([0-9]{2})\.([0-9]{2})(?:\.([1-9][0-9]*))?"
            r"(?:-([0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*))?", value)
        if not match:
            raise ValueError("Use YYYY.MM.DD[.N], for example 2026.11.20 or 2026.11.20.1.")
        year, month, day, revision, modifier = match.groups()
        return cls(date(int(year), int(month), int(day)), int(revision or 0), modifier or "")

    @property
    def app_version(self):
        return self.released.strftime("%Y.%m.%d")

    def __str__(self):
        return self.app_version + (f".{self.revision}" if self.revision else "") + (f"-{self.modifier}" if self.modifier else "")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    arguments = parser.parse_args()
    try:
        version = CalVer.parse(arguments.version)
    except ValueError as error:
        parser.error(str(error))
    print(f"{version}\t{version.app_version}")
