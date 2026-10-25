@tool
extends RefCounted

const PREFIX := "editors/state_machine/appearance/"
const COLORS := {
	"graph_background": Color("25282e"),
	"grid": Color("454a54"),
	"default_state": Color("3a424d"),
	"hierarchy_state": Color("414b63"),
	"any_state": Color("4d465e"),
	"entry": Color("78b887"),
	"exit": Color("d09078"),
	"default_transition": Color("aab7c8"),
	"default_random": Color("514765"),
	"initial_accent": Color("78b887"),
	"selected_accent": Color("79a9e5"),
	"active_state_accent": Color("68bd87"),
	"last_transition_accent": Color("e3c17c"),
	"transition_manual": Color("c4c9d1"),
	"transition_event": Color("83a8d5"),
	"transition_timer": Color("b28bd2"),
	"transition_input_action": Color("bb9c70"),
	"transition_animation_finished": Color("6caaa9"),
	"transition_property_watch": Color("d09078"),
}

# Each exposed setting declares its dependants here. Unknown future settings
# fall back to a complete style pass, never a graph reconstruction.
const DEPENDENCIES := {
	"graph_background": ["background"], "grid": ["grid"],
	"default_state": ["states", "inspector"], "hierarchy_state": ["states", "inspector"],
	"any_state": ["any_state"], "entry": ["entry", "inspector"], "exit": ["exit", "inspector"],
	"default_transition": ["transitions", "inspector"], "default_random": ["random"],
	"initial_accent": ["states"],
	"selected_accent": ["states", "any_state", "entry", "exit", "random"],
	"active_state_accent": ["debug"], "last_transition_accent": ["debug"],
	"transition_manual": ["inspector"], "transition_event": ["inspector"],
	"transition_timer": ["inspector"], "transition_input_action": ["inspector"],
	"transition_animation_finished": ["inspector"], "transition_property_watch": ["inspector"],
}

static func affected_categories(key: String) -> Array:
	if DEPENDENCIES.has(key): return DEPENDENCIES[key]
	var categories := []
	for values in DEPENDENCIES.values():
		for category in values:
			if not category in categories: categories.append(category)
	return categories


static func initialize(settings: EditorSettings) -> void:
	if settings == null:
		return
	for key in COLORS:
		var setting: String = PREFIX + key
		var current: Variant = settings.get_setting(setting)
		if not current is Color:
			var initial: Color = COLORS[key]
			if key == "default_transition" and settings.has_setting("editors/state_machine/appearance/new_transition_color"):
				var legacy: Variant = settings.get_setting("editors/state_machine/appearance/new_transition_color")
				if legacy is Color: initial = legacy
			settings.set_setting(setting, initial)
			settings.set_initial_value(setting, COLORS[key], false)
		settings.add_property_info({"name": setting, "type": TYPE_COLOR})


static func get_color(settings: EditorSettings, key: String) -> Color:
	if settings != null:
		var value: Variant = settings.get_setting(PREFIX + key)
		if value is Color:
			return value
	return COLORS.get(key, Color.WHITE)


static func get_transition_color(interface: EditorInterface, trigger: int) -> Color:
	if trigger == 7: return get_color(interface.get_editor_settings() if is_instance_valid(interface) else null, "transition_event")
	var keys := ["transition_manual", "transition_event", "transition_timer", "transition_input_action", "transition_animation_finished", "transition_property_watch"]
	return get_color(interface.get_editor_settings() if is_instance_valid(interface) else null, keys[clampi(trigger, 0, keys.size() - 1)])


static func resolve_state_color(state: State, default_color: Color, preview_color: Variant = null) -> Color:
	if preview_color is Color:
		return preview_color
	if is_instance_valid(state):
		var authored: Variant = state.get_meta(&"fsm_editor_color", default_color)
		if authored is Color:
			return authored
	return default_color


static func resolve_boundary_color(machine: FiniteStateMachine, is_entry: bool, settings: EditorSettings) -> Color:
	var key := &"fsm_editor_boundary_entry_color" if is_entry else &"fsm_editor_exit_color"
	var container := machine.get_state_container() if is_instance_valid(machine) else null
	if is_instance_valid(container):
		var authored: Variant = container.get_meta(key, get_color(settings, "entry" if is_entry else "exit"))
		if authored is Color:
			return authored
	return get_color(settings, "entry" if is_entry else "exit")


static func set_color(settings: EditorSettings, key: String, value: Color) -> void:
	if settings == null or not COLORS.has(key):
		return
	settings.set_setting(PREFIX + key, value)
	settings.mark_setting_changed(PREFIX + key)


static func reset(settings: EditorSettings) -> void:
	if settings == null:
		return
	for key in COLORS:
		set_color(settings, key, COLORS[key])


static func keys() -> Array[String]:
	var result: Array[String] = []
	result.assign(COLORS.keys())
	return result


static func label(key: String) -> String:
	var labels := {
		"graph_background": "Graph Background",
		"grid": "Grid",
		"default_state": "Default State",
		"hierarchy_state": "Hierarchy State",
		"any_state": "Any State",
		"entry": "ENTRY Color",
		"exit": "EXIT Color",
		"default_transition": "Default Transition Color",
		"default_random": "Default Random Color",
		"initial_accent": "Initial State Accent",
		"selected_accent": "Selected State Accent",
		"active_state_accent": "Active State Accent",
		"last_transition_accent": "Last Transition Accent",
		"transition_manual": "Manual",
		"transition_event": "Event",
		"transition_timer": "Timer",
		"transition_input_action": "Input Action",
		"transition_animation_finished": "Animation Finished",
		"transition_property_watch": "Property Watch",
	}
	return labels.get(key, key)
