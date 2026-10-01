<div align="center">

# 🎧 Arctis 7 · Low-Battery Beep Muter

**Silence the "beep-beep" your Arctis 7 makes when the battery runs low, by patching the firmware GG already ships.**

`Python 3` · `Windows PowerShell` · `no dependencies` · `6 bytes changed`

</div>

> **Unofficial.** Not affiliated with or endorsed by SteelSeries. You flash your own headset at your own risk
> (see [Risks](#-risks)). Firmware files belong to SteelSeries and are never included in this repository.

SteelSeries says the Arctis 7 low-battery alert [cannot be disabled](https://support.steelseries.com/hc/en-us/articles/10000346317581-How-do-I-disable-the-low-battery-alert-on-my-Arctis-7).
It is just a tone stored in the headset firmware, so this project mutes that one tone and leaves everything else
alone: same version, same threshold (about 20 %), same other sounds.

| | Before | After |
|---|---|---|
| `LowBatTone` | 419 Hz beep · pause · 419 Hz beep · pause | pause · pause · pause · pause |
| Everything else in the firmware | | **byte-for-byte identical** |

**Tested on:** Arctis 7 (2019 edition), GG 120.0.0, firmware 1.19.0.0, Python 3.10, Windows PowerShell 5.1.

| | Status |
|---|---|
| Editing tone blocks and flashing them through GG | ✅ verified on a real headset (modified startup sounds were heard) |
| The patched firmware changes only `LowBatTone` | ✅ checked byte by byte |
| The muted tone really is the low-battery alert | ❓ not triggered yet, only confirmed once the battery gets low |

## ⚡ Quick start

Two scripts. Neither needs anything installed beyond Python 3 and PowerShell.

```powershell
python patch_lowbat.py                                              # 1. build the patched firmware into .\out\
powershell -ExecutionPolicy Bypass -File .\install.ps1 install      # 2. ADMINISTRATOR PowerShell: copy it into GG
```

Then:

1. **Restart GG** (it only reads `version.json` at startup) and plug the headset in with its **micro-USB cable**.
2. Open **GG → Engine → Arctis 7** and click **"Click to install"** in the green banner. Unplug nothing until it ends.
3. Switch the headset off and on.

GG keeps showing the update banner afterwards. That is expected and harmless, see [How GG decides](#-how-gg-offers-the-update).

| Script | What it does |
|---|---|
| `patch_lowbat.py` | Reads the headset firmware (from GG, or `--source FILE.ef`) and writes a patched copy to `out\` (git-ignored). **Never touches GG.** |
| `install.ps1 install` | Backs up the originals as `original-<name>.bak`, copies the patched firmware into GG, and raises the `version.json` files (headset and dongle) so GG offers the update. |
| `install.ps1 restore` | Removes the patched firmware **and** the backups, leaves only the official firmware in GG's folder, and makes GG offer the update again so the headset gets the official firmware back. |

### Sharing it

`install.ps1` looks for the patched `.ef` in `.\out\` next to it, then right next to itself. A release is therefore
just **the patched `.ef` + `install.ps1` in one folder**, no `out\` needed (`-Firmware PATH` also works). The file
name must start with `firmware`.

## ↩️ Back to the official firmware

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 restore       # ADMINISTRATOR PowerShell
```

Restart GG, headset on micro-USB, **"Click to install"**. `restore` deliberately keeps the raised `version.json`
(`1.42.0.0`): that is what makes GG offer the update, so the headset is flashed with the official firmware again.

## 🔁 When GG ships a new firmware

GG overwrites its firmware folder, but old backups would stay behind and `patch_lowbat.py` would patch the **old**
original. So: delete the `original-*.bak` files in GG's firmware folders, then run both scripts again.
`patch_lowbat.py` refuses to write anything if the integrity formula, the `LowBatTone` block or its layout differ.

## ⚠️ Risks

- A firmware with a wrong integrity field can be rejected, leaving the headset in bootloader mode (it then shows up
  as "Avnera AV6302"). GG has a recovery procedure for it, **not tested here**. The script checks the integrity
  field of every block before writing anything.
- Never unplug anything or power off the PC while GG is flashing.
- Only the Arctis 7 (2018/2019) folders of GG are touched.

<details>
<summary><h2>🔬 How it works</h2></summary>

### Where the firmware lives

GG keeps firmware in `C:\Program Files\SteelSeries\GG\apps\engine\firmware\<id>\`, with
`id = (0x1038 << 16) | USB PID` written in decimal:

| Folder | Device | USB PID | File |
|---|---|---|---|
| `272110254` | headset (`rx`) | `12AE` | `firmware-arctis-7-2018-rx-v1.19.0.ef` |
| `272110253` | USB dongle (`tx`) | `12AD` | `firmware-arctis-7-2018-tx-v1.19.0.ff` |

Each folder also has a `version.json`. Only the headset firmware contains the tones.

### The firmware format

A text file, one byte per line (`6A // 0x0000`), cut into named blocks by `IMAGE:` markers. A config block is a
4-byte header (id, 16-bit length, check byte so the four bytes sum to `0xFF`), then `06 c1 c2` and the content.
`c1 c2` is an **integrity field**.

### The tones

`PowerOnTone`, `LowBatTone`, `ButtonPressTone`, `LinkUpTone`, `LinkDownTone`. After `01 0d 03 28 c4 b4`, 4-byte
items `1a 00 lo hi` alternate **duration (ms)** and **frequency (Hz)**; frequency `1` is a pause, `0` ends the tone.
`LowBatTone` is two 100 ms beeps at 419 Hz, identical in the Arctis 7, 1W, 1X, 7P and 7X firmwares.
Units were checked on the headset: a 1000 Hz tone sounds clearly higher than 419 Hz.

Block names are only hints: editing `PowerOnTone` changed both the startup sound and the mic mute/unmute sound.

### The integrity field

Without fixing it, a modified block may be rejected. CRCs, byte sums and XOR did not match. What does, on 165 blocks
of 8 firmwares:

```
S = sum of the big-endian 16-bit words of the content   (an odd last byte counts as a high byte)
c = S + 1                                                (mod 65536)
if len(content) is even:  c = c - content[-1]
c1 c2 = c, little-endian
```

How it was found: the field is identical for identical content across firmwares, so it depends on the content only;
the word sum matched in its low byte with a constant gap of 1, except for a few blocks, which all ended with a
non-zero byte.

### How GG offers the update

- GG shows **"Click to install"** when a folder's `version.json` is newer than the version read from the device.
  The Arctis 7 card is the **dongle's**, so its `version.json` must be raised too: raising only the headset's shows
  nothing. `1.42.0.0` is just a value above the real `1.19.0.0`; it is not written into the firmware.
- GG picks the firmware file in the folder with the pattern `^firmware`. The name only has to start with
  `firmware`, and **no other file may**. That is why backups are named `original-*.bak`.
- With the micro-USB cable, Windows sees the headset itself (PID `12AE`) and GG updates it directly.
- **Do not edit the version text** inside the firmware (`V1.19,client,...`). GG reads the headset version from it
  and compares with `version.json` only when both have the same number of parts. A `V1.19.3` text made GG report
  `1.19.3.0.0` (5 parts) and the headset update was silently skipped.
- After flashing, the device still reports its real version, so the banner stays. Clicking it again would only
  flash the same firmware.

</details>

## 📄 License

[MIT](LICENSE). The scripts are MIT-licensed; the firmware they patch is SteelSeries' and is not covered by it.

## 📚 Sources and thanks

- [SteelSeries support](https://support.steelseries.com/hc/en-us/articles/10000346317581-How-do-I-disable-the-low-battery-alert-on-my-Arctis-7): the alert is not configurable
- [HeadsetControl](https://github.com/Sapd/HeadsetControl): no command for this beep
- [Prehistoricman/AV7300](https://github.com/Prehistoricman/AV7300) and [whitequark/binja-avnera](https://github.com/whitequark/binja-avnera): Avnera chip reverse engineering
