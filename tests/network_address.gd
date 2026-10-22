extends SceneTree
const Address = preload("res://scripts/net/network_address.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	check(Address.normalize_url("192.168.1.20:9000") == "ws://192.168.1.20:9000/ws", "Pasted IP:port becomes a join URL")
	check(Address.normalize_url("192.168.1.20/ws") == "ws://192.168.1.20:8090/ws", "Bare IP uses the game port")
	check(Address.connection_url("ws://0.0.0.0:9000/ws") == "ws://127.0.0.1:9000/ws", "Host connects to loopback, not the bind wildcard")
	check(Address.endpoint("wss://example.org/lobby") == "example.org:443", "TLS default port is retained")
	check(Address.endpoint("ws://[::1]:9000/ws") == "[::1]:9000", "IPv6 authority retains brackets and port")
	check(Address.port("ws://localhost:99999") == -1 and Address.port("ws://localhost:bad") == -1, "Invalid ports are rejected")
	var interfaces := [
		{"name": "lo", "addresses": ["127.0.0.1", "::1"]},
		{"name": "docker0", "addresses": ["172.17.0.1"]},
		{"name": "wlan0", "addresses": ["192.168.1.20", "fe80::1", "169.254.2.3"]},
		{"name": "tun0", "addresses": ["10.20.0.1"]},
	]
	var addresses := Address.share_endpoints(9000, interfaces)
	check(addresses[0] == "192.168.1.20:9000", "Copy IP prefers the physical LAN address")
	check(not addresses.has("127.0.0.1:9000") and not addresses.has("0.0.0.0:9000"), "Wildcard and loopback are not shared when LAN is available")
	check(addresses.has("10.20.0.1:9000"), "VPN address remains selectable")
	check(Address.share_endpoints(9000, []).front() == "127.0.0.1:9000", "Offline host has an explicit loopback fallback")
	print("NETWORK ADDRESS: %s" % ("PASS" if failures.is_empty() else str(failures.size()) + " failures"))
	quit(0 if failures.is_empty() else 1)
