#GDScriptAudioImport v0.1

#MIT License
#
#Copyright (c) 2020 Gianclgar (Giannino Clemente) gianclgar@gmail.com
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

#I honestly don't care that much, Kopimi ftw, but it's my little baby and I want it to look nice :3

extends Node
class_name AudioLoader

func report_errors(err, filepath):
	# See: https://docs.godotengine.org/en/latest/classes/class_@globalscope.html#enum-globalscope-error
	var result_hash = {
		ERR_FILE_NOT_FOUND: "File: not found",
		ERR_FILE_BAD_DRIVE: "File: Bad drive error",
		ERR_FILE_BAD_PATH: "File: Bad path error.",
		ERR_FILE_NO_PERMISSION: "File: No permission error.",
		ERR_FILE_ALREADY_IN_USE: "File: Already in use error.",
		ERR_FILE_CANT_OPEN: "File: Can't open error.",
		ERR_FILE_CANT_WRITE: "File: Can't write error.",
		ERR_FILE_CANT_READ: "File: Can't read error.",
		ERR_FILE_UNRECOGNIZED: "File: Unrecognized error.",
		ERR_FILE_CORRUPT: "File: Corrupt error.",
		ERR_FILE_MISSING_DEPENDENCIES: "File: Missing dependencies error.",
		ERR_FILE_EOF: "File: End of file (EOF) error."
	}
	if err in result_hash:
		print("Error: ", result_hash[err], " ", filepath)
	else:
		print("Unknown error with file ", filepath, " error code: ", err)

func get_format(bytes:PoolByteArray) -> String:
	if bytes.size() < 12: return "unknown"
	# Figure out file format from signatures
	# https://en.wikipedia.org/wiki/List_of_file_signatures
	
#	print(bytes.subarray(0,3).hex_encode())
	
	# .ogg
	if bytes.subarray(0,3) == PoolByteArray([0x4F,0x67,0x67,0x53]): return "ogg"
	if bytes.subarray(0,3) == PoolByteArray([82,73,70,70]) and bytes.subarray(8,11) == PoolByteArray([87,65,86,69]): return "wav"
	# .mp3
	if (bytes.subarray(0,1) == PoolByteArray([0xFF,0xFB])
	or bytes.subarray(0,1) == PoolByteArray([0xFF,0xF3])
	or bytes.subarray(0,1) == PoolByteArray([0xFF,0xFA])
	or bytes.subarray(0,1) == PoolByteArray([0xFF,0xF2])
	or bytes.subarray(0,2) == PoolByteArray([0x49,0x44,0x33])): return "mp3"
	# unsupported
	return "unknown"

func load_buffer(bytes:PoolByteArray,loop:bool=false):
	var format = get_format(bytes)
	
	# if File is wav
	if format == "wav":
		var reader = StreamPeerBuffer.new()
		reader.data_array = bytes
		reader.big_endian = false
		reader.seek(12)
		var channels = 0
		var rate = 0
		var bits = 0
		var pcm = PoolByteArray()
		while reader.get_position() + 8 <= bytes.size():
			var tag = reader.get_data(4)[1].get_string_from_ascii()
			var size = reader.get_u32()
			var start = reader.get_position()
			if size > bytes.size() - start: return null
			if tag == "fmt ":
				if size < 16 or reader.get_u16() != 1: return null
				channels = reader.get_u16()
				rate = reader.get_u32()
				reader.get_u32()
				reader.get_u16()
				bits = reader.get_u16()
			elif tag == "data": pcm = reader.get_data(size)[1]
			reader.seek(min(bytes.size(), start + size + size % 2))
		if not channels in [1, 2] or not bits in [8, 16] or rate <= 0 or pcm.empty(): return null
		if bits == 8:
			for i in pcm.size(): pcm[i] = (int(pcm[i]) + 128) % 256
		var stream = AudioStreamSample.new()
		stream.format = AudioStreamSample.FORMAT_16_BITS if bits == 16 else AudioStreamSample.FORMAT_8_BITS
		stream.mix_rate = rate
		stream.stereo = channels == 2
		stream.data = pcm
		return stream
	elif format == "ogg":
		var newstream = AudioStreamOGGVorbis.new()
		newstream.loop = loop #set to false or delete this line if you don't want to loop
		newstream.data = bytes
		return newstream

	#if file is mp3
	elif format == "mp3":
		var newstream = AudioStreamMP3.new()
		newstream.loop = loop #set to false or delete this line if you don't want to loop
		newstream.data = bytes
		return newstream

	else:
		print("ERROR: Unknown filetype or format")
		push_error("Unknown filetype or format!")
		return Globals.error_sound

func load_file(filepath:String,loop:bool=false):
	var file = File.new()
	var err = file.open(Globals.p(filepath), File.READ)
	if err != OK:
		report_errors(err, Globals.p(filepath))
		file.close()
		return Globals.error_sound
	
	var bytes:PoolByteArray = file.get_buffer(file.get_len())
	file.close()
	return load_buffer(bytes,loop)

# Converts .wav data from 24 or 32 bits to 16
#
# These conversions are SLOW in GDScript
# on my one test song, 32 -> 16 was around 3x slower than 24 -> 16
#
# I couldn't get threads to help very much
# They made the 24bit case about 2x faster in my test file
# And the 32bit case abour 50% slower
# I don't wanna risk it always being slower on other files
# And really, the solution would be to handle it in a low-level language
func convert_to_16bit(data: PoolByteArray, from: int) -> PoolByteArray:
	print("converting to 16-bit from %d" % from)
	var time = OS.get_ticks_msec()
	# 24 bit .wav's are typically stored as integers
	# so we just grab the 2 most significant bytes and ignore the other
	if from == 24:
		var j = 0
		for i in range(0, data.size(), 3):
			data[j] = data[i+1]
			data[j+1] = data[i+2]
			j += 2
		data.resize(data.size() * 2 / 3)
	# 32 bit .wav's are typically stored as floating point numbers
	# so we need to grab all 4 bytes and interpret them as a float first
	if from == 32:
		var spb := StreamPeerBuffer.new()
		var single_float: float
		var value: int
		for i in range(0, data.size(), 4):
			spb.data_array = data.subarray(i, i+3)
			single_float = spb.get_float()
			value = single_float * 32768
			data[i/2] = value
			data[i/2+1] = value >> 8
		data.resize(data.size() / 2)
	print("Took %f seconds for slow conversion" % ((OS.get_ticks_msec() - time) / 1000.0))
	return data


# ---------- REFERENCE ---------------
# note: typical values doesn't always match

#Positions  Typical Value Description
#
#1 - 4      "RIFF"        Marks the file as a RIFF multimedia file.
#                         Characters are each 1 byte long.
#
#5 - 8      (integer)     The overall file size in bytes (32-bit integer)
#                         minus 8 bytes. Typically, you'd fill this in after
#                         file creation is complete.
#
#9 - 12     "WAVE"        RIFF file format header. For our purposes, it
#                         always equals "WAVE".
#
#13-16      "fmt "        Format sub-chunk marker. Includes trailing null.
#
#17-20      16            Length of the rest of the format sub-chunk below.
#
#21-22      1             Audio format code, a 2 byte (16 bit) integer. 
#                         1 = PCM (pulse code modulation).
#
#23-24      2             Number of channels as a 2 byte (16 bit) integer.
#                         1 = mono, 2 = stereo, etc.
#
#25-28      44100         Sample rate as a 4 byte (32 bit) integer. Common
#                         values are 44100 (CD), 48000 (DAT). Sample rate =
#                         number of samples per second, or Hertz.
#
#29-32      176400        (SampleRate * BitsPerSample * Channels) / 8
#                         This is the Byte rate.
#
#33-34      4             (BitsPerSample * Channels) / 8
#                         1 = 8 bit mono, 2 = 8 bit stereo or 16 bit mono, 4
#                         = 16 bit stereo.
#
#35-36      16            Bits per sample. 
#
#37-40      "data"        Data sub-chunk header. Marks the beginning of the
#                         raw data section.
#
#41-44      (integer)     The number of bytes of the data section below this
#                         point. Also equal to (#ofSamples * #ofChannels *
#                         BitsPerSample) / 8
#
#45+                      The raw audio data.            
