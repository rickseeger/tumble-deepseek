extends Node
## AudioManager -- G16 node 5 destruction-sound system (autoload singleton).
##
## Owns every generated WAV (16-bit mono 44.1 kHz) and plays it on the right
## game event. Samples are read straight off disk with FileAccess and wrapped in
## AudioStreamWAV at runtime, so there is NO Godot import step to run and no
## editor-generated .import metadata to commit -- the audio works from a fresh
## `git clone` in headless tests and in the real game alike.
##
## Public API (called from the weapon and the destruction module):
##   play_pew()                  -- crisp high-pitched weapon fire, per shot.
##   play_crash(weight, variety) -- rumbly crash/explosion scaled to a
##                                  structure's debris size (weight = total
##                                  debris mass in kg) and its block variety.
##   play_impact(mass)           -- light, short single-debris impact scaled to
##                                  that block's mass.
##
## Everything scales monotonically with size via pure static functions so tests
## can assert the mapping without any audio device:
##   tier_for_weight / pitch_for_weight / volume_for_weight / layers_for_variety
##
## Instrumentation (for the code-level wiring assertions): the `*_played`
## counters and the `last_*` values record every trigger, so the audio test can
## prove fire -> pew and shatter -> crash without listening to a single sample.

const SR := 44100

const PEW_PATHS: Array[String] = [
	"res://audio/pew_0.wav",
	"res://audio/pew_1.wav",
	"res://audio/pew_2.wav",
]
const CRASH_PATHS: Array[String] = [
	"res://audio/crash_small.wav",   # tier 0
	"res://audio/crash_medium.wav",  # tier 1
	"res://audio/crash_large.wav",   # tier 2
	"res://audio/crash_huge.wav",    # tier 3
]
const IMPACT_PATH := "res://audio/impact.wav"

# Size tiers, keyed on total debris mass (kg) reported by Godot's RigidBody3D.
const TIER_SMALL_KG := 1200.0
const TIER_MEDIUM_KG := 2400.0
const TIER_LARGE_KG := 4000.0

const POOL_SIZE := 12
const PEW_VOLUME_DB := -7.0

# Instrumentation -- the wiring test asserts on these.
var pew_played := 0
var crash_played := 0
var impact_played := 0
var last_crash_weight := 0.0
var last_crash_variety := 0
var last_impact_mass := 0.0

var _pew_streams: Array[AudioStreamWAV] = []
var _crash_streams: Array[AudioStreamWAV] = []
var _impact_stream: AudioStreamWAV = null
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0


func _ready() -> void:
	_load_streams()
	_build_pool()


# --- pure, testable size -> sound mapping ---------------------------------

static func tier_for_weight(weight: float) -> int:
	if weight < TIER_SMALL_KG:
		return 0
	if weight < TIER_MEDIUM_KG:
		return 1
	if weight < TIER_LARGE_KG:
		return 2
	return 3


## Bigger (heavier) => lower pitch => deeper, heavier sound.
static func pitch_for_weight(weight: float) -> float:
	return clampf(1.25 - 0.00008 * weight, 0.78, 1.25)


## Bigger => louder (dB, still negative to leave headroom for the rumble).
static func volume_for_weight(weight: float) -> float:
	return clampf(-9.0 + 6.0 * (weight / 4000.0), -10.0, 1.0)


## More distinct block sizes/shapes => more overlapping debris layers.
static func layers_for_variety(variety: int) -> int:
	if variety >= 10:
		return 2
	return 1


## Lighter single debris => higher pitch, shorter-feeling tap.
static func pitch_for_impact(mass: float) -> float:
	return clampf(1.5 - 0.02 * mass, 1.0, 1.5)


static func volume_for_impact(mass: float) -> float:
	return clampf(-14.0 + 8.0 * (mass / 30.0), -14.0, -2.0)


# --- trigger API ----------------------------------------------------------

func play_pew() -> void:
	pew_played += 1
	if _pew_streams.is_empty():
		return
	var p := _acquire()
	p.stream = _pew_streams[randi() % _pew_streams.size()]
	p.pitch_scale = randf_range(0.92, 1.08)
	p.volume_db = PEW_VOLUME_DB
	p.play()


func play_crash(weight: float, variety: int = 1) -> void:
	crash_played += 1
	last_crash_weight = weight
	last_crash_variety = variety
	if _crash_streams.is_empty():
		return
	var tier := tier_for_weight(weight)
	var layers := layers_for_variety(variety)
	for i in range(layers):
		var p := _acquire()
		p.stream = _crash_streams[tier]
		if i == 0:
			p.pitch_scale = pitch_for_weight(weight)
			p.volume_db = volume_for_weight(weight)
		else:
			# Extra variety layer: a higher, quieter "small debris" overtone.
			p.pitch_scale = pitch_for_weight(weight) * 1.5
			p.volume_db = volume_for_weight(weight) - 9.0
		p.play()


func play_impact(mass: float) -> void:
	impact_played += 1
	last_impact_mass = mass
	if _impact_stream == null:
		return
	var p := _acquire()
	p.stream = _impact_stream
	p.pitch_scale = pitch_for_impact(mass)
	p.volume_db = volume_for_impact(mass)
	p.play()


# --- loading / pool -------------------------------------------------------

func _load_streams() -> void:
	for path in PEW_PATHS:
		var s := _load_wav(path)
		if s != null:
			_pew_streams.append(s)
	for path in CRASH_PATHS:
		var s := _load_wav(path)
		if s != null:
			_crash_streams.append(s)
	_impact_stream = _load_wav(IMPACT_PATH)


func _build_pool() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "Sfx_%02d" % i
		add_child(p)
		_players.append(p)


func _acquire() -> AudioStreamPlayer:
	# Prefer an idle player so long crash tails are not cut off.
	for p in _players:
		if not p.playing:
			return p
	# All busy: steal the oldest (round-robin).
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	return p


# --- WAV loading (raw FileAccess, no import step) --------------------------

func _load_wav(path: String) -> AudioStreamWAV:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("audio: cannot open " + path)
		return null
	var buf := f.get_buffer(f.get_length())
	f.close()
	return _wav_from_bytes(buf)


static func _wav_from_bytes(buf: PackedByteArray) -> AudioStreamWAV:
	if buf.size() < 12 or _ascii(buf, 0, 4) != "RIFF" or _ascii(buf, 8, 4) != "WAVE":
		return null
	var pos := 12
	var fmt: Dictionary = {}
	var data := PackedByteArray()
	while pos + 8 <= buf.size():
		var cid := _ascii(buf, pos, 4)
		var csize := _le32(buf, pos + 4)
		pos += 8
		if cid == "fmt ":
			fmt = {
				"format": _le16(buf, pos),
				"channels": _le16(buf, pos + 2),
				"rate": _le32(buf, pos + 4),
				"bits": _le16(buf, pos + 14),
			}
		elif cid == "data":
			data = buf.slice(pos, pos + csize)
		pos += csize

	if data.is_empty() or fmt.is_empty() or int(fmt["bits"]) != 16:
		return null

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(fmt["rate"])
	stream.stereo = int(fmt["channels"]) == 2
	stream.data = data
	return stream


static func _ascii(buf: PackedByteArray, off: int, n: int) -> String:
	var s := ""
	for i in range(n):
		s += char(buf[off + i])
	return s


static func _le16(buf: PackedByteArray, off: int) -> int:
	return int(buf[off]) | (int(buf[off + 1]) << 8)


static func _le32(buf: PackedByteArray, off: int) -> int:
	return int(buf[off]) | (int(buf[off + 1]) << 8) | (int(buf[off + 2]) << 16) | (int(buf[off + 3]) << 24)
