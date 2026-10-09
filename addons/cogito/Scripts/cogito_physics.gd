class_name CogitoPhysics

enum CollisionLayer {
	NONE = 0,
	ENVIRONMENT = 1,
	INTERACTABLES = 2,
	WATER = 3,
	NON_PHYSICAL_INTERACTABLES = 4,
	PLAYER = 5,
	NPC = 6,
}

enum CollisionMask {
	NONE = 0,
	ENVIRONMENT = 1 << (CollisionLayer.ENVIRONMENT - 1),
	INTERACTABLES = 1 << (CollisionLayer.INTERACTABLES - 1),
	WATER = 1 << (CollisionLayer.WATER - 1),
	NON_PHYSICAL_INTERACTABLES = 1 << (CollisionLayer.NON_PHYSICAL_INTERACTABLES - 1),
	PLAYER = 1 << (CollisionLayer.PLAYER - 1),
	NPC = 1 << (CollisionLayer.NPC - 1),
}
