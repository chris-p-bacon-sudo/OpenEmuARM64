#!/usr/bin/env python3
"""
Creates dark-background variants of the OpenEmu app icon PNGs.
Uses only Python stdlib (no Pillow required).
Dark background color: #1c1c1e (Apple's standard dark UI background)
"""
import struct
import zlib
import os


def read_png_chunks(filename):
    with open(filename, 'rb') as f:
        data = f.read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', f"Not a PNG: {filename}"
    chunks = []
    offset = 8
    while offset < len(data):
        length = struct.unpack('>I', data[offset:offset+4])[0]
        chunk_type = data[offset+4:offset+8]
        chunk_data = data[offset+8:offset+8+length]
        chunks.append((chunk_type, chunk_data))
        offset += 12 + length
    return chunks


def parse_ihdr(data):
    width = struct.unpack('>I', data[0:4])[0]
    height = struct.unpack('>I', data[4:8])[0]
    bit_depth = data[8]
    color_type = data[9]
    return width, height, bit_depth, color_type


def paeth_predictor(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    elif pb <= pc:
        return b
    return c


def defilter_rows(raw_data, width, height, bpp):
    scanline_size = 1 + width * bpp
    rows = []
    prev = bytearray(width * bpp)
    for y in range(height):
        base = y * scanline_size
        ftype = raw_data[base]
        raw = raw_data[base+1:base+scanline_size]
        recon = bytearray(len(raw))
        if ftype == 0:
            recon[:] = raw
        elif ftype == 1:
            for i in range(len(raw)):
                a = recon[i - bpp] if i >= bpp else 0
                recon[i] = (raw[i] + a) & 0xFF
        elif ftype == 2:
            for i in range(len(raw)):
                recon[i] = (raw[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(len(raw)):
                a = recon[i - bpp] if i >= bpp else 0
                b = prev[i]
                recon[i] = (raw[i] + (a + b) // 2) & 0xFF
        elif ftype == 4:
            for i in range(len(raw)):
                a = recon[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                recon[i] = (raw[i] + paeth_predictor(a, b, c)) & 0xFF
        else:
            raise ValueError(f"Unknown PNG filter type: {ftype}")
        rows.append(bytes(recon))
        prev = recon
    return rows


def make_chunk(chunk_type, data):
    crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
    return struct.pack('>I', len(data)) + chunk_type + data + struct.pack('>I', crc)


def encode_rgba_png(width, height, rgba_bytes):
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # None filter
        raw.extend(rgba_bytes[y * stride:(y + 1) * stride])
    compressed = zlib.compress(bytes(raw), 9)
    return (b'\x89PNG\r\n\x1a\n'
            + make_chunk(b'IHDR', ihdr)
            + make_chunk(b'IDAT', compressed)
            + make_chunk(b'IEND', b''))


def add_dark_background(input_path, output_path, bg=(0x1c, 0x1c, 0x1e)):
    chunks = read_png_chunks(input_path)
    ihdr_data = idat_buf = None
    idat_parts = []
    for ctype, cdata in chunks:
        if ctype == b'IHDR':
            ihdr_data = cdata
        elif ctype == b'IDAT':
            idat_parts.append(cdata)

    assert ihdr_data is not None
    width, height, bit_depth, color_type = parse_ihdr(ihdr_data)
    assert bit_depth == 8, f"Only 8-bit PNGs supported, got {bit_depth}"

    bpp = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    assert bpp is not None, f"Unsupported color type: {color_type}"

    raw_data = zlib.decompress(b''.join(idat_parts))
    rows = defilter_rows(raw_data, width, height, bpp)

    bg_r, bg_g, bg_b = bg
    out = bytearray(width * height * 4)
    for y, row in enumerate(rows):
        for x in range(width):
            if color_type == 6:    # RGBA
                r, g, b, a = row[x*4], row[x*4+1], row[x*4+2], row[x*4+3]
            elif color_type == 2:  # RGB
                r, g, b, a = row[x*3], row[x*3+1], row[x*3+2], 255
            elif color_type == 4:  # Grayscale+Alpha
                lum, a = row[x*2], row[x*2+1]
                r = g = b = lum
            else:                  # Grayscale
                r = g = b = row[x]; a = 255

            inv = 255 - a
            base = (y * width + x) * 4
            out[base]   = (r * a + bg_r * inv) // 255
            out[base+1] = (g * a + bg_g * inv) // 255
            out[base+2] = (b * a + bg_b * inv) // 255
            out[base+3] = 255

    with open(output_path, 'wb') as f:
        f.write(encode_rgba_png(width, height, bytes(out)))
    print(f"  Created: {os.path.basename(output_path)}")


ICON_DIR = os.path.join(os.path.dirname(__file__),
                        "OpenEmu/Graphics.xcassets/OpenEmu.appiconset")

ICONS = [
    "icon-16-srgb.png",
    "icon-16-p3.png",
    "icon-32-srgb.png",
    "icon-32-p3.png",
    "icon-64-srgb.png",
    "icon-64-p3.png",
    "icon-128-srgb.png",
    "icon-128-p3.png",
    "icon-256-srgb.png",
    "icon-256-p3.png",
    "icon-512-srgb.png",
    "icon-512-p3.png",
    "icon-1024-srgb.png",
    "icon-1024-p3.png",
]

if __name__ == '__main__':
    print("Generating dark-background icon variants...")
    for name in ICONS:
        src = os.path.join(ICON_DIR, name)
        dst = os.path.join(ICON_DIR, name.replace('.png', '-dark.png'))
        add_dark_background(src, dst)
    print("Done.")
