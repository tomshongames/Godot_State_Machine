# State Machine Visual Editor

A node-based finite state machine (FSM) addon for Godot. It combines a reusable
runtime with a visual editor for authoring States and transitions in a scene. The
runtime has no dependency on the editor plugin, and the addon adds no third-party
dependencies.

The current addon version is **1.16.2-dev**. The development target is Godot
**4.7.2 on Windows**. A shutdown defect in that engine version can cause a native
`0xC0000005` exit after tests finish; see [Godot #117975](https://github.com/godotengine/godot/issues/117975).
Focused shutdown comparisons passed on 4.8-dev7, which is not full compatibility
certification. Other operating systems and graphical acceptance remain unverified.
Development archives are not certified stable releases.

## Installation

1. Extract StateMachine-Release.zip at your Godot project root, or copy the
   included addons/state_machine directory into your project.
2. Copy the complete `addons/state_machine` directory into the same path in your
   Godot project: `res://addons/state_machine/`. When extracting a release ZIP,
   extract it at your project root so the `addons/` directory is preserved.
3. Keep all included `.gd.uid` files. Godot generates its import cache on first open. Do not replace your
   project's `project.godot` with the development project's file.
4. Open **Project → Project Settings → Plugins** and enable **State Machine Visual
   Editor**.
5. Select a `FiniteStateMachine` node. The **State Machine** main-screen workspace
   and its dock should become available.

## Quick Start

1. Add a `CharacterBody2D` or another gameplay Node to your scene.
2. Use **Add Child Node** in the SceneTree to add a `FiniteStateMachine` under it.
3. Select the FSM and set its **Actor** property to the gameplay Node.
4. Open the **State Machine** workspace. In **Events → STRUCTURE**, add two States,
   for example `Idle` and `Run`. Set **Initial State** to `Idle` in the Inspector.
5. Drag **Event** from the palette to the graph, connect its source to `Idle`, and
   connect its output to `Run`. Select the transition and set its event name to
   `begin_run`.
6. Add a script to the gameplay Node and send the event:

```gdscript
extends CharacterBody2D

@onready var fsm: FiniteStateMachine = $FiniteStateMachine

func _ready() -> void:
	if not fsm.send_event(&"begin_run"):
		push_warning("No eligible begin_run transition was committed")
	print("Current state: ", fsm.get_current_state_name())
```

The FSM enters its Initial State when it becomes ready. The authored Event route
then changes it to `Run`; `get_current_state_name()` lets you inspect the result.
State scripts are optional. A State script can implement lifecycle hooks:

```gdscript
extends State

func enter() -> void:
	print("Entered ", name)

func update(_delta: float) -> void:
	pass
```

`enter`, `exit`, `update`, `physics_update` and `handle_input` are available hooks.
Call `transition_to(&"StateName")` from a State to request an explicit transition.

## Core Concepts

The Quick Start above is a complete practical example. Runtime classes include
Godot `##` reference comments for configuration and public methods.

**FiniteStateMachine** is a Node that owns States, an Initial State, transition
Resources and runtime policy. A root FSM needs an Actor and at least one direct
State child. It starts automatically when it enters the running scene. To change
the root FSM, add or select a node in the SceneTree; the graph palette does not
create another root FSM.

**State** is a Node with lifecycle hooks and optional per-State policies. State
names are used as local transition endpoints. **StateTransition** is a Resource
that describes a source, destination, trigger, priority, Conditions, Effects,
cooldown and interruption behavior.

The supported triggers are Manual, Event, Timer, Input Action, Animation Finished,
Property Watch and Signal. `send_event(&"name")` dispatches an Event trigger;
`change_state(&"name")` and `State.transition_to(&"name")` provide explicit
requests. Input Action names must exist in Godot's Input Map. Animation, signal and
property triggers need their corresponding source and match settings configured.

**Conditions** gate a transition using typed property comparisons or expression
groups. **Effects** can set or add a property value, toggle a Boolean, call a method
or emit a signal at the configured transition phase. They run without arguments;
methods with required parameters are reported as invalid.

**HierarchyState** contains child States and an internal FSM. Each level has its own
Initial State and transition graph. Actor references inherit from the parent by
default, with an optional local override. Entry modes support RESET and RESUME.
ENTRY routes enter a nested machine; EXIT routes leave through the owning
HierarchyState's configured parent destination.

**Random routing** chooses among branch destinations from a transition's output.
Equal mode gives connected branches equal chances. Percentage mode uses authored
weights that must total 100. Random is an editor routing block, not a trigger or a
gameplay Node.

Transition priority is evaluated before selection; ties use authored order. State
Minimum State Time and Interruptible, plus transition Cooldown and Can Interrupt,
control eligibility and interruption. Self-transitions can re-enter the State or
keep its current lifecycle, according to the transition setting.

## Graph Editor

Select a `FiniteStateMachine` in the SceneTree and open the **State Machine**
workspace. The graph is in the center, the Inspector/Transitions/Validation/Search/
Live dock is on the right, and the **Events** palette can be shown beside the graph.
The palette's **STRUCTURE** group creates State and Hierarchy State nodes.

Click a transition trigger to create a floating draft, or drag it onto a State to
set its source. Connect its output to a destination when ready. Incomplete authored
transitions remain saved and appear in Validation; unattached drafts are temporary
editor state. Drag a block to a different source to move it, or reconnect its output
to change its destination. Undo and Redo apply to authoring operations.

Use **Auto Layout** to arrange States and transition stacks, **Frame All** to fit the
visible graph, and the zoom/grid controls to adjust the view. The toolbar Search and
the dock's Validation/Search tools operate on graph content. State visibility,
Appearance defaults, copy/paste, transition Conditions and Effects, Random branches
and live debugging are available in their respective graph, Inspector or dock
controls. The Events palette places Random after Signal under **TRANSITIONS**.

## Advanced Features

- Any State sources, hierarchy ENTRY/EXIT routing, explicit/inherited Actor links,
  RESET/RESUME entry behavior and per-FSM transition priorities.
- Conditions, grouped Boolean expressions, typed property comparisons, Effects,
  minimum State time, interruption, cooldown and self-reentry policies.
- Random equal or percentage routing with per-instance deterministic seed support.
- Persistent transition Resources, incomplete authored routes, independent parallel
  transitions, graph visibility metadata and saved graph positions.
- Cross-FSM State, hierarchy and transition copy/paste with independent mutable
  authoring Resources and scene Undo/Redo.
- Validation/Search navigation, native Inspector/SceneTree visibility controls and
  live runtime state, transition, history and watch information.

## Troubleshooting

- **The State Machine workspace is missing:** enable the plugin in Project Settings
  → Plugins, then select a `FiniteStateMachine` in the SceneTree.
- **The FSM does not enter its Initial State:** assign its Actor and a direct child
  State as Initial State. Check Godot's Output and the FSM configuration warnings.
- **An Event transition does not fire:** check that the route is enabled, its source
  and destination are connected, its event name matches `send_event`, and its
  Conditions, priority, minimum State time and cooldown allow it.
- **An Input Action transition is inactive:** add the action in Project Settings →
  Input Map and use the same name in the transition.
- **A nested machine cannot exit:** connect its EXIT route to a valid State in the
  parent graph, or to the parent's EXIT when that machine is itself nested.
- **An addon icon or class cannot be found after copying files:** copy the complete
  `addons/state_machine` folder and retain `.gd.uid` files,
  then allow Godot to finish importing before enabling the plugin.

## Project Structure

```text
addons/state_machine/runtime/   FSM, State, transition and runtime support
addons/state_machine/editor/    Godot editor plugin and graph components
addons/state_machine/icons/     Node and palette icons
addons/state_machine/plugin.cfg Plugin registration
addons/state_machine/README.md  Installation and usage
addons/state_machine/LICENSE    MIT license
```

The distributable archive contains the plugin, runtime, editor, required icons,
license and this README. It excludes tests, CI files, Python
tools, benchmarks, maintainer checklists, internal acceptance evidence and the
sample project.

## Compatibility and Limitations

Godot **4.7.2 on Windows** is the tested configuration. Other Godot versions and
platforms are not currently claimed. Signal arguments are not passed into Conditions
or Effects. Event delivery is not buffered. Runtime topology rebuilding during
execution and infinitely redirecting State entry callbacks are unsupported. The
editor's native SceneTree eye integration depends on Godot 4.7 editor internals;
Inspector and context-menu visibility controls are also available.

Contributor instructions, examples, performance results and the graphical
acceptance checklist are maintained in the source repository. Headless tests do
not certify appearance, focus behavior or pointer ergonomics.

## License

MIT. See [LICENSE](LICENSE).
