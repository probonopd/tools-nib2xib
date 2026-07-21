# nib2xib

nib2xib converts modern Apple NSKeyedArchiver-format `.nib` bundles (as produced by Xcode and Interface Builder) into human-readable/editable formats on GNUstep/Linux.

This tool is **based on** tools-nib2xib by Gregory John Casamento and the Free Software Foundation, which originally targeted OPENSTEP 4.2 typed-stream nibs. The current version adds support for NSKeyedArchiver-format nibs and produces two output formats:

- **XIB** — Apple's XML-based Interface Builder format, loadable by GNUstep's `NSNibLoading`.
- **UIPlist** — An OpenStep property list representation of the full archived object graph (see [UIPlistFormat.md](UIPlistFormat.md)).

## Building

### Prerequisites

- [GNUstep](http://gnustep.org) base library (`libgnustep-base`)
- GNUstep GUI library (`libgnustep-gui`)
- GNUstep Make (`gnustep-make`)

### Build

    source /usr/share/GNUstep/Makefiles/GNUstep.sh
    make

### Build and test

    make check

The test suite converts two real-world `.nib` files to both XIB and UIPlist, validates structural correctness, and checks determinism (same input → same output).

## Usage

    nib2xib input.nib output.xib
    nib2xib input.nib output.uiplist

The tool auto-detects the output format from the file extension.

### Input

A `.nib` bundle (directory) containing a `keyedobjects.nib` file — the NSKeyedArchiver-format XML archive produced by Apple's `ibtool` and Xcode.

### Output formats

| Extension | Format | Description |
|-----------|--------|-------------|
| `.xib`    | XML    | Apple Interface Builder document, loadable by GNUstep's `NSBundle +loadNibNamed:owner:topLevelObjects:` |
| `.uiplist`| OpenStep property list | Full archived object graph with `@oid` references. See [UIPlistFormat.md](UIPlistFormat.md) for the spec. |

## Architecture

nib2xib uses GNUstep's NSKeyedUnarchiver to decode the archive, then walks the live object graph via NSIBObjectData, NSWindowTemplate, and related AppKit classes. Format-specific writers serialize the graph:

- **XIB**: `NIBParser` → recursive `toXMLWithParser:` calls on each object category → `XMLDocument`
- **UIPlist**: `UIPlistWriter` reads the raw object/oid/name tables and emits sorted OpenStep property list output

## Files

| File | Purpose |
|------|---------|
| `NIBParser.h/.m` | NSKeyedArchiver decoder, oid/name table access, XML document generation |
| `NSIBObjectData.h/.m` | Accessors for the decoded IB object data |
| `NSWindowTemplate.h/.m` | Window serialization with recursive view hierarchy |
| `NSView_Additions.h/.m` | View hierarchy traversal with cycle detection |
| `NSMenuTemplate.h/.m` | Menu serialization |
| `NSCustomObject.h/.m` | Placeholder objects (File's Owner, etc.) |
| `UIPlistWriter.h/.m` | OpenStep property list output format |
| `XMLDocument.h/.m`, `XMLElement.h/.m`, `XMLNode.h/.m` | XML tree model used for XIB output |
| Various `*_Additions.h/.m` | Categories on AppKit classes for key extraction and serialization |
| `OidProvider.h` | Protocol for oid lookup abstraction |
| `nib2xib_main.m` | Tool entry point, format detection |
| `Tests/` | GNUstep-style test suite (run with `make check`) |

## License

GPL-3.0-or-later (see [COPYINGv3](COPYINGv3)).

New files (UIPlistWriter) are BSD-2-Clause OR GPL-3.0-or-later.
