@tool
extends EditorInspectorPlugin

const PROPERTY := preload("res://addons/state_machine/editor/state_visibility_property.gd")
var actions: RefCounted
var controls: Array[WeakRef] = []

func setup(editor_actions: RefCounted) -> void:
	actions = editor_actions

func _can_handle(object: Object) -> bool:
	return actions != null and object is State

func _parse_begin(object: Object) -> void:
	if not _can_handle(object): return
	var heading := Label.new()
	heading.text = "HIERARCHY STATE" if object is HierarchyState else "STATE"
	add_custom_control(heading)
	var property := PROPERTY.new()
	property.setup(object, actions)
	add_custom_control(property)
	controls = controls.filter(func(reference): return is_instance_valid(reference.get_ref()))
	controls.append(weakref(property))

func _parse_property(_object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_text: String, _usage: int, _wide: bool) -> bool:
	# Avoid an inverse, unmanaged duplicate in Node's generic Metadata section.
	return actions != null and name == "metadata/" + String(actions.HIDDEN_META)

func shutdown() -> void:
	var states := {}
	for reference in controls:
		var property = reference.get_ref()
		if not is_instance_valid(property): continue
		var state: State = property.state_ref.get_ref() if property.state_ref != null else null
		if is_instance_valid(state): states[state] = true
		property.shutdown()
	controls.clear()
	actions = null
	for state: State in states:
		if is_instance_valid(state): state.notify_property_list_changed()
