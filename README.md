# Torii

A macOS app for capturing and transplanting PS5 extended storage partition
headers, with guard rails so nobody has to point `dd` at the wrong disk.

> **Status: experimental, and currently blocked.** The technique this tool
> automates is known to have worked on PS5 firmware 4.03, but the extended
> storage partition layout changed on later firmware and no sample of the
> current layout is publicly available. See [Current blocker](#current-blocker).

## What this is about

The PS5 M.2 expansion slot requires a PCIe Gen4 drive with at least 5,500 MB/s
sequential read. A Gen3 x4 drive tops out around 3.5 GB/s — below the floor by
bus bandwidth, not by labelling, so no firmware trick makes a Gen3 drive
negotiate as Gen4.

What *was* demonstrated is different: the console appears to run its speed
validation at **format** time, not at **mount** time. Presented with a volume
that already carries a valid extended storage layout, it mounts the drive
without ever benchmarking it.

In 2022 this was reached by accident. Windfox found that writing the
NetflixNHack extended storage image onto a Gen3 M.2 got the console to accept
the drive instead of refusing it; flaviopenas-ps then trimmed that image into
something small and quick to flash. Bringus Studios mounted a 128 GB drive the
same way, so the 250 GB floor was not enforced either. No exploit and no
jailbreak are involved — this runs on stock firmware.

## Current blocker

The extended storage partition layout changed on newer firmware, so images
built for 4.03 are no longer recognized. Rebuilding one requires a sample of
the current layout, which means a read-only dump of the leading sectors from a
Gen4 drive that is already formatted and working in a PS5 on current firmware.

Two open questions determine whether the approach survives at all:

- **Does the header carry console-unique data?** If the layout is bound to the
  console that formatted it, a shared dump is useless.
- **Does drive capacity have to match?** DrYenyen's drive cloning research
  notes that PS5 M.2 extended storage needs exact-size images, unlike PS4
  extended storage. If that applies here, a donor has to match the target's
  capacity rather than being any Gen4 drive.

If you have a Gen4 expansion drive in a PS5 on current firmware and are willing
to contribute a read-only header dump, open an issue. Nothing is written to your
drive and installed games are untouched.

## What the app does

- Enumerates removable NVMe drives and refuses to touch the boot disk or any
  internal volume.
- Captures a read-only header image from a donor drive.
- Writes a header image onto a target drive, behind an explicit confirmation
  that names the destination.
- Verifies the write by reading the region back and comparing.

Both directions are ordinary block-level reads and writes. The app exists to
make the destination unambiguous, because the failure mode of doing this by
hand is destroying the wrong disk.

## Safety

Writing to a block device is destructive and not undoable. The app will not
offer internal or boot volumes as targets, and every write is confirmed against
a named destination. Even so: verify the disk identifier yourself before
confirming, and do not run this against a drive holding anything you care about.

## Requirements

- macOS 14 or later
- A USB NVMe enclosure or an M.2 slot to attach drives to

## Install

```bash
brew install --cask nspxmiguel/tap/torii
```

## Build from source

```bash
git clone https://github.com/NspxMiguel/torii.git
cd torii
./build.sh
```

## Credits

The original technique is not ours. Windfox found the behaviour,
flaviopenas-ps produced the practical trimmed image, and Bringus Studios
established that the capacity floor was not enforced. This repository exists so
that work is in one place instead of scattered across a Discord and a handful
of forum threads.

## License

MIT © 2026 NSPX
