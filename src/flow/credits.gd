extends RefCounted
## The authors of the game's outside sources for the credits page of the main
## menu, read at run time from the files CREDITS.* beside the sources under
## assets/ (docs/ASSETS.md, «Лицензии»). A folder with .gdignore is not part
## of the game and is passed by. The texts stay as their files have them, in
## English; Markdown loses its marks (plain).

const ROOT := "res://assets"
const NAME := "CREDITS."

## The files CREDITS.* under `root`, sorted by path.
static func files(root := ROOT) -> Array[String]:
	var found: Array[String] = []
	if FileAccess.file_exists(root.path_join(".gdignore")):
		return found
	for file: String in DirAccess.get_files_at(root):
		if file.begins_with(NAME):
			found.append(root.path_join(file))
	for folder: String in DirAccess.get_directories_at(root):
		found.append_array(files(root.path_join(folder)))
	found.sort()
	return found

## One entry for each file of files(): {folder: its folder under `root`,
## text: its text without Markdown}. An empty file gives no entry.
static func read(root := ROOT) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for path: String in files(root):
		var text := plain(FileAccess.get_file_as_string(path))
		if not text.is_empty():
			entries.append({"folder": path.get_base_dir().trim_prefix(root).trim_prefix("/"), "text": text})
	return entries

## `markdown` as plain lines: headings without "#", table rows as cells
## joined by " · " (the row of dashes goes), links as "text (address)",
## no "**" or "`". Plain text keeps its lines.
static func plain(markdown: String) -> String:
	var link := RegEx.create_from_string("\\[([^\\]]*)\\]\\(([^)]*)\\)")
	var lines := PackedStringArray()
	for raw: String in markdown.replace("\r", "").split("\n"):
		var line := raw.strip_edges(false, true)
		if line.begins_with("#"):
			line = line.lstrip("#").strip_edges()
		elif line.begins_with("|"):
			var cells := PackedStringArray()
			for cell: String in line.trim_prefix("|").trim_suffix("|").split("|"):
				cells.append(cell.strip_edges())
			if "".join(cells).replace("-", "").replace(":", "").strip_edges().is_empty():
				continue
			line = " · ".join(cells)
		line = link.sub(line, "$1 ($2)", true).replace("**", "").replace("`", "")
		lines.append(line)
	return "\n".join(lines).strip_edges()
