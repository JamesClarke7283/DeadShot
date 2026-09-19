extends SceneTree
## Exercise the actual match integration over local WebSockets, beyond protocol
## dispatch: remote movement, owner damage, kill credit, bot ownership, respawn.
const Client = preload("res://scripts/net/net_client.gd")
const Relay = preload("res://scripts/server/multiplayer_relay.gd")
const Session = preload("res://scripts/game/match_session.gd")
var failures: Array[String] = []
var clients: Array = []
var matches: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func until(condition: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec()+3000
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	check(condition.call(),message)

func run() -> void:
	var relay = Relay.new()
	root.add_child(relay)
	var port := 22000+OS.get_process_id()%1000
	check(relay.start(port,"127.0.0.1")==OK,"Local relay starts")
	for i in 2:
		var client = Client.new()
		root.add_child(client)
		clients.append(client)
		client.connect_room("ws://127.0.0.1:%d/ws"%port,"MATCH","Host" if i==0 else "Guest")
		await until(func():return client.self_id>=0,"Client joins")
	await until(func():return clients[1].players.size()==2,"Both players in roster")
	var data = preload("res://scripts/core/game_data.gd")
	var save: Dictionary = data.table("default_save")
	for i in 2:
		var session = Session.new()
		root.add_child(session)
		session.network_client = clients[i]
		check(session.start({"mapId":"desert_town","mode":"tdm","botCount":1,"playerName":"Host" if i==0 else "Guest"},save.classes[0],save.settings),"Network match starts")
		session.state="live"
		matches.append(session)
	var host = matches[0]
	var guest = matches[1]
	check(host.player.actor_id==clients[0].self_id and guest.player.actor_id==clients[1].self_id,"Players use relay IDs")
	check(host.player.team=="blue" and guest.player.team=="red","Roster owns team assignment")
	check(host.actors.size()==3 and guest.actors.size()==2,"Only host creates simulated bot")
	host.player.position=Vector3(10,0,-4)
	guest.player.position=Vector3(-10,0,4)
	host.network.tick(0.05)
	guest.network.tick(0.05)
	await until(func():return guest.network.remotes.has(1000000),"Host bot appears as guest remote")
	await until(func():return guest.network.remotes[host.player.actor_id].has_snapshot,"Player snapshot arrives")
	var mirrored_host = guest.network.remotes[host.player.actor_id]
	check(mirrored_host.position.is_equal_approx(host.player.position),"First remote snapshot snaps to player")
	host.player.position.x=20
	host.network.tick(0.05)
	await until(func():return mirrored_host.target_position.x==20,"Second remote snapshot arrives")
	mirrored_host.tick(1.0/60)
	check(is_equal_approx(mirrored_host.position.x,12),"Subsequent snapshots interpolate at source rate")
	var mirrored_guest = host.network.remotes[guest.player.actor_id]
	mirrored_guest.apply_damage(40,host.player,"m4",true)
	check(mirrored_guest.health==100,"Local hit does not mutate remote health")
	await until(func():return guest.player.health==60,"Victim owner applies hit")
	mirrored_guest.apply_damage(60,host.player,"m4",true)
	await until(func():return not guest.player.alive and host.scores[host.player.actor_id].kills==1,"Death broadcast credits attacker")
	check(guest.scores[host.player.actor_id].kills==1 and host.scores[guest.player.actor_id].deaths==1,"Peers agree on one death and kill")
	check(not mirrored_guest.alive,"Remote death hides victim")
	check(host.streak_scores[host.player.actor_id]==125,"Remote kill credits headshot streak score once")
	guest.respawn_player_now()
	guest.network.tick(0.05)
	await until(func():return mirrored_guest.alive,"Owner respawn restores remote")
	var guest_bot = guest.network.remotes[1000000]
	guest_bot.apply_damage(100,guest.player,"m4",false)
	await until(func():return not host.network.actor_by_id(1000000).alive,"Guest hit reaches host-owned bot")
	await until(func():return guest.scores[guest.player.actor_id].kills==1,"Bot death relays kill credit")
	var departed: int = guest.player.actor_id
	clients[1].disconnect_room()
	await until(func():return not host.network.remotes.has(departed),"Departed peer removed from match")
	for session in matches:session.free()
	for client in clients:client.disconnect_room()
	for frame in 12:await process_frame
	for client in clients:client.free()
	relay.stop()
	relay.free()
	print("Network match integration: %s" % ("PASS" if failures.is_empty() else "%d failures" % failures.size()))
	quit(0 if failures.is_empty() else 1)
