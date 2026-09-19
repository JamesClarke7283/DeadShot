extends SceneTree
## Dedicated native relay: godot --headless --path . --script scripts/server/relay_main.gd -- --port=8090
const Relay := preload("res://scripts/server/multiplayer_relay.gd")
var relay: Node

func _initialize() -> void:
	var port := 8090
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	relay = Relay.new()
	root.add_child(relay)
	var result: Error = relay.start(port)
	if result != OK:
		push_error("Could not listen on port %d: %s" % [port, error_string(result)])
		quit(1)
	else:
		print("DeadShot native relay listening on ws://0.0.0.0:%d/ws" % port)
