@tool
extends RefCounted

const APPEARANCE := preload("res://addons/state_machine/editor/appearance_preferences.gd")

const META := &"fsm_editor_transition_color"
const END_META := &"fsm_editor_transition_end_color"
const SETTING := "editors/state_machine/appearance/new_transition_color"
const INSPECTOR_SWATCH_SIZE := Vector2(32.0, 28.0)
static var default_color := Color("aab7c8")
const DEFAULT := Color("aab7c8")

static func configure_inspector_color_button(button: ColorPickerButton) -> void:
	if button == null: return
	button.custom_minimum_size = INSPECTOR_SWATCH_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

static func color(route: Resource) -> Color:
	var value: Variant = route.get_meta(META, default_color) if route != null else default_color
	return value if value is Color else default_color

static func uses_entry_color(route: Resource) -> bool:
	return route is StateTransition and route.source_mode == StateTransition.SourceMode.HIERARCHY_ENTRY

static func source_color(route: Resource, machine: FiniteStateMachine = null, settings: EditorSettings = null) -> Color:
	if not uses_entry_color(route): return color(route)
	if settings == null and Engine.is_editor_hint(): settings = EditorInterface.get_editor_settings()
	return APPEARANCE.resolve_boundary_color(machine, true, settings)

static func end_color(route: Resource, automatic: Color) -> Color:
	if uses_exit_color(route): return automatic
	var value: Variant = route.get_meta(END_META, automatic) if route != null else automatic
	return value if value is Color else automatic

static func uses_exit_color(route: Resource) -> bool:
	return route is StateTransition and route.target_key() == StateTransition.EXIT_TARGET

static func has_override(resource: Resource) -> bool:
	return resource != null and resource.has_meta(META) and resource.get_meta(META) is Color

static func has_end_override(resource: Resource) -> bool:
	return resource != null and not uses_exit_color(resource) and resource.has_meta(END_META) and resource.get_meta(END_META) is Color

static func creation(settings: EditorSettings) -> Color:
	if settings == null: return DEFAULT
	if not settings.has_setting(SETTING) or not settings.get_setting(SETTING) is Color:
		settings.set_setting(SETTING, DEFAULT)
		settings.set_initial_value(SETTING, DEFAULT, false)
	settings.add_property_info({"name":SETTING, "type":TYPE_COLOR})
	return settings.get_setting(SETTING)

static func swatch(value: Color, size := 10) -> Texture2D:
	var pixels := Image.create(size, size, false, Image.FORMAT_RGBA8)
	pixels.fill(value)
	return ImageTexture.create_from_image(pixels)
