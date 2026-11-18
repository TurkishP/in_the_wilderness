extends RefCounted
## What every enemy leaves behind when it falls. Change anything here; the game reads this
## table each time something dies (Game.roll_drops).
##
## DROPS: enemy kind (the keys of data/enemies.gd) -> list of lines. Every line is rolled on
## its own, so one enemy can drop several things.
##   chance   0..1, how often the line drops. Left out = always.
##   silver   [least, most] pieces of silver. Later stages give more (x 0.6 + 0.4 x stage mult).
##   bronze   [least, most] lumps of bronze, which the smith needs.
##   item     an item id from data/items.gd.
##   gear     true = one ordinary piece of gear the trader sells at this stage.
##   table    a name in TABLES below: one thing is picked from that list.
##
## Legendary weapons are never rolled for. Each exists once in a journey and comes from one place
## only: a stage boss (its "drop" in data/stages.gd), a very hard quest, or a place held by a unique
## guardian. LEGENDARY_SOURCES says where each is found.
##
## TABLES: name -> list of [item id, weight]. A heavier weight is picked more often. Only items
## whose tier is at most one above the stage's tier can fall, so the best finds wait for the
## later stages.

const DROPS := {
	# ---- wildlife: skins, stings and fangs, which the trader buys
	"snake": [
		{"chance": 0.45, "item": "viper_skin"},
	],
	"scorpion": [
		{"chance": 0.4, "item": "scorpion_sting"},
	],
	"jackal": [
		{"chance": 0.5, "item": "jackal_pelt"},
	],
	"wolf": [
		{"chance": 0.55, "item": "wolf_pelt"},
	],
	"hyena": [
		{"chance": 0.5, "item": "hyena_pelt"},
	],
	"leopard": [
		{"chance": 0.6, "item": "leopard_skin"},
	],
	"lion": [
		{"chance": 0.75, "item": "lion_skin"},
		{"chance": 0.5, "item": "lion_claw"},
	],
	"bear": [
		{"chance": 0.7, "item": "bear_pelt"},
		{"chance": 0.4, "item": "bear_claw"},
	],
	"fiery_serpent": [
		{"chance": 0.6, "item": "serpent_fang"},
		{"chance": 0.3, "item": "viper_skin"},
	],
	# ---- fighting men
	"raider": [
		{"silver": [3, 9]},
		{"chance": 0.3, "bronze": [1, 2]},
		{"chance": 0.1, "gear": true},
		{"chance": 0.01, "table": "rare"},
	],
	"slinger": [
		{"silver": [3, 9]},
		{"chance": 0.25, "bronze": [1, 1]},
		{"chance": 0.1, "gear": true},
		{"chance": 0.01, "table": "rare"},
	],
	# ---- the stronger ones
	"champion": [
		{"silver": [12, 25]},
		{"chance": 0.7, "bronze": [1, 3]},
		{"chance": 0.5, "gear": true},
		{"chance": 0.3, "table": "rare"},
	],
	"anak": [
		{"silver": [15, 30]},
		{"chance": 0.6, "bronze": [1, 3]},
		{"chance": 0.35, "table": "rare"},
	],
	"boss": [
		{"silver": [40, 70]},
		{"bronze": [3, 3]},
		{"gear": true},
		{"chance": 0.6, "table": "rare"},
	],
}

const TABLES := {
	"rare": [
		["thorn_club", 4], ["chieftains_spear", 4], ["khopesh", 4], ["horn_bow", 3],
		["maryannu_scale", 3], ["arad_mace", 3], ["crested_helmet", 2], ["gilded_dagger", 2],
		["heshbon_axe", 2],
	],
}

## Where each legendary weapon is found (for reference; the drop itself is set where it happens).
const LEGENDARY_SOURCES := {
	"chieftains_blade": "Stage 2: the Amalekite chief at Rephidim",
	"great_bow": "Stage 4: the bowmen of Kedar (a guarded place, not yet built)",
	"giants_shield": "Stage 5: the watchtower of the sons of Anak (a guarded place, not yet built)",
	"elders_staff": "Stage 6: the almond staff, a very hard quest (not yet built)",
	"anak_spear": "Stage 9: the field of the Rephaim (a guarded place, not yet built)",
	"bashan_blade": "Stage 9: Og, king of Bashan, at Edrei",
	"kings_khopesh": "Stage 10: the last of the five kings of Midian to fall",
}
