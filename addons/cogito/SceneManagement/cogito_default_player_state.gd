class_name CogitoDefaultPlayerState
extends CogitoPlayerState


func save_additional_states(player):
	pass


func load_additional_states(player):
	player.is_crouching = player.try_crouch
