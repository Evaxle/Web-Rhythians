extends Node

enum ActivityType { Playing }

class ActivityAssets extends Reference:
	func set_large_image(_value): pass
	func set_large_text(_value): pass
	func set_small_image(_value): pass
	func set_small_text(_value): pass

class ActivityTimestamps extends Reference:
	func set_start(_value): pass
	func set_end(_value): pass

class ActivityParty extends Reference:
	func set_id(_value): pass

class Activity extends Reference:
	var _assets = ActivityAssets.new()
	var _timestamps = ActivityTimestamps.new()
	var _party = ActivityParty.new()
	func set_type(_value): pass
	func set_state(_value): pass
	func set_details(_value): pass
	func set_application_id(_value): pass
	func get_assets(): return _assets
	func get_timestamps(): return _timestamps
	func get_party(): return _party

class ActivityManager extends Reference:
	func update_activity(_activity): pass
	func clear_activity(): pass

var activity_manager = ActivityManager.new()
