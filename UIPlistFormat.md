# UIPlist File Format Specification

**Version 1.0**

UIPlist is a **git-friendly, human-readable, diff-able** representation of the archived object graph inside an NSKeyedArchiver-format `.nib` bundle. It is produced by `nib2xib` when the output file has a `.uiplist` extension.

## Design goals

- **Git compatible** — Plain text, line-oriented. Diffs are meaningful and merges are possible. Store `.uiplist` files in version control alongside your source code.
- **Human readable** — Structure is immediately visible. Object IDs, class names, and key-value pairs are self-evident.
- **Diff-able** — Deterministic output (sorted keys, sorted object IDs) ensures that the same input always produces the same output. A change in the nib produces a minimal, focused diff.
- **Robust** — Only the original archive's keys are emitted; runtime ephemera (memory addresses, transient descriptions) are filtered out. The format is designed to parse cleanly even when individual values contain unusual characters.
- **GNUstep familiar** — Uses the OpenStep property list format (a.k.a. "old-style" or "ASCII" plist), which has been the native serialization format of GNUstep and OPENSTEP since the 1990s. GNUstep's `Foundation` library reads and writes it natively.

## Format

UIPlist uses the **OpenStep property list** format: line-oriented, with curly braces `{}` for dictionaries and parentheses `()` for arrays, and semicolons as statement terminators.

### MIME type

Not registered. Suggested: `text/x-uiplist`

### File extension

`.uiplist`

## Top-Level Structure

```
{
    objects = (
        {
            id = 1;
            isa = NSCustomObject;
            keys = {
                className = "NSApplication";
            };
        },
        {
            id = 2;
            isa = NSWindowTemplate;
            keys = {
                title = "Window";
                windowView = @3;
                ...
            };
        },
        ...
    );
}
```

The root is a dictionary with a single key `objects` whose value is an array of object entries.

## Object Entry

Each object in the `objects` array is a dictionary with three keys:

| Key   | Type      | Description |
|-------|-----------|-------------|
| `id`  | integer   | Unique object identifier within this file |
| `isa` | string    | The Objective-C class name of the object |
| `keys`| dictionary| Key-value pairs representing the object's archived properties |

### `id`

An integer that uniquely identifies the object within the file. IDs are assigned by the original NSKeyedArchiver and are preserved verbatim.

Object IDs are **not** guaranteed to be contiguous or in any particular order, but they are unique per file.

### `isa`

The Objective-C class name as a string (e.g., `NSWindowTemplate`, `NSCustomObject`, `NSView`).

### `keys`

A dictionary of key-value pairs representing the object's properties as stored in the archive. The types of values are:

| Value type   | Representation            | Example                    |
|-------------|---------------------------|----------------------------|
| object reference | `@` followed by the target object's `id`  | `@44`                    |
| string       | Double-quoted string      | `"Window"`                 |
| number       | Integer or floating-point | `1`, `3.14`                |
| boolean      | Not used (archives use integers) | —                    |
| data         | Hex-encoded `<>`          | `<00000000 00000000>`      |
| array        | Parentheses `()`          | `(1, 2, 3)`                |
| dictionary   | Curly braces `{}`         | `{key = value;}`           |
| NSRect/point/size | OpenStep format `{x,y,w,h}` | `"{x = 0; y = 0; width = 396; height = 254}"` |
| color        | OpenStep color string     | `"{ ColorSpace = \"NSCalibratedWhiteColorSpace\"; ... }"` |
| font         | Font descriptor string    | `"{NSFontNameAttribute = \"Helvetica\"; ...}"` |

## Object References

Object references use the syntax `@<id>` where `<id>` is the target object's integer identifier.

Example: `contentView = @3;` means the `contentView` property references the object with `id = 3`.

References always point to an object that exists in the same file's `objects` array.

## Key Sorting

Within each `keys` dictionary, keys are serialized in **sorted order** (ascending, case-sensitive via `compare:`). This guarantees deterministic output: the same `.nib` file always produces byte-identical `.uiplist` output.

Object entries in the `objects` array are sorted by their `id` in ascending order.

## Data Values

Arbitrary binary data (e.g., `NSArchiver`-encoded sub-archives, raw byte buffers) is serialized as a space-separated hex string enclosed in angle brackets:

```
compressionPriorities = "({GSIntrinsicContentSizePriority=ff}) <00000000 00000000>";
```

## Ephemeral Values

Runtime ephemeral values — in particular pointer/memory addresses from `-[NSObject description]` (e.g., `<NSButton: 0x55a7a9693008>`) — are filtered out of the output. Only values that were actually present in the original archive are included.

## Determinism

Given the same `.nib` input, `nib2xib` always produces byte-identical `.uiplist` output. This is ensured by:

1. Object ID sorting (entries sorted by id)
2. Key sorting within each object's `keys` dictionary
3. Consistent key selection (no runtime-dependent values)

## Example

Input: `DesktopPref.nib` (33 objects, 119 references)

Output structure:

```
{
    objects = (
        {
            id = 1;
            isa = NSCustomObject;
            keys = {
                className = "NSApplication";
            };
        },
        {
            id = 2;
            isa = NSWindowTemplate;
            keys = {
                title = "Window";
                ...
            };
        },
        ...
    );
}
```

## Comparison to XIB

| Aspect | UIPlist | XIB |
|--------|---------|-----|
| Format | OpenStep property list | XML |
| Object graph | Full, every archived object | Selective, only "understood" objects |
| Object IDs | Original archive oids (integers) | Formatted hex strings (e.g., `583-74-655`) |
| View hierarchy | Flat (references via `@oid`) | Hierarchical (nested XML elements) |
| Plugin metadata | Not included | Included (dependencies, plugIn, capability) |
| File size (DesktopPref.nib) | ~1664 lines | ~X lines |
| Deterministic | Yes | Yes (since v1.0) |
| Loadable by GNUstep | No (tool format) | Yes (`NSBundle loadNibNamed:`) |

## Limitations

- The format preserves all archived keys verbatim. Some keys contain private/internal implementation details of AppKit classes.
- Data values (`<>` hex blocks) are not decoded further; they remain opaque.
- The format does not include XIB-specific metadata (deployment target, tools version, plugin identifiers).
