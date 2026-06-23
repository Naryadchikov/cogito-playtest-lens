extends Node

## Filepath to the main menu scene.
@export_file("*.tscn") var main_menu_scene
## Filepath to the scene the player should start in, when pressing "Start game" button.
@export_file("*.tscn") var start_game_scene

func _on_main_menu_start_game_pressed():
	if start_game_scene: 
		CogitoSceneManager.load_next_scene(start_game_scene, "", "temp", CogitoSceneManager.CogitoSceneLoadMode.RESET) #Load_mode 2 means there's no attempt to load a state.
	else:
		print("menu_scene_switcher.gd: No start game scene set.")

func start_new_game():
	if CogitoGlobals.cogito_settings.new_game_start_scene:
		var path_to_scene = CogitoGlobals.cogito_settings.new_game_start_scene.resource_path
		CogitoSceneManager.load_next_scene(path_to_scene, "", "temp", CogitoSceneManager.CogitoSceneLoadMode.RESET) #Load_mode 2 means there's no attempt to load a state.
		#Setting new game world state:
		CogitoSceneManager._current_world_dict = CogitoGlobals.cogito_settings.new_game_world_state.get_world_dict()
	else:
		print("ISSUE: No start game scene set.")
