extends SceneTree

const REQUIRED_RESOURCES = [
	"res://default_bus_layout.tres",
	"res://default_env.tres",
	"res://localization/localization.en.translation",
	"res://localization/localization.fr.translation",
	"res://localization/localization.ja.translation",
	"res://localization/localization.pl.translation",
	"res://localization/localization.es.translation",
	"res://localization/localization.it.translation",
	"res://localization/localization.en.translation",
	"res://localization/localization.fr.translation",
	"res://localization/localization.ja.translation",
	"res://localization/localization.pl.translation",
	"res://localization/localization.es.translation",
	"res://localization/localization.it.translation",
	"res://scenes/init.tscn",
	"res://scenes/loaders/menuload.tscn",
	"res://scenes/loaders/songload.tscn",
	"res://scenes/menu/menu2.tscn",
	"res://scenes/menu/contentmgr.tscn",
	"res://scenes/song.tscn",
	"res://scripts/Rhythian.gd",
	"res://scripts/ui/menu/RhythiansPortal.gd",
	"res://scripts/network/BattleClient.gd",
	"res://scripts/network/ClipClient.gd",
	"res://assets/worlds/baseplate/baseplate.tscn",
	"res://assets/worlds/event_horizon/event_horizon.tscn",
	"res://assets/worlds/tri_tunnel/tri_tunnel.tscn",
	"res://assets/worlds/grid/grid.tscn",
	"res://assets/notefx/ripple/ripple.tscn",
	"res://assets/notefx/shards/shards.tscn",
	"res://assets/notefx/miss/miss.tscn",
	"res://assets/blocks/rounded.obj",
	"res://assets/blocks/default.obj",
	"res://assets/blocks/circle.obj",
	"res://assets/blocks/cube.obj",
	"res://assets/blocks/plane.obj",
	"res://assets/blocks/quad.tres",
	"res://assets/songs/MeteoricImpact.mp3",
	"res://assets/songs/Meganeko - Feral (osu! edit).mp3",
	"res://assets/songs/spamton_neo_mix_ex_wip.ogg"
]

const REQUIRED_FILES = [
	"res://assets/songs/built_in_maps.sspmr",
	"res://assets/songs/MeteoricImpact.txt",
	"res://assets/songs/meganeko - Feral.txt",
	"res://assets/songs/BigShot.txt"
]

func _init():
	var failures = 0
	for path in REQUIRED_RESOURCES:
		if not ResourceLoader.exists(path):
			print("PACK_MISSING_RESOURCE: ", path)
			failures += 1
	var file = File.new()
	for path in REQUIRED_FILES:
		if not file.file_exists(path):
			print("PACK_MISSING_FILE: ", path)
			failures += 1
	print("PACK_SMOKE_FAILURES=", failures)
	quit(failures)
