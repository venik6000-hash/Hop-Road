extends Logger
## Catches the runtime errors of scripts. A runtime error stops the function
## it is in: the checks after it do not run, and a verdict counted from the
## checks that ran is green. The runner reads this log and fails the run.
## tests/test_runner.gd and tools/lib/tool_runner.gd use it.
##
## With `with_push_error`, push_error() counts too. An error whose text has a
## fragment given to expect() is kept apart (expected()) and does not count.
## Godot can call the logger from any thread: every list is behind the mutex.

## The meta of the SceneTree that holds the log of a tool run (tool_runner.gd).
const META := "script_errors"

var _with_push_error: bool
var _mutex := Mutex.new()
var _messages: PackedStringArray = []
var _expected_fragments: PackedStringArray = []
var _expected: PackedStringArray = []

func _init(with_push_error := false) -> void:
	_with_push_error = with_push_error

## Errors whose text has `fragment` are expected from now on.
func expect(fragment: String) -> void:
	_mutex.lock()
	_expected_fragments.append(fragment)
	_mutex.unlock()

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var pushed := _with_push_error and error_type == ERROR_TYPE_ERROR and function == "push_error"
	if error_type != ERROR_TYPE_SCRIPT and not pushed:
		return
	# push_error() reports the engine's own file: the script that called it
	# is the top of the backtrace.
	if pushed and not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
		file = script_backtraces[0].get_frame_file(0)
		line = script_backtraces[0].get_frame_line(0)
		function = script_backtraces[0].get_frame_function(0)
	var text: String = rationale if not rationale.is_empty() else code
	var message := "%s (%s:%d, %s)" % [text, file.get_file(), line, function]
	_mutex.lock()
	var is_expected := false
	for fragment: String in _expected_fragments:
		is_expected = is_expected or text.contains(fragment)
	if is_expected:
		_expected.append(message)
	else:
		_messages.append(message)
	_mutex.unlock()

## The errors that count, caught since the last take(); the log is emptied.
func take() -> PackedStringArray:
	_mutex.lock()
	var out: PackedStringArray = _messages
	_messages = []
	_mutex.unlock()
	return out

## The errors that count, caught since the last take(); the log keeps them.
func peek() -> PackedStringArray:
	_mutex.lock()
	var out: PackedStringArray = _messages.duplicate()
	_mutex.unlock()
	return out

## The expected errors caught so far.
func expected() -> PackedStringArray:
	_mutex.lock()
	var out: PackedStringArray = _expected.duplicate()
	_mutex.unlock()
	return out
