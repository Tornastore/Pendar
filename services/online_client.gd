extends RefCounted
## Thin WebSocket transport for online matchmaking.
## Queue policy, match state, and game actions intentionally remain in main.gd.

var _socket: WebSocketPeer


func connect_to_url(endpoint: String) -> Error:
	close()
	_socket = WebSocketPeer.new()
	var error: Error = _socket.connect_to_url(endpoint)
	if error != OK:
		_socket = null
	return error


func has_socket() -> bool:
	return _socket != null


func is_open() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func is_closed() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED


func poll() -> void:
	if _socket != null:
		_socket.poll()


func send_json(payload: Dictionary) -> bool:
	if not is_open():
		return false
	return _socket.send_text(JSON.stringify(payload)) == OK


func has_available_packets() -> bool:
	return _socket != null and _socket.get_available_packet_count() > 0


func receive_next_message() -> Variant:
	if not has_available_packets():
		return null
	var packet_text: String = _socket.get_packet().get_string_from_utf8()
	return JSON.parse_string(packet_text)


func close() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
