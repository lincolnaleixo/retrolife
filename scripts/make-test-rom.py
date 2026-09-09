#!/usr/bin/env python3
"""Build an original minimal SNES LoROM fixture. No third-party game data.

The program sets a red backdrop, writes 0x42 into battery RAM and loops.
It exercises reset, video delivery and save persistence, not commercial-game
compatibility or audible output. Source and generated output: AGPL-3.0-only.
"""
from pathlib import Path
import sys

rom = bytearray([0xff] * 32768)
code = bytes.fromhex(
    '78 18 fb c2 10 a2 ff 1f 9a e2 20 '
    'a9 80 8d 00 21 a9 00 '
    '8d 2c 21 8d 2d 21 8d 2e 21 8d 2f 21 '
    '8d 30 21 8d 31 21 8d 33 21 8d 05 21 '
    '8d 21 21 '
    'a9 1f 8d 22 21 a9 00 8d 22 21 '
    'a9 42 8f 00 00 70 a9 0f 8d 00 21 80 fe'
)
rom[:len(code)] = code
rom[0x7fc0:0x7fd5] = b'RETROLIFE TEST       '[:21].ljust(21,b' ')
rom[0x7fd5:0x7fdc] = bytes([0x20, 0x02, 0x05, 0x01, 0x01, 0x00, 0x00])
for vector in (0x7fe4,0x7fe6,0x7fea,0x7fee,0x7ff4,0x7ffa,0x7ffc,0x7ffe):
    rom[vector:vector+2] = bytes([0,0x80])
rom[0x7fdc:0x7fe0] = bytes([0xff,0xff,0,0])
checksum=sum(rom)&0xffff
rom[0x7fdc:0x7fe0] = (checksum ^ 0xffff).to_bytes(2,'little') + checksum.to_bytes(2,'little')
output=Path(sys.argv[1] if len(sys.argv)>1 else '.cache/test.sfc')
output.parent.mkdir(parents=True,exist_ok=True)
output.write_bytes(rom)
print('Generated original 32 KiB test ROM')
