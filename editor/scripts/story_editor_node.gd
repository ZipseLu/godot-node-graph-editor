## Darstellung eines Story-Nodes im Graph. Die Daten liegen in `data`,
## der Inspector bearbeitet sie und ruft danach refresh() auf.
class_name StoryEditorNode
extends GraphNode

const WIDTH := 250.0
const PORT_COLOR := Color("#d8dde3")

var node_id := ""
var node_type := ""
var data: Dictionary = {}

var _active := false
var _issue_level := ""  # "", "warning", "error"


func setup(id: String, type: String, node_data: Dictionary) -> void:
	node_id = id
	node_type = type
	name = id
	data = StoryNodeTypes.normalize_data(type, node_data)
	custom_minimum_size = Vector2(WIDTH, 0)
	refresh()


## Anzahl der Ausgänge aktuell.
func output_count() -> int:
	return StoryNodeTypes.get_outputs(node_type, data).size()


func refresh() -> void:
	var def := StoryNodeTypes.get_def(node_type)
	title = def.get("title", node_type)
	tooltip_text = def.get("help", "")

	clear_all_slots()
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var outputs := StoryNodeTypes.get_outputs(node_type, data)
	var has_input: bool = def.get("has_input", true)

	# Zeile 0: Vorschau. Trägt den Eingang und – bei genau einem Ausgang – auch den Ausgang.
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size = Vector2(WIDTH - 30, 0)
	summary.max_lines_visible = 4
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var text := StoryNodeTypes.summary_text(node_type, data).strip_edges()
	if text == "":
		text = _empty_hint()
		summary.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))
	else:
		summary.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
	summary.text = text
	add_child(summary)

	var single_output := outputs.size() == 1
	set_slot(0, has_input, 0, PORT_COLOR, single_output, 0, PORT_COLOR)

	if outputs.size() > 1:
		for i in outputs.size():
			var l := Label.new()
			l.text = outputs[i]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l.add_theme_color_override("font_color", _output_color(i, outputs.size()))
			add_child(l)
			set_slot(i + 1, false, 0, PORT_COLOR, true, 0, _output_color(i, outputs.size()))
	_apply_style()
	size = Vector2(WIDTH, 0)  # auf Inhalt schrumpfen
	reset_size()


func set_active(active: bool) -> void:
	_active = active
	_apply_style()


func set_issue_level(level: String) -> void:
	if level == _issue_level:
		return
	_issue_level = level
	_apply_style()


func _empty_hint() -> String:
	match node_type:
		"start": return "Beginn der Geschichte"
		"once": return "Beim ersten Mal oben, danach unten"
		"sequence": return "Führt die Schritte nacheinander aus"
		"random": return "Wählt zufällig"
		"end": return "Ende"
	return "(im Inspector ausfüllen)"


func _output_color(i: int, count: int) -> Color:
	# Wahr/Falsch und Erfolg/Abbruch farblich unterscheiden.
	if node_type in ["branch", "compare", "all_any"] and count == 2:
		return Color("#6fd39a") if i == 0 else Color("#ef8a7a")
	if node_type == "countdown":
		return Color("#6fd39a") if i == 0 else Color("#ef8a7a")
	if node_type == "choice" and float(data.get("time_limit", 0.0)) > 0.0 and i == count - 1:
		return Color("#ef8a7a")
	return Color(1, 1, 1, 0.8)


func _apply_style() -> void:
	var category: String = StoryNodeTypes.get_def(node_type).get("category", "")
	var color := StoryNodeTypes.category_color(category)

	var title_box := StyleBoxFlat.new()
	title_box.bg_color = color.darkened(0.25)
	title_box.corner_radius_top_left = 8
	title_box.corner_radius_top_right = 8
	title_box.content_margin_left = 12
	title_box.content_margin_right = 12
	title_box.content_margin_top = 6
	title_box.content_margin_bottom = 6
	var title_sel := title_box.duplicate()
	title_sel.bg_color = color

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#23272e")
	panel.corner_radius_bottom_left = 8
	panel.corner_radius_bottom_right = 8
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 8
	panel.content_margin_bottom = 10
	panel.border_color = color.darkened(0.25)
	panel.set_border_width_all(1)
	panel.border_width_top = 0
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 6
	var panel_sel := panel.duplicate()
	panel_sel.border_color = Color.WHITE
	panel_sel.set_border_width_all(2)
	panel_sel.border_width_top = 0

	for box in [panel, panel_sel]:
		if _issue_level == "error":
			box.border_color = Color("#ff5d5d")
			box.set_border_width_all(2)
			box.border_width_top = 0
		elif _issue_level == "warning" and box == panel:
			box.border_color = Color("#e0b040")
		if _active:
			box.border_color = Color("#ffd84a")
			box.set_border_width_all(4)
			box.border_width_top = 0
			box.shadow_color = Color("#ffd84a", 0.5)
			box.shadow_size = 14
	for box in [title_box, title_sel]:
		if _active:
			box.bg_color = Color("#ffd84a").lerp(color, 0.35)

	add_theme_stylebox_override("titlebar", title_box)
	add_theme_stylebox_override("titlebar_selected", title_sel)
	add_theme_stylebox_override("panel", panel)
	add_theme_stylebox_override("panel_selected", panel_sel)
	add_theme_constant_override("separation", 6)
