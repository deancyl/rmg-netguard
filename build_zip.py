#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build rmg-netguard module zip (KSU module format: files at zip root).

Pure ASCII output, LF line endings preserved as-is (binary copy), no BOM.
"""
import hashlib
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "module")
OUT = os.path.join(HERE, "rmg-netguard-v2.1.0.zip")


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    files = []
    for root, dirs, names in os.walk(SRC):
        dirs.sort()
        for n in sorted(names):
            p = os.path.join(root, n)
            files.append(p)

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            arc = os.path.relpath(p, SRC).replace("\\", "/")
            z.write(p, arc)

    with zipfile.ZipFile(OUT) as z:
        bad = z.testzip()
        if bad:
            print("CORRUPT ENTRY: " + bad)
            sys.exit(1)
        names = z.namelist()

    # sanity: module.prop at zip root, LF check on scripts
    assert "module.prop" in names, "module.prop missing at zip root"
    for p in files:
        data = open(p, "rb").read()
        assert b"\r\n" not in data, "CRLF found in " + p
        assert not data.startswith(b"\xef\xbb\xbf"), "BOM found in " + p

    size = os.path.getsize(OUT)
    print("zip: " + OUT)
    print("md5: " + md5(OUT))
    print("size: %d bytes, %d entries" % (size, len(names)))
    for n in names:
        print("  " + n)


if __name__ == "__main__":
    main()
