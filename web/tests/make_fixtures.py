from pathlib import Path
import io
import math
import struct
import wave

root = Path(__file__).parent
root.mkdir(exist_ok=True)
stream = io.BytesIO()
with wave.open(stream, 'wb') as audio:
    audio.setparams((1, 2, 22050, 0, 'NONE', 'not compressed'))
    audio.writeframes(b''.join(struct.pack('<h', int(1200 * math.sin(2 * math.pi * 440 * i / 22050))) for i in range(6 * 22050)))
track = stream.getvalue()
notes = [(1000 * i, 1, 1) for i in range(1, 6)]
pack = struct.pack
v1 = b'SS+m' + pack('<HH', 1, 0) + b'web-test-v1\nBrowser Test V1\nWeb Rhythia Tests\n'
v1 += pack('<IIBBBQ', 5000, len(notes), 1, 0, 1, len(track)) + track
v1 += b''.join(pack('<IBBB', t, 0, x, y) for t, x, y in notes)
(root / 'v1.sspm').write_bytes(v1)
def text(value):
    value = value.encode()
    return pack('<H', len(value)) + value
v2 = bytearray(128)
v2[:6] = b'SS+m' + pack('<H', 2)
struct.pack_into('<III', v2, 0x1e, 5000, len(notes), len(notes))
v2[0x2a] = 1
v2[0x2d] = 1
v2 += text('web-test-v2') + text('Browser Test V2') + text('Test Tone') + pack('<H', 1) + text('Web Rhythia Tests') + pack('<H', 0)
definition_offset = len(v2)
v2 += bytes([1]) + text('ssp_note') + bytes([1, 7, 0])
audio_offset = len(v2)
v2 += track
marker_offset = len(v2)
v2 += b''.join(pack('<IBBBB', t, 0, 0, x, y) for t, x, y in notes)
struct.pack_into('<QQ', v2, 0x40, audio_offset, len(track))
struct.pack_into('<Q', v2, 0x60, definition_offset)
struct.pack_into('<Q', v2, 0x70, marker_offset)
struct.pack_into('<QQ', v2, 0x30, definition_offset - 2, 2)
(root / 'v2.sspm').write_bytes(v2)
(root / 'broken.sspm').write_bytes(b'SS+m\x02\x00' + bytes(16))
print(root)
