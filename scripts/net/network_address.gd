extends RefCounted
## Connection URLs and shareable IPv4 endpoints for the native lobby.
const DEFAULT_PORT := 8090

static func normalize_url(value: String) -> String:
	var url := value.strip_edges()
	if url.is_empty():
		return "ws://127.0.0.1:8090/ws"
	if not url.contains("://"):
		if url.is_valid_ip_address() and url.contains(":"):
			url = "[%s]:%d" % [url, DEFAULT_PORT]
		elif not url.get_slice("/", 0).contains(":"):
			var server := url.get_slice("/", 0)
			url = server + ":%d" % DEFAULT_PORT + url.substr(server.length())
		url = "ws://" + url
	if not url.get_slice("://", 1).contains("/"):
		url += "/ws"
	return url

static func authority(url: String) -> String:
	return normalize_url(url).get_slice("://", 1).get_slice("/", 0)

static func host(url: String) -> String:
	var address := authority(url)
	if address.begins_with("["):
		return address.get_slice("]", 0).trim_prefix("[")
	return address.get_slice(":", 0)

static func port(url: String) -> int:
	var address := authority(url)
	var suffix := ""
	if address.begins_with("["):
		var closing := address.find("]")
		if closing < 0:
			return -1
		var remainder := address.substr(closing + 1)
		if not remainder.is_empty() and not remainder.begins_with(":"):
			return -1
		suffix = remainder.trim_prefix(":")
	elif address.contains(":"):
		suffix = address.get_slice(":", 1)
	if address.ends_with(":"):
		return -1
	if suffix.is_empty():
		return 443 if url.begins_with("wss://") else 80
	return int(suffix) if suffix.is_valid_int() and int(suffix) >= 1 and int(suffix) <= 65535 else -1

static func endpoint(url: String) -> String:
	var hostname := host(url)
	if hostname.contains(":"):
		hostname = "[%s]" % hostname
	return "%s:%d" % [hostname, port(normalize_url(url))]

static func connection_url(url: String) -> String:
	# Wildcards are listening addresses, never destinations to share or dial.
	return normalize_url(url).replace("://0.0.0.0", "://127.0.0.1").replace("://[::]", "://[::1]")

static func is_local(hostname: String) -> bool:
	return hostname in ["localhost", "127.0.0.1", "0.0.0.0", "::", "::1"] or hostname in IP.get_local_addresses()

static func share_endpoints(listen_port: int, interfaces: Array) -> Array[String]:
	var candidates: Array = []
	for interface in interfaces:
		var name := (str(interface.get("name", "")) + " " + str(interface.get("friendly", ""))).to_lower()
		var virtual := false
		for tag in ["docker", "veth", "virbr", "vbox", "vmware", "loopback", "tailscale", "tun", "tap", "bridge"]:
			if name.contains(tag):
				virtual = true
		for value in interface.get("addresses", []):
			var address := str(value)
			if not address.is_valid_ip_address() or address.contains(":") or address.begins_with("127.") or address.begins_with("169.254.") or address == "0.0.0.0":
				continue
			var octets := address.split(".")
			if int(octets[0]) >= 224:
				continue
			var private := address.begins_with("10.") or address.begins_with("192.168.") or (octets[0] == "172" and int(octets[1]) >= 16 and int(octets[1]) <= 31)
			candidates.append({"address": address, "rank": (100 if private else 80) - (50 if virtual else 0)})
	candidates.sort_custom(func(a, b): return a.rank > b.rank if a.rank != b.rank else a.address < b.address)
	var result: Array[String] = []
	for candidate in candidates:
		var address := "%s:%d" % [candidate.address, listen_port]
		if not result.has(address):
			result.append(address)
	if result.is_empty():
		result.append("127.0.0.1:%d" % listen_port)
	return result
