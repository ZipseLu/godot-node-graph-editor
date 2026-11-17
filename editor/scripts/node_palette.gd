## Durchsuchbare Liste aller Node-Typen, nach Kategorie gruppiert.
## Wird links als Palette und im Hinzufügen-Menü (Rechtsklick/Leertaste) verwendet.
class_name NodePalette
extends VBoxContainer

signal type_activated(type: String)

## Zusätzliche Suchbegriffe, damit man Nodes auch unter anderen Wörtern findet.
const SYNONYMS := {
	"wait": "timer pause delay verzögerung sekunden",
	"countdown": "timer qte zeitdruck frist sekunden",
	"choice": "auswahl option qte antwort",
	"dialogue": "text sprechen satz zeile line",
	"branch": "if wenn falls condition",
	"compare": "if wenn gleich größer kleiner",
	"all_any": "und oder and or nicht not logik gatter",
	"set_var": "setzen erhöhen verringern zähler rechnen plus minus wert",
	"switch": "fall case",
	"expression": "code gdscript skript",
	"call_method": "funktion code skript aufruf",
	"emit_signal": "event ereignis kamera sound animation",
	"task_start": "ziel aufgabe quest objective",
	"task_complete": "ziel aufgabe quest erledigt",
	"task_wait": "ziel aufgabe quest parallel",
	"jump": "goto sprung",
	"label": "marke anker",
	"subgraph": "szene kapitel datei",
	"once": "erstes mal besucht",
	"random": "würfel chance wahrscheinlichkeit",
	"end": "ende ending schluss",
}

var search: LineEdit
var tree: Tree


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	search = LineEdit.new()
	search.placeholder_text = "Node suchen …  (z. B. dialog, timer, variable)"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _populate())
	search.text_submitted.connect(func(_t): _activate_selected())
	search.gui_input.connect(_on_search_input)
	add_child(search)

	tree = Tree.new()
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.select_mode = Tree.SELECT_ROW
	tree.item_activated.connect(_activate_selected)
	tree.set_drag_forwarding(_get_tree_drag_data, Callable(), Callable())
	add_child(tree)
	_populate()


func focus_search() -> void:
	search.text = ""
	_populate()
	search.grab_focus()


func _populate() -> void:
	tree.clear()
	var root := tree.create_item()
	var query := search.text.strip_edges().to_lower()
	var first: TreeItem = null
	for category in StoryNodeTypes.CATEGORIES:
		var cat: Dictionary = StoryNodeTypes.CATEGORIES[category]
		var types := StoryNodeTypes.types_in_category(category)
		var matches: Array[String] = []
		for t in types:
			var def := StoryNodeTypes.get_def(t)
			var haystack := ("%s %s %s %s %s" % [def["title"], cat["title"], t, SYNONYMS.get(t, ""), def.get("help", "")]).to_lower()
			if query == "" or query in haystack:
				matches.append(t)
		if matches.is_empty():
			continue
		var cat_item := tree.create_item(root)
		cat_item.set_text(0, cat["title"].to_upper())
		cat_item.set_custom_color(0, cat["color"].lightened(0.25))
		cat_item.set_selectable(0, false)
		cat_item.set_custom_font_size(0, 12)
		for t in matches:
			var def := StoryNodeTypes.get_def(t)
			var item := tree.create_item(cat_item)
			item.set_text(0, "   " + def["title"])
			item.set_icon(0, _dot(cat["color"]))
			item.set_tooltip_text(0, def.get("help", ""))
			item.set_metadata(0, t)
			if first == null:
				first = item
	if query != "" and first != null:
		first.select(0)
		tree.scroll_to_item(first)


func _activate_selected() -> void:
	var item := tree.get_selected()
	if item != null and item.get_metadata(0) != null:
		type_activated.emit(item.get_metadata(0))


func _on_search_input(e: InputEvent) -> void:
	# Pfeiltasten im Suchfeld bewegen die Auswahl in der Liste.
	if e is InputEventKey and e.pressed and e.keycode in [KEY_DOWN, KEY_UP]:
		var items := _selectable_items()
		if items.is_empty():
			return
		var current := items.find(tree.get_selected())
		var next := clampi(current + (1 if e.keycode == KEY_DOWN else -1), 0, items.size() - 1)
		items[next].select(0)
		tree.scroll_to_item(items[next])
		search.accept_event()


func _selectable_items() -> Array[TreeItem]:
	var result: Array[TreeItem] = []
	var cat := tree.get_root().get_first_child() if tree.get_root() else null
	while cat != null:
		var item := cat.get_first_child()
		while item != null:
			result.append(item)
			item = item.get_next()
		cat = cat.get_next()
	return result


func _get_tree_drag_data(at: Vector2) -> Variant:
	var item := tree.get_item_at_position(at)
	if item == null or item.get_metadata(0) == null:
		return null
	var t: String = item.get_metadata(0)
	var preview := Label.new()
	preview.text = "  ＋ " + StoryNodeTypes.get_def(t)["title"]
	tree.set_drag_preview(preview)
	return {"story_node_type": t}


static var _dots: Dictionary = {}
static func _dot(color: Color) -> Texture2D:
	var key := color.to_html()
	if _dots.has(key):
		return _dots[key]
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 12:
		for y in 12:
			if Vector2(x - 5.5, y - 5.5).length() <= 5.0:
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_dots[key] = tex
	return tex
