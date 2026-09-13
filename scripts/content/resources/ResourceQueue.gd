extends Node

var pending = {}
var queue = []

func queue_resource(path, front=false):
	if pending.has(path): return OK
	var loader = ResourceLoader.load_interactive(path)
	if loader == null: return FAILED
	pending[path] = loader
	if front: queue.push_front(path)
	else: queue.append(path)
	return OK

func is_ready(path):
	return pending.has(path) and not pending[path] is ResourceInteractiveLoader

func get_progress(path):
	if not pending.has(path): return -1
	var value = pending[path]
	return float(value.get_stage()) / max(1, value.get_stage_count()) if value is ResourceInteractiveLoader else 1.0

func get_resource(path):
	if not pending.has(path): return load(path)
	var value = pending[path]
	if value is ResourceInteractiveLoader: return load(path)
	pending.erase(path)
	return value

func cancel_resource(path):
	queue.erase(path)
	pending.erase(path)

func _process(_delta):
	var until = OS.get_ticks_usec() + 4000
	while not queue.empty() and OS.get_ticks_usec() < until:
		var path = queue[0]
		var loader = pending[path]
		var result = loader.poll()
		if result != OK:
			pending[path] = loader.get_resource() if result == ERR_FILE_EOF else null
			queue.pop_front()
