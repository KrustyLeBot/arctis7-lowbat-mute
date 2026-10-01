#!/usr/bin/env python3
"""Create a copy of the Arctis 7 (2018/2019) headset firmware with the low-battery beep muted.

    python patch_lowbat.py                       # reads the firmware from SteelSeries GG
    python patch_lowbat.py --source FILE.ef      # or from a file you give it

The patched firmware is written to the "out" folder next to this script (git-ignored).
Nothing else is changed in the firmware, and GG itself is never touched: install.ps1 does that.
"""
import argparse
import hashlib
import os
import re
import sys

GG_DIR = r"C:\Program Files\SteelSeries\GG\apps\engine\firmware"
HEADSET_ID = "272110254"          # GG folder of the headset: (0x1038 << 16) | USB PID 0x12AE, in decimal
TONE_BLOCK = "LowBatTone"
TONE_PREFIX = 13                  # 4-byte header + "06 c1 c2" + "01 0d 03 28 c4 b4"
PAUSE = 1                         # tone frequency value meaning "silence"

LINE = re.compile(r"^([0-9A-Fa-f]{2})\s*//\s*0x([0-9a-fA-F]+)(?:\s+IMAGE:\s*(\S*))?")


def read_firmware(path):
    """Return (bytes, {block name: (start, end)}, text lines) of an .ef firmware file."""
    data, starts = bytearray(), []
    lines = open(path, encoding="ascii").read().split("\n")
    for line in lines:
        m = LINE.match(line.strip())
        if m:
            if m.group(3):
                starts.append((m.group(3), len(data)))
            data.append(int(m.group(1), 16))
    ends = [start for _, start in starts[1:]] + [len(data)]
    return data, {name: (s, e) for (name, s), e in zip(starts, ends)}, lines


def integrity(body):
    """16-bit integrity field of a config block ("06 c1 c2" + body); c1 c2 are stored little-endian.

    Sum of the big-endian 16-bit words of the body (an odd last byte counts as a high byte), plus 1,
    minus the last body byte when the body length is even. Matches all 165 blocks of 8 GG firmwares.
    """
    total = sum(body[i] << 8 | body[i + 1] for i in range(0, len(body) - 1, 2)) + 1
    total += body[-1] << 8 if len(body) % 2 else -body[-1]
    return total & 0xFFFF


def verify_integrity(data, blocks):
    """Stop unless the formula reproduces every config block of this firmware (new version = new rules?)."""
    checked = 0
    for name, (s, e) in blocks.items():
        b = data[s:e]
        if len(b) > 7 and b[4] == 6 and sum(b[:4]) & 255 == 255 and b[1] | b[2] << 8 == len(b) - 4:
            if integrity(bytes(b[7:])) != b[5] | b[6] << 8:
                sys.exit(f"Unknown firmware: the integrity formula differs on {name}. Nothing was written.")
            checked += 1
    print(f"integrity formula verified on {checked} blocks")


def mute_tone(path):
    """Return the firmware text with the notes of TONE_BLOCK replaced by pauses."""
    data, blocks, lines = read_firmware(path)
    verify_integrity(data, blocks)
    if TONE_BLOCK not in blocks:
        sys.exit(f"Block {TONE_BLOCK} not found.")
    s, e = blocks[TONE_BLOCK]
    block = bytearray(data[s:e])
    # 4-byte items "1a 00 lo hi" alternating duration (ms) / frequency (Hz); frequency 1 = pause, 0 = end
    items = range(TONE_PREFIX, len(block), 4)
    if any(block[i] != 0x1A or block[i + 1] != 0 for i in items):
        sys.exit(f"{TONE_BLOCK} has an unexpected layout. Nothing was written.")
    value = lambda i: block[i + 2] | block[i + 3] << 8
    print("tone before:", [value(i) for i in items])
    for i in list(items)[1::2]:                         # frequencies only, durations are kept
        if value(i) not in (0, PAUSE):
            block[i + 2], block[i + 3] = PAUSE, 0
    check = integrity(bytes(block[7:]))
    block[5], block[6] = check & 255, check >> 8
    print("tone after: ", [value(i) for i in items])

    patched = bytearray(data)
    patched[s:e] = block
    out = []
    for line in lines:                                  # rewrite only the lines whose byte changed
        m = LINE.match(line.strip())
        if m and patched[int(m.group(2), 16)] != data[int(m.group(2), 16)]:
            line = f"{patched[int(m.group(2), 16)]:02X}" + line.strip()[2:]
        out.append(line)
    print(f"{sum(a != b for a, b in zip(data, patched))} bytes changed, all inside {TONE_BLOCK}")
    return "\n".join(out)


def find_source(gg_dir):
    """The headset firmware in GG's folder: the original-*.bak made by install.ps1 if present, else the .ef."""
    folder = os.path.join(gg_dir, HEADSET_ID)
    if not os.path.isdir(folder):
        sys.exit(f"{folder} not found. Is GG installed, and was the headset connected once? (see --gg-dir, --source)")
    names = os.listdir(folder)
    backups = [n for n in names if n.startswith("original-firmware") and n.endswith(".ef.bak")]
    firmwares = [n for n in names if n.startswith("firmware") and n.endswith(".ef")]
    if backups:
        return os.path.join(folder, backups[0]), backups[0][len("original-"):-len(".bak")]
    if len(firmwares) != 1:
        sys.exit(f"Expected exactly one firmware*.ef in {folder}, found {firmwares}.")
    return os.path.join(folder, firmwares[0]), firmwares[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", help="headset firmware (.ef) to patch instead of the one in GG")
    parser.add_argument("--gg-dir", default=os.environ.get("ARCTIS7_GG_FIRMWARE_DIR", GG_DIR))
    parser.add_argument("--out-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "out"))
    args = parser.parse_args()

    if args.source:
        source, name = args.source, os.path.basename(args.source)
    else:
        source, name = find_source(args.gg_dir)
    print(f"source: {source}")
    text = mute_tone(source)

    os.makedirs(args.out_dir, exist_ok=True)
    target = os.path.join(args.out_dir, name)
    with open(target, "w", newline="") as f:
        f.write(text)
    print(f"patched firmware: {target}")
    print("sha256:", hashlib.sha256(open(target, "rb").read()).hexdigest())
    print("\nNext: run install.ps1 in an administrator PowerShell (see README.md).")


if __name__ == "__main__":
    main()
