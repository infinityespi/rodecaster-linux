"""Patch RODECasterApp.exe 2.0.115 so its UI repaints under Wine.

Wine's IDXGIOutput::WaitForVBlank is a stub that always fails. The app is
built with JUCE 7.0.9, which only flushes deferred repaints when a VBlank
arrives, so under Wine nothing is redrawn after a window's first paint (black
pages, frozen progress bars, clicks with no visible effect).

JUCE's VBlank thread loop (at VA 0x140ff5060) calls WaitForVBlank and, on
failure, sleeps 1 ms and retries. This patch rewrites that failure branch to
Sleep(16) and then continue into the normal "VBlank happened" path, giving
~60 Hz repaints.

The patch is 30 bytes and contains no RØDE code. It only applies to the exact
2.0.115 binary: the original bytes are checked before anything is written.
Running it again on an already-patched file does nothing.

Usage: python3 patch_vblank.py RODECasterApp.exe
"""
import struct
import sys

VA = 0x140ff509d             # start of the failure branch
SUCCESS_PATH = 0x140ff5071   # "VBlank happened" path
SLEEP_IAT = 0x141dce4d8      # import address table entry for kernel32!Sleep
ORIG = bytes.fromhex("488b0d8c2d08024885c9750a8bcfff152794dd00eb088bd7ff15ad93dd00")


def file_offset(data, va):
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    optsz = struct.unpack_from("<H", data, pe + 20)[0]
    base = struct.unpack_from("<Q", data, pe + 24 + 24)[0]
    sec = pe + 24 + optsz
    rva = va - base
    for i in range(nsec):
        vsize, vaddr, rsize, roff = struct.unpack_from("<IIII", data, sec + 40 * i + 8)
        if vaddr <= rva < vaddr + rsize:
            return roff + rva - vaddr
    raise SystemExit("patch_vblank: address not found in the executable")


def build_patch():
    patch = bytearray()
    patch += b"\xb9\x10\x00\x00\x00"                                   # mov ecx, 16
    patch += b"\xff\x15" + struct.pack("<i", SLEEP_IAT - (VA + len(patch) + 6))  # call [Sleep]
    patch += b"\x31\xc0"                                               # xor eax, eax
    patch += b"\xeb" + struct.pack("<b", SUCCESS_PATH - (VA + len(patch) + 2))   # jmp success
    patch += b"\x90" * (len(ORIG) - len(patch))                        # nop padding
    return bytes(patch)


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    exe = sys.argv[1]
    data = bytearray(open(exe, "rb").read())
    off = file_offset(data, VA)
    current = bytes(data[off:off + len(ORIG)])
    patch = build_patch()
    if current == patch:
        print("patch_vblank: already patched")
        return
    if current != ORIG:
        raise SystemExit("patch_vblank: unexpected bytes - this is not RODECaster App 2.0.115")
    data[off:off + len(patch)] = patch
    open(exe, "wb").write(data)
    print("patch_vblank: patched")


if __name__ == "__main__":
    main()
