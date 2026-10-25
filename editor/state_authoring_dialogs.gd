@tool
extends Node

signal create_requested(name: String, create_script: bool)
signal delete_confirmed
signal color_confirmed(color: Color, reset: bool)
signal script_ready(script: Script)

var create_dialog: ConfirmationDialog
var delete_dialog: ConfirmationDialog
var color_dialog: ConfirmationDialog
var error_dialog: AcceptDialog
var name_edit: LineEdit
var script_check: CheckBox
var color_picker: ColorPickerButton
var resetting := false
var script_file_dialog: EditorFileDialog
var script_base_class := "State"


func setup() -> void:
	create_dialog = ConfirmationDialog.new()
	create_dialog.title = "Create State"
	create_dialog.get_ok_button().text = "Create"
	add_child(create_dialog)
	var form := VBoxContainer.new()
	create_dialog.add_child(form)
	var name_label := Label.new()
	name_label.text = "Name"
	form.add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size.x = 320
	form.add_child(name_edit)
	script_check = CheckBox.new()
	script_check.text = "Create Script"
	script_check.button_pressed = true
	form.add_child(script_check)
	var template := OptionButton.new()
	template.add_item("Empty")
	form.add_child(template)
	var location := Label.new()
	location.text = "Scripts: states/ beside the saved scene.\nUnsaved scenes ask where to save the script.\nExisting files are never overwritten."
	form.add_child(location)
	create_dialog.confirmed.connect(func(): create_requested.emit(name_edit.text, script_check.button_pressed))
	name_edit.text_submitted.connect(func(_text): create_dialog.get_ok_button().pressed.emit())
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete State"
	delete_dialog.confirmed.connect(func(): delete_confirmed.emit())
	add_child(delete_dialog)
	color_dialog = ConfirmationDialog.new()
	color_dialog.title = "State Color"
	add_child(color_dialog)
	var colors := VBoxContainer.new()
	color_dialog.add_child(colors)
	color_picker = ColorPickerButton.new()
	color_picker.custom_minimum_size = Vector2(280, 40)
	color_picker.color_changed.connect(func(_color): resetting = false)
	colors.add_child(color_picker)
	var presets := HBoxContainer.new()
	colors.add_child(presets)
	for color in [Color("788aa3"), Color("7c9c87"), Color("aa9775"), Color("9986a5")]:
		var button := Button.new()
		button.text = "●"
		button.modulate = color
		button.pressed.connect(_choose_color.bind(color))
		presets.add_child(button)
	var reset := Button.new()
	reset.text = "Reset Color"
	reset.pressed.connect(func(): resetting = true; color_dialog.confirmed.emit(); color_dialog.hide())
	colors.add_child(reset)
	color_dialog.confirmed.connect(func(): color_confirmed.emit(color_picker.color, resetting))
	error_dialog = AcceptDialog.new()
	error_dialog.title = "State Machine"
	add_child(error_dialog)


func _build_script_file_dialog() -> void:
	script_file_dialog = EditorFileDialog.new()
	script_file_dialog.title = "Save State Script"
	script_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	script_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	script_file_dialog.add_filter("*.gd", "GDScript")
	script_file_dialog.file_selected.connect(_script_file_selected)
	add_child(script_file_dialog)


func show_create(suggested_name: String) -> void:
	name_edit.text = suggested_name
	create_dialog.popup_centered()
	name_edit.grab_focus()
	name_edit.select_all()


func show_delete(state_name: String, count: int) -> void:
	delete_dialog.dialog_text = "State '%s' has %d connected transitions.\nDeleting it will also remove those transitions." % [state_name, count]
	delete_dialog.popup_centered()


func show_color(color: Color) -> void:
	resetting = false
	color_picker.color = color
	color_dialog.popup_centered()


func _choose_color(color: Color) -> void:
	resetting = false
	color_picker.color = color


func show_error(message: String) -> void:
	if error_dialog == null:
		push_warning(message)
		return
	error_dialog.dialog_text = message
	error_dialog.popup_centered()


func script_directory(scene: Node, machine: FiniteStateMachine = null) -> String:
	if not is_instance_valid(scene) or scene.scene_file_path.is_empty():
		return ""
	var directory := scene.scene_file_path.get_base_dir().path_join("states").simplify_path()
	var names: Array[String] = []
	var visited := {}
	while is_instance_valid(machine) and not visited.has(machine):
		visited[machine] = true
		var state := machine.get_parent() as State
		if state == null:
			break
		names.push_front(_script_basename(String(state.name)))
		machine = FiniteStateMachine.machine_for_state(state)
	for state_name in names:
		directory = directory.path_join(state_name)
	return "" if directory.to_lower().begins_with("res://addons/") else directory


func request_script(state_name: String, scene: Node, machine: FiniteStateMachine = null, base_class: String = "State") -> void:
	script_base_class = base_class
	var directory := script_directory(scene, machine)
	if directory.is_empty():
		if script_file_dialog == null:
			_build_script_file_dialog()
		script_file_dialog.current_dir = "res://"
		script_file_dialog.current_file = _script_basename(state_name) + ".gd"
		script_file_dialog.popup_centered_ratio(0.65)
		return
	var script := create_script_at(directory.path_join(_script_basename(state_name) + ".gd"), _state_template(base_class))
	if script:
		script_ready.emit(script)


func create_script(state_name: String, scene: Node, machine: FiniteStateMachine, base_class: String = "State") -> Script:
	var directory := script_directory(scene, machine)
	if directory.is_empty():
		return null
	return create_script_at(directory.path_join(_script_basename(state_name) + ".gd"), _state_template(base_class))


func _script_basename(state_name: String) -> String:
	var basename := state_name.to_snake_case().validate_filename()
	return "state" if basename.is_empty() else basename


func _script_file_selected(path: String) -> void:
	var script := create_script_at(path, _state_template(script_base_class))
	if script:
		script_ready.emit(script)


func _state_template(base_class: String) -> String:
	return ("@tool\n" if base_class == "HierarchyState" else "") + "extends %s\n\nfunc enter() -> void:\n\tpass\n\nfunc exit() -> void:\n\tpass\n" % base_class


func copy_state_script(source: Script, state_name: String, scene: Node) -> Script:
	if not source is GDScript:
		show_error("Only GDScript State scripts can be copied automatically.")
		return null
	var directory := source.resource_path.get_base_dir() if source.resource_path.begins_with("res://") else ""
	if directory.is_empty() or directory.to_lower().begins_with("res://addons/"):
		directory = script_directory(scene)
	if directory.is_empty():
		show_error("Save the scene before duplicating a State with an embedded or unsaved custom script.")
		return null
	var code: String = source.source_code
	var global_class := RegEx.new()
	global_class.compile("(?m)^([ \\t]*)class_name[ \\t]+[A-Za-z_][A-Za-z_0-9]*[ \\t]*")
	code = global_class.sub(code, "$1", true)
	return create_script_at(directory.path_join(_script_basename(state_name) + ".gd"), code)


func create_script_at(requested_path: String, source_code: String = "") -> Script:
	var path := requested_path.simplify_path()
	if not path.begins_with("res://") or path.to_lower().begins_with("res://addons/") or path.get_extension().to_lower() != "gd":
		show_error("Save gameplay scripts as .gd files in project content outside res://addons/.")
		return null
	var directory := path.get_base_dir()
	var result := DirAccess.make_dir_recursive_absolute(directory)
	if result != OK:
		show_error("Cannot create script directory: %s (error %s)." % [directory, result])
		return null
	var basename := path.get_file().get_basename()
	var index := 2
	while FileAccess.file_exists(path):
		path = directory.path_join(basename + "_" + str(index) + ".gd")
		index += 1
	var script := GDScript.new()
	script.source_code = source_code if not source_code.is_empty() else "extends State\n\n\nfunc enter() -> void:\n\tpass\n\n\nfunc exit() -> void:\n\tpass\n"
	script.resource_path = path
	if script.reload() != OK:
		show_error("The Empty State template could not be compiled.")
		return null
	result = ResourceSaver.save(script, path)
	if result != OK:
		show_error("Cannot save State script: %s (error %s)." % [path, result])
		return null
	script.take_over_path(path)
	return script
