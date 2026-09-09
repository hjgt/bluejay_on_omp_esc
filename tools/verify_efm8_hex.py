#!/usr/bin/env python3
"""Validate an Intel HEX image for the custom EFM8BB21 Bluejay target."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from typing import Iterable


FLASH_SIZE = 0x4000
DEFAULT_LAYOUT_TAG = b"#X_H_05#"
MCU_TAG = b"#BLHELI$EFM8B21#"


class HexError(ValueError):
    pass


def parse_intel_hex(lines: Iterable[str]) -> tuple[dict[int, int], bool]:
    memory: dict[int, int] = {}
    base_address = 0
    saw_eof = False

    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line:
            continue
        if saw_eof:
            raise HexError(f"line {line_number}: data found after EOF record")
        if not line.startswith(":"):
            raise HexError(f"line {line_number}: missing ':' prefix")
        try:
            record = bytes.fromhex(line[1:])
        except ValueError as exc:
            raise HexError(f"line {line_number}: invalid hexadecimal text") from exc
        if len(record) < 5:
            raise HexError(f"line {line_number}: record is too short")

        length = record[0]
        if len(record) != length + 5:
            raise HexError(
                f"line {line_number}: byte count says {length}, "
                f"record contains {len(record) - 5}"
            )
        if sum(record) & 0xFF:
            raise HexError(f"line {line_number}: checksum mismatch")

        offset = (record[1] << 8) | record[2]
        record_type = record[3]
        data = record[4:-1]

        if record_type == 0x00:
            absolute = base_address + offset
            for index, value in enumerate(data):
                address = absolute + index
                previous = memory.get(address)
                if previous is not None and previous != value:
                    raise HexError(
                        f"line {line_number}: conflicting data at 0x{address:04X}"
                    )
                memory[address] = value
        elif record_type == 0x01:
            if length != 0 or offset != 0:
                raise HexError(f"line {line_number}: malformed EOF record")
            saw_eof = True
        elif record_type == 0x02:
            if length != 2 or offset != 0:
                raise HexError(f"line {line_number}: malformed segment address record")
            base_address = int.from_bytes(data, "big") << 4
        elif record_type == 0x04:
            if length != 2 or offset != 0:
                raise HexError(f"line {line_number}: malformed linear address record")
            base_address = int.from_bytes(data, "big") << 16
        elif record_type in (0x03, 0x05):
            # Start-address records contain metadata and do not program flash.
            continue
        else:
            raise HexError(f"line {line_number}: unsupported record type 0x{record_type:02X}")

    return memory, saw_eof


def contiguous_flash(memory: dict[int, int], fill: int = 0xFF) -> bytes:
    return bytes(memory.get(address, fill) for address in range(FLASH_SIZE))


def validate_address_range(memory: dict[int, int]) -> None:
    outside = [address for address in memory if not 0 <= address < FLASH_SIZE]
    if outside:
        raise HexError(
            f"data outside EFM8BB21 16 KiB flash at 0x{min(outside):X}"
        )


def validate_firmware(memory: dict[int, int], expected_layout_tag: bytes) -> None:
    if not memory:
        raise HexError("firmware contains no data records")
    image = contiguous_flash(memory)
    if expected_layout_tag not in image:
        raise HexError(
            f"missing layout tag {expected_layout_tag.decode('ascii', errors='replace')!r}"
        )
    if MCU_TAG not in image:
        raise HexError(f"missing MCU tag {MCU_TAG.decode('ascii')!r}")
    if all(value == 0xFF for value in image[:16]):
        raise HexError("reset-vector area is blank")


def validate_full_backup(memory: dict[int, int]) -> None:
    missing = [address for address in range(FLASH_SIZE) if address not in memory]
    if missing:
        raise HexError(
            f"backup is incomplete: first missing address is 0x{missing[0]:04X}"
        )
    image = contiguous_flash(memory)
    if len(set(image)) == 1:
        raise HexError(f"backup is uniformly 0x{image[0]:02X}")


def load_hex(path: Path) -> tuple[bytes, dict[int, int]]:
    raw = path.read_bytes()
    try:
        text = raw.decode("ascii")
    except UnicodeError as exc:
        raise HexError(f"{path}: file is not ASCII Intel HEX") from exc
    memory, saw_eof = parse_intel_hex(text.splitlines())
    if not saw_eof:
        raise HexError(f"{path}: missing EOF record")
    validate_address_range(memory)
    return raw, memory


def compare_programmed(readback: dict[int, int], firmware: dict[int, int]) -> None:
    for address, expected in sorted(firmware.items()):
        actual = readback.get(address)
        if actual is None:
            raise HexError(f"readback is missing programmed address 0x{address:04X}")
        if actual != expected:
            raise HexError(
                f"readback mismatch at 0x{address:04X}: "
                f"expected 0x{expected:02X}, got 0x{actual:02X}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate Intel HEX checksums, addresses and Bluejay target tags."
    )
    parser.add_argument("hex_file", type=Path)
    parser.add_argument(
        "--full-backup",
        action="store_true",
        help="require a non-empty readback covering all 16 KiB",
    )
    parser.add_argument(
        "--layout-tag",
        default=DEFAULT_LAYOUT_TAG.decode("ascii"),
        help="expected Bluejay layout tag (default: #X_H_05#)",
    )
    parser.add_argument(
        "--compare-programmed",
        type=Path,
        metavar="FIRMWARE_HEX",
        help="compare every programmed firmware byte against this readback",
    )
    args = parser.parse_args()

    try:
        raw, memory = load_hex(args.hex_file)
        if args.full_backup:
            validate_full_backup(memory)
        else:
            validate_firmware(memory, args.layout_tag.encode("ascii"))
        if args.compare_programmed:
            _, firmware = load_hex(args.compare_programmed)
            validate_firmware(firmware, args.layout_tag.encode("ascii"))
            compare_programmed(memory, firmware)
    except (HexError, UnicodeError) as exc:
        parser.exit(1, f"ERROR: {exc}\n")

    digest = hashlib.sha256(raw).hexdigest()
    lowest = min(memory) if memory else 0
    highest = max(memory) if memory else 0
    mode = "full backup" if args.full_backup else "Bluejay firmware"
    print(f"OK: {mode}")
    print(f"Programmed/read bytes: {len(memory)}")
    print(f"Address range: 0x{lowest:04X}-0x{highest:04X}")
    if args.compare_programmed:
        print(f"Programmed-byte comparison: OK ({args.compare_programmed})")
    print(f"SHA-256: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
