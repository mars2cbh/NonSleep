#!/usr/bin/env python3
"""Create and verify Sparkle-signed release metadata for both Mac architectures."""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET
import zipfile

from calver import CalVer

REPOSITORY = "mars2cbh/NonSleep"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def archive_metadata(archive, version, public_key):
    with zipfile.ZipFile(archive) as bundle:
        info = plistlib.loads(bundle.read("NonSleep.app/Contents/Info.plist"))
    expected = {
        "CFBundleIdentifier": "dev.nonsleep.mac",
        "CFBundleShortVersionString": version.app_version,
        "NonSleepReleaseVersion": str(version),
        "SUPublicEDKey": public_key,
    }
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError(f"{archive.name}: app identity, version or public key mismatch")
    build = str(info.get("CFBundleVersion", ""))
    if not build.isascii() or not build.isdigit() or int(build) <= 0:
        raise ValueError(f"{archive.name}: invalid build number")
    return info


def run_signer(signer, secret, *arguments):
    # Feed secrets through stdin, never shell interpolation or process arguments.
    result = subprocess.run([str(signer), "--ed-key-file", "-", *map(str, arguments)],
                            input=secret, text=True, capture_output=True)
    if result.returncode:
        raise ValueError("Sparkle signing or verification failed")
    return result.stdout.strip()


def generate(dist, version, signer, secret, public_key):
    if not secret:
        raise ValueError("Configure the SPARKLE_PRIVATE_KEY GitHub Actions secret first")
    # Fail before signing if a rotated/mistyped secret differs from the key in the app.
    result = subprocess.run(["swift", str(Path(__file__).with_name("update-key.swift")), "public"],
                            input=secret, text=True, capture_output=True)
    if result.returncode or result.stdout.strip() != public_key:
        raise ValueError("SPARKLE_PRIVATE_KEY does not match Resources/Info.plist SUPublicEDKey")
    archives = []
    for arch in ("arm64", "x86_64"):
        archive = dist / f"NonSleep-{version}-macos-{arch}.zip"
        info = archive_metadata(archive, version, public_key)
        archives.append((arch, archive, info))
    if len({info["CFBundleVersion"] for _, _, info in archives}) != 1:
        raise ValueError("Architecture builds must have the same build number")
    outputs = []
    for arch, archive, info in archives:
        signature = run_signer(signer, secret, "-p", archive)
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError("Invalid Ed25519 signature")
        run_signer(signer, secret, "--verify", archive, signature)
        release_url = f"https://github.com/{REPOSITORY}/releases/tag/v{version}"
        download_url = f"https://github.com/{REPOSITORY}/releases/download/v{version}/{archive.name}"
        rss = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = f"NonSleep ({arch})"
        ET.SubElement(channel, "link").text = f"https://github.com/{REPOSITORY}/releases"
        ET.SubElement(channel, "description").text = "NonSleep updates"
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = f"NonSleep {version}"
        ET.SubElement(item, "link").text = release_url
        ET.SubElement(item, f"{{{SPARKLE}}}version").text = str(info["CFBundleVersion"])
        ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = str(version)
        ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
        ET.SubElement(item, "description").text = f"NonSleep {version}. See the GitHub Release for changes."
        ET.SubElement(item, "enclosure", {
            "url": download_url, "length": str(archive.stat().st_size),
            "type": "application/octet-stream", f"{{{SPARKLE}}}edSignature": signature,
        })
        feed = dist / f"appcast-{arch}.xml"
        ET.indent(rss)
        ET.ElementTree(rss).write(feed, encoding="utf-8", xml_declaration=True)
        # Sparkle 2.10 signs the feed itself as well as its enclosed archive.
        run_signer(signer, secret, feed)
        run_signer(signer, secret, "--verify", feed)
        outputs.extend((archive, feed))
    with (dist / "SHA256SUMS.txt").open("w") as checksums:
        for path in outputs:
            with path.open("rb") as stream:
                digest = hashlib.sha256(stream.read()).hexdigest()
            checksums.write(f"{digest}  {path.name}\n")
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--dist", type=Path, required=True)
    parser.add_argument("--signer", type=Path, required=True)
    parser.add_argument("--info", type=Path, default=Path("Resources/Info.plist"))
    args = parser.parse_args()
    try:
        with args.info.open("rb") as source:
            public_key = plistlib.load(source)["SUPublicEDKey"]
        outputs = generate(args.dist, CalVer.parse(args.version), args.signer,
                           os.environ.get("SPARKLE_PRIVATE_KEY", ""), public_key)
        print("Signed and verified: " + ", ".join(path.name for path in outputs))
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release metadata error: {error}\n")


if __name__ == "__main__":
    main()
