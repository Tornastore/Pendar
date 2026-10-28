extends RefCounted
## Width-based line breaking for long Persian text.
## Main._wrap() now wraps by words too; this helper remains useful when a screen needs a fixed line count.

## Returns `text` with "\n" inserted so that no line is wider than `width` pixels (measured with the host font).
static func wrap(host, text: String, width: float, size: int, bold: bool = false, max_lines: int = 0) -> String:
	var lines: Array[String] = []
	for paragraph in text.split("\n"):
		var current := ""
		for word in paragraph.split(" ", false):
			var candidate: String = word if current.is_empty() else current + " " + word
			if current.is_empty() or host._txt_w(candidate, size, bold) <= width:
				current = candidate
			else:
				lines.append(current)
				current = word
		lines.append(current)
	if max_lines > 0 and lines.size() > max_lines:
		lines = lines.slice(0, max_lines)
	return "\n".join(lines)


static func line_count(wrapped: String) -> int:
	return wrapped.count("\n") + 1
