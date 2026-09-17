#!/usr/bin/env python3
"""
rbxl_script_extractor.py

Extracts every Script / LocalScript / ModuleScript from a Roblox binary
place file (.rbxl) directly, without Roblox Studio, Rojo, Lune, or the
Roblox Command Bar.

Usage:
    python3 rbxl_script_extractor.py input.rbxl output_folder/

Dependencies:
    pip install lz4

--------------------------------------------------------------------------
FORMAT NOTES (why this needed custom code)

The .rbxl binary format is:

  Header (32 bytes):
    8 bytes  "<roblox!"
    6 bytes  magic  89 FF 0D 0A 1A 0A
    2 bytes  version (u16 LE)
    4 bytes  class count (u32 LE)
    4 bytes  instance count (u32 LE)
    8 bytes  reserved

  Then a sequence of chunks until an "END\0" chunk:
    4 bytes  chunk name  ("SSTR","INST","PROP","PRNT","END\0", ...)
    4 bytes  compressed length   (u32 LE) -- 0 means chunk is stored raw
    4 bytes  uncompressed length (u32 LE)
    4 bytes  reserved
    N bytes  chunk body, LZ4-**block**-compressed (no LZ4 frame header)

Chunk bodies of interest:

  INST -- declares one Roblox class: a class index, class name, an
          "object format" byte, an instance count, and then an array of
          instance IDs ("referents") belonging to that class.

  PROP -- one property (e.g. "Name", "Source") for every instance of one
          class, in the same order as that class's referent array.

  PRNT -- the parent/child graph for literally every instance in the
          place, as two parallel referent arrays (children, parents).

  Referent arrays (used in both INST and PRNT) are NOT stored as plain
  little/big-endian ints. Each array of N 32-bit integers is stored as:

    1. A "byte-plane" transpose: instead of the 4 bytes of every int
       being contiguous, the arrays are stored as
         [byte0 of every element][byte1 of every element]
         [byte2 of every element][byte3 of every element]
       reassembled big-endian per element.

    2. Each resulting 32-bit word is zigzag-decoded:
         zigzag_decode(v) = (v >> 1) ^ (-(v & 1))   (v treated as u32)

    3. The zigzag-decoded values are deltas: the actual referent value
       is a running sum (mod 2^32, reinterpreted as signed) of these
       deltas, reset to 0 at the start of every INST/PRNT array.

  This encoding isn't documented in any general-purpose zip/LZ4 tool,
  so it had to be reverse engineered and reimplemented (see
  `read_referents` below) by brute-forcing byte-plane orderings /
  zigzag vs. plain-delta combinations against known invariants (e.g.
  "every instance must appear as a child exactly once in PRNT, and the
  referent sets from INST and PRNT must be identical").

  In this particular file, "Name" and "Source" are stored as plain
  String properties (type tag 0x01: u32 length + raw bytes) -- no
  SharedString/dedup indirection was needed here, but the code checks
  the type tag and warns if it ever encounters something else.
--------------------------------------------------------------------------
"""

import sys
import os
import re
import struct
import json
from collections import Counter

import lz4.block


# ---------------------------------------------------------------------------
# Low-level integer / referent decoding
# ---------------------------------------------------------------------------

def zigzag_decode(v: int) -> int:
    """Decode a zigzag-encoded value (v is a raw u32)."""
    uv = v & 0xFFFFFFFF
    return (uv >> 1) ^ (-(uv & 1))


def assemble_be(buf: bytes, n: int):
    """
    Reassemble n big-endian 32-bit words from a byte-plane-transposed
    buffer of length n*4: plane0 (MSB of every element), plane1, plane2,
    plane3 (LSB of every element), each of length n.
    """
    out = [0] * n
    for i in range(n):
        b0 = buf[i]
        b1 = buf[n + i]
        b2 = buf[2 * n + i]
        b3 = buf[3 * n + i]
        out[i] = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    return out


def read_referents(buf: bytes, n: int):
    """
    Decode an interleaved + zigzag + running-delta referent array
    (used for INST instance-ID lists and PRNT child/parent lists).
    """
    raw = assemble_be(buf, n)
    deltas = [zigzag_decode(v) for v in raw]
    out = [0] * n
    last = 0
    for i in range(n):
        last = (last + deltas[i]) & 0xFFFFFFFF
        out[i] = last - 0x100000000 if last >= 0x80000000 else last
    return out


# ---------------------------------------------------------------------------
# Byte-stream reader
# ---------------------------------------------------------------------------

class Reader:
    def __init__(self, b: bytes):
        self.b = b
        self.p = 0

    def read(self, n: int) -> bytes:
        r = self.b[self.p:self.p + n]
        self.p += n
        return r

    def u8(self) -> int:
        v = self.b[self.p]
        self.p += 1
        return v

    def u32(self) -> int:
        v = struct.unpack_from('<I', self.b, self.p)[0]
        self.p += 4
        return v

    def string(self) -> bytes:
        length = self.u32()
        return self.read(length)

    def remaining(self) -> int:
        return len(self.b) - self.p

    def eof(self) -> bool:
        return self.p >= len(self.b)


# ---------------------------------------------------------------------------
# Chunk-level parsing
# ---------------------------------------------------------------------------

def parse_chunks(path: str):
    with open(path, 'rb') as f:
        data = f.read()

    assert data[0:8] == b'<roblox!', "Not a Roblox binary place file"
    assert data[8:14] == b'\x89\xff\x0d\x0a\x1a\x0a', "Bad magic bytes"

    version = struct.unpack('<H', data[14:16])[0]
    class_count = struct.unpack('<I', data[16:20])[0]
    instance_count = struct.unpack('<I', data[20:24])[0]

    pos = 32
    chunks = []
    while pos < len(data):
        name = data[pos:pos + 4]
        complen, uncomplen, _reserved = struct.unpack('<III', data[pos + 4:pos + 16])
        body_start = pos + 16
        if complen == 0:
            raw = data[body_start:body_start + uncomplen]
        else:
            comp = data[body_start:body_start + complen]
            raw = lz4.block.decompress(comp, uncompressed_size=uncomplen)
        chunks.append((name, raw))
        pos = body_start + (complen if complen > 0 else uncomplen)
        if name == b'END\x00':
            break

    return dict(version=version, class_count=class_count,
                instance_count=instance_count, chunks=chunks)


def read_string_array(r: Reader, n: int):
    out = []
    for _ in range(n):
        length = r.u32()
        out.append(r.read(length))
    return out


# ---------------------------------------------------------------------------
# High-level extraction
# ---------------------------------------------------------------------------

EXT_MAP = {
    'Script': '.server.luau',
    'LocalScript': '.client.luau',
    'ModuleScript': '.luau',
}


def sanitize(name: str) -> str:
    name = name.strip()
    if not name:
        return "Unnamed"
    name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', name)
    name = name.rstrip('. ')
    return name or "Unnamed"


def extract(rbxl_path: str, out_dir: str):
    info = parse_chunks(rbxl_path)
    chunks = info['chunks']
    instance_count = info['instance_count']

    # ---- INST: classIndex -> className, classIndex -> [referents] ----
    classes_by_index = {}
    class_referents = {}
    refid_to_class = {}

    for name, raw in chunks:
        if name != b'INST':
            continue
        r = Reader(raw)
        class_index = r.u32()
        class_name = r.string().decode('utf-8')
        object_format = r.u8()
        num_instances = r.u32()
        refbuf = r.read(num_instances * 4)
        refs = read_referents(refbuf, num_instances)
        if object_format == 1:
            r.read(num_instances)  # per-instance "isService" flags, unused here
        classes_by_index[class_index] = class_name
        class_referents[class_index] = refs
        for rid in refs:
            refid_to_class[rid] = class_name

    # ---- PRNT: refid -> parent refid (root/service-level = -1) ----
    refid_to_parent = {}
    for name, raw in chunks:
        if name != b'PRNT':
            continue
        r = Reader(raw)
        _version = r.u8()
        num_items = r.u32()
        children = read_referents(r.read(num_items * 4), num_items)
        parents = read_referents(r.read(num_items * 4), num_items)
        for c, p in zip(children, parents):
            refid_to_parent[c] = p
        break  # only one PRNT chunk in practice

    # ---- PROP: Name (every class) + Source (script classes) ----
    refid_to_name = {}
    refid_to_source = {}

    for name, raw in chunks:
        if name != b'PROP':
            continue
        r = Reader(raw)
        class_index = r.u32()
        prop_name = r.string().decode('utf-8', errors='replace')
        dtype = r.u8()
        if prop_name not in ('Name', 'Source'):
            continue
        if dtype != 0x1:  # String
            print(f"WARNING: unexpected type tag {hex(dtype)} for "
                  f"property '{prop_name}' on class "
                  f"{classes_by_index.get(class_index)!r} -- skipping",
                  file=sys.stderr)
            continue
        refs = class_referents.get(class_index, [])
        values = read_string_array(r, len(refs))
        if not r.eof():
            print(f"WARNING: {r.remaining()} leftover bytes parsing "
                  f"'{prop_name}' for class "
                  f"{classes_by_index.get(class_index)!r}", file=sys.stderr)
        for rid, v in zip(refs, values):
            if prop_name == 'Name':
                refid_to_name[rid] = v
            else:
                refid_to_source[rid] = v

    # ---- Build hierarchy paths for every script instance ----
    def get_name(rid: int) -> str:
        raw = refid_to_name.get(rid)
        if raw is None:
            return f"Unnamed_{rid}"
        try:
            return raw.decode('utf-8')
        except UnicodeDecodeError:
            return raw.decode('utf-8', errors='replace')

    def build_path_parts(rid: int):
        parts = []
        cur = rid
        seen = set()
        while True:
            if cur in seen:
                raise RuntimeError(f"Cycle detected at referent {cur}")
            seen.add(cur)
            parts.append(sanitize(get_name(cur)))
            parent = refid_to_parent.get(cur, -1)
            if parent == -1 or parent not in refid_to_class:
                break
            cur = parent
        parts.reverse()
        return parts

    script_entries = []
    for rid, class_name in refid_to_class.items():
        if class_name in EXT_MAP:
            script_entries.append(dict(
                rid=rid,
                className=class_name,
                path_parts=build_path_parts(rid),
                source=refid_to_source.get(rid, b''),
            ))

    # ---- Resolve filename collisions among siblings ----
    used_paths = {}
    final_files = []
    for e in script_entries:
        dir_parts = e['path_parts'][:-1]
        leaf = e['path_parts'][-1]
        ext = EXT_MAP[e['className']]
        filename = leaf + ext
        rel_path = os.path.join(*dir_parts, filename) if dir_parts else filename
        if rel_path in used_paths:
            filename = f"{leaf}_{e['rid']}{ext}"
            rel_path = os.path.join(*dir_parts, filename) if dir_parts else filename
        used_paths[rel_path] = e['rid']
        final_files.append((rel_path, e))

    # ---- Write files ----
    os.makedirs(out_dir, exist_ok=True)
    manifest = []
    for rel_path, e in final_files:
        full_path = os.path.join(out_dir, rel_path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, 'wb') as f:
            f.write(e['source'])
        manifest.append(dict(path=rel_path, className=e['className'],
                              bytes=len(e['source'])))

    with open(os.path.join(out_dir, '_manifest.json'), 'w') as f:
        json.dump(manifest, f, indent=2)

    # ---- Verification / summary ----
    counts = Counter(e['className'] for e in script_entries)
    total_instances = sum(len(v) for v in class_referents.values())

    print(f"Instances declared in header : {instance_count}")
    print(f"Instances parsed from INST   : {total_instances}")
    print(f"Scripts extracted            : {len(final_files)}")
    for cls in ('Script', 'LocalScript', 'ModuleScript'):
        print(f"  {cls:<12}: {counts.get(cls, 0)}")
    print(f"Output written to            : {out_dir}")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.rbxl output_folder/", file=sys.stderr)
        sys.exit(1)
    extract(sys.argv[1], sys.argv[2])
