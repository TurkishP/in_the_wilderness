extends RefCounted
## The look of every menu and of the text on screen: one set of colors and fonts, and a Theme
## built from them, so the title, the pause menu, the dialogs and the bag all match.
##
## Headings are set in Cinzel's capitals and everything else in EB Garamond, a book face, which
## suit an old story better than the engine's plain sans-serif. Without the font files the
## system's own book serifs are used instead (Palatino Linotype on Windows, with fall-backs).

const INK := Color(0.07, 0.052, 0.038)        # the ground of panels
const INK_LIGHT := Color(0.15, 0.115, 0.08)   # buttons and rows on it
const PARCHMENT := Color(0.96, 0.91, 0.8)     # running text
const GOLD := Color(0.96, 0.79, 0.46)         # headings, and whatever is chosen
const BRONZE := Color(0.62, 0.45, 0.24)       # borders and rules
const MUTED := Color(0.74, 0.68, 0.57)        # notes and small print
const DANGER := Color(1.0, 0.52, 0.4)
const SERIFS := ["Palatino Linotype", "Book Antiqua", "Constantia", "Georgia", "Times New Roman", "serif"]
## The game's own faces: role -> [file, weight, extra space between letters]. Cinzel (capitals
## cut like a Roman inscription) for headings, EB Garamond for everything read. Both are under
## the SIL Open Font License; the licence texts are beside them.
const FONTS := {
	"regular": ["res://assets/fonts/EBGaramond.ttf", 500, 0],
	"bold": ["res://assets/fonts/EBGaramond.ttf", 700, 0],
	"italic": ["res://assets/fonts/EBGaramond-Italic.ttf", 500, 0],
	"display": ["res://assets/fonts/Cinzel.ttf", 700, 1],
}

static var _fonts := {}
static var _theme: Theme


## The text font: "regular", "bold", "italic", or "display" (capitals with a little space between
## the letters, for headings). The game's own fonts are used if they are in assets/fonts/ (FONTS);
## otherwise the system's serifs stand in.
static func font(which: String = "regular") -> Font:
	if not _fonts.has(which):
		var own := _own_font(which)
		_fonts[which] = own if own != null else _system_font(which)
	return _fonts[which]


## One of the game's own faces at the weight the role wants. They are variable fonts: one file
## holds every weight.
static func _own_font(which: String) -> Font:
	var role: Array = FONTS.get(which, [])
	if role.is_empty() or not ResourceLoader.exists(str(role[0])):
		return null
	var face := FontVariation.new()
	face.base_font = load(str(role[0]))
	face.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): int(role[1])}
	face.spacing_glyph = int(role[2])
	return face


static func _system_font(which: String) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(SERIFS)
	f.font_weight = 700 if which == "bold" or which == "display" else 400
	f.font_italic = which == "italic"
	if which == "display":
		var spaced := FontVariation.new()
		spaced.base_font = f
		spaced.spacing_glyph = 2
		return spaced
	return f


## A box for panels: dark, with a bronze edge and a soft shadow under it.
static func panel_style(margin: float = 22.0, alpha: float = 0.96) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK.r, INK.g, INK.b, alpha)
	sb.border_color = BRONZE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	return sb


## The thin gold line drawn just inside a panel's edge.
static func inner_style(margin: float = 18.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(margin)
	return sb


## A panel with the double edge of the menus. Add what goes in it to the returned panel's
## "Inside" child (get_child(0)).
static func framed(margin: float = 18.0) -> PanelContainer:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", panel_style(5.0))
	var inner := PanelContainer.new()
	inner.name = "Inside"
	inner.add_theme_stylebox_override("panel", inner_style(margin))
	outer.add_child(inner)
	return outer


static func _button_box(bg: Color, bar: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = bar
	sb.border_width_left = 3
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


## The Theme all the game's controls take their look from.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 18
	t.set_color("font_color", "Label", PARCHMENT)
	# Buttons: a dark bar that lights up, with a gold mark at its left, when pointed at.
	var clear := Color(BRONZE.r, BRONZE.g, BRONZE.b, 0.0)
	t.set_stylebox("normal", "Button", _button_box(Color(INK_LIGHT.r, INK_LIGHT.g, INK_LIGHT.b, 0.9), clear))
	t.set_stylebox("hover", "Button", _button_box(Color(0.27, 0.2, 0.12, 0.95), GOLD))
	t.set_stylebox("pressed", "Button", _button_box(Color(0.34, 0.25, 0.13, 1.0), GOLD))
	t.set_stylebox("disabled", "Button", _button_box(Color(INK_LIGHT.r, INK_LIGHT.g, INK_LIGHT.b, 0.45), clear))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_hover_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(MUTED.r, MUTED.g, MUTED.b, 0.55))
	t.set_font_size("font_size", "Button", 18)
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", PARCHMENT)
	t.set_color("font_hover_color", "CheckBox", GOLD)
	t.set_color("font_pressed_color", "CheckBox", PARCHMENT)
	t.set_color("font_hover_pressed_color", "CheckBox", GOLD)
	t.set_constant("h_separation", "CheckBox", 10)
	# Sliders: a dark groove that fills with gold.
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0, 0, 0, 0.55)
	groove.border_color = Color(BRONZE.r, BRONZE.g, BRONZE.b, 0.6)
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(3)
	groove.content_margin_top = 4
	groove.content_margin_bottom = 4
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.75)
	filled.set_corner_radius_all(3)
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	t.set_font("normal_font", "RichTextLabel", font())
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_font("italics_font", "RichTextLabel", font("italic"))
	t.set_font("bold_italics_font", "RichTextLabel", font("italic"))
	# Scroll bars: a thin gold thumb.
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = Color(BRONZE.r, BRONZE.g, BRONZE.b, 0.8)
	thumb.set_corner_radius_all(3)
	thumb.content_margin_left = 3
	thumb.content_margin_right = 3
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.3)
	track.set_corner_radius_all(3)
	track.content_margin_left = 3
	track.content_margin_right = 3
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", bar, thumb)
		t.set_stylebox("grabber_highlight", bar, thumb)
		t.set_stylebox("grabber_pressed", bar, thumb)
		t.set_stylebox("scroll", bar, track)
	_theme = t
	return t


## A line of text. `which` is the font (see font()).
static func label(text: String, size: int = 18, color: Color = PARCHMENT, which: String = "regular") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(which))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A heading in spaced capitals.
static func heading(text: String, size: int = 28) -> Label:
	return label(text.to_upper(), size, GOLD, "display")


## A thin bronze rule that fades out at both ends, to part one thing from the next.
static func rule(width: float = 0.0) -> Control:
	var r := Rule.new()
	r.custom_minimum_size = Vector2(width, 12)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


class Rule extends Control:
	func _draw() -> void:
		var y := size.y * 0.5
		var mid := size.x * 0.5
		var steps := 24
		for i in steps:
			var a := float(i) / steps
			var b := float(i + 1) / steps
			var strength := sin((a + b) * 0.5 * PI)
			draw_line(Vector2(a * size.x, y), Vector2(b * size.x, y), Color(0.62, 0.45, 0.24, strength), 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(mid - 5, y), Vector2(mid, y - 4), Vector2(mid + 5, y), Vector2(mid, y + 4)]), Color(0.96, 0.79, 0.46, 0.9))
