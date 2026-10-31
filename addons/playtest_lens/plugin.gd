@tool
extends EditorPlugin

## Editor only. Enabling the plugin adds the PlaytestLensLogger autoload,
## disabling it removes the autoload. While the plugin is on, the
## playtest_lens/player_path setting shows in Project Settings, General.
## The running game never loads this script.

const AUTOLOAD_NAME := "PlaytestLensLogger"
const AUTOLOAD_PATH := "res://addons/playtest_lens/logger.gd"
const PLAYER_PATH_SETTING := "playtest_lens/player_path"


func _enter_tree() -> void:
	# Empty is the default and is not written to project.godot.
	if not ProjectSettings.has_setting(PLAYER_PATH_SETTING):
		ProjectSettings.set_setting(PLAYER_PATH_SETTING, "")
	ProjectSettings.set_initial_value(PLAYER_PATH_SETTING, "")
	ProjectSettings.set_as_basic(PLAYER_PATH_SETTING, true)
	ProjectSettings.add_property_info({"name": PLAYER_PATH_SETTING, "type": TYPE_STRING})


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
