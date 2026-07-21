# uiconvert

`uiconvert` converts between `.nib` bundles (Apple NSKeyedArchiver-format), `.xib` (Interface Builder XML), and `.uiplist` (git-friendly object graph dump) on GNUstep/Linux.

This tool is **based on** tools-nib2xib by Gregory John Casamento and the Free Software Foundation, which originally targeted OPENSTEP 4.2 typed-stream nibs. The current version adds NSKeyedArchiver support and multiple conversion directions.

## Supported conversions

| Direction | Description |
|-----------|-------------|
| `.nib` → `.xib` | Interface Builder XML, loadable by GNUstep's `NSNibLoading` |
| `.nib` → `.uiplist` | Git-friendly object graph dump (see [UIPlistFormat.md](UIPlistFormat.md)) |
| `.uiplist` → `.nib` | Reconstruct `.nib` bundle from `.uiplist` |

The direction is auto-detected from the file extensions.

## Building

### Prerequisites

- [GNUstep](http://gnustep.org) base + gui libraries
- GNUstep Make (`gnustep-make`)

### Build

    source /usr/share/GNUstep/Makefiles/GNUstep.sh
    make

### Test

    make check

The test suite converts two real-world `.nib` files through all supported directions, validates structural correctness, and checks determinism (same input → same output).

## Usage

    uiconvert input.nib output.xib
    uiconvert input.nib output.uiplist
    uiconvert input.uiplist output.nib

### Input

- `.nib`: a bundle (directory) containing `keyedobjects.nib` — the NSKeyedArchiver-format archive.
- `.uiplist`: an OpenStep property list file with `@oid` references.

## Architecture

`uiconvert` uses GNUstep's NSKeyedUnarchiver to decode `.nib` archives, then walks the live object graph via NSIBObjectData, NSWindowTemplate, and related AppKit classes:

- **XIB**: `NIBParser` → recursive `toXMLWithParser:` calls → `XMLDocument`
- **UIPlist (write)**: `UIPlistWriter` reads the object/oid/name tables and emits sorted OpenStep property list output
- **UIPlist (read)**: `UIPlistReader` parses the `.uiplist` format and reconstructs an NSKeyedArchiver XML archive

## Files

| File | Purpose |
|------|---------|
| `uiconvert_main.m` | Tool entry point, conversion direction detection |
| `NIBParser.h/.m` | NSKeyedArchiver decoder, oid/name table access, XIB generation |
| `NSIBObjectData.h/.m` | Accessors for the decoded IB object data |
| `UIPlistWriter.h/.m` | OpenStep property list output |
| `UIPlistReader.h/.m` | UIPlist → .nib reverse conversion |
| `NSWindowTemplate.h/.m` | Window serialization with view hierarchy |
| `NSView_Additions.h/.m` | View hierarchy with cycle detection |
| `NSMenuTemplate.h/.m` | Menu serialization |
| `NSCustomObject.h/.m` | Placeholder objects (File's Owner, etc.) |
| `XMLDocument.h/.m`, `XMLElement.h/.m`, `XMLNode.h/.m` | XML tree model for XIB output |
| Various `*_Additions.h/.m` | Categories on AppKit classes |
| `Tests/` | GNUstep-style test suite |

## License

GPL-3.0-or-later (see [COPYINGv3](COPYINGv3)).

New files (UIPlistWriter, UIPlistReader) are BSD-2-Clause OR GPL-3.0-or-later.
