@icon("res://addons/cogito/Assets/Graphics/Editor/Icon_StateProcessor.svg")
extends Node
class_name StateProcessor

## Reference to the NPC
@export var npc: CogitoNPC
## Reference to the NPCs state chart
@export var state_chart: StateChart
## Reference to the NPCs barker i.e if they make noises during states, this is the audio player for that
@export var barker: AudioStreamPlayer3D

## Plays a bark. Passes in a sound that could be null if not configured, so checks a barker exists and sound exists before attempting to play it
func bark(nullable_sound):
	if barker and nullable_sound:
		barker.stream = nullable_sound
		barker.play()
