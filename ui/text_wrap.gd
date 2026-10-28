extends RefCounted
## Width-based line breaking for Persian and Latin UI text.
## Layout measurement and drawing both use the returned explicit newline structure.

static func _split_oversized_word(host, word: String, width: float, size: int, bold: bool) -> Array[String]:
	if host._txt_w(word, size, bold) <= width:
		return [word]
	var parts: Array[String] = []
	var current: String = ""
	for index in range(word.length()):
		var character: String = word.substr(index, 1)
		if not current.is_empty() and host._txt_w(current + character, size, bold) > width:
			parts.append(current)
			current = character
		else:
			current += character
	if not current.is_empty():
		parts.append(current)
	return parts if not parts.is_empty() else [word]


static func wrap(host, text: String, width: float, size: int, bold: bool = false, max_lines: int = 0) -> String:
	var lines: Array[String] = []
	var safe_width: float = maxf(1.0, width)
	for paragraph in text.split("\n", true):
		if paragraph.is_empty():
			lines.append("")
			continue
		var current: String = ""
		for word in paragraph.split(" ", false):
			var parts: Array[String] = _split_oversized_word(host, word, safe_width, size, bold)
			for part_index in range(parts.size()):
				var part: String = parts[part_index]
				var separator: String = " " if part_index == 0 and not current.is_empty() else ""
				var candidate: String = current + separator + part
				if current.is_empty() or host._txt_w(candidate, size, bold) <= safe_width:
					current = candidate
				else:
					lines.append(current)
					current = part
		lines.append(current)
	if lines.is_empty():
		lines.append("")
	if max_lines > 0 and lines.size() > max_lines:
		lines = lines.slice(0, max_lines)
	return "\n".join(lines)


static func line_count(wrapped: String) -> int:
	return wrapped.count("\n") + 1
