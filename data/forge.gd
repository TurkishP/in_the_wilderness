extends RefCounted
## What the camp's smith can forge, and what he asks for it. Change anything here.
##
## Each line:
##   item     what he makes (an id from data/items.gd)
##   silver   his fee
##   bronze   the metal it takes. Bronze falls from raiders (data/drops.gd).
##   needs    optional: an item he works from, taken from your bag (a staff to be shod)
## He can make only what the camp's craft has reached: things of the stage's tier or lower
## (data/stages.gd "tier"). Forging costs less silver than the trader's price, since you bring
## the metal yourself.
##
## Making gear stronger (+1, +2 ...) is not listed here: its cost comes from the item's tier
## (Game.upgrade_cost), and it stops at +2 until Bezalel's workshop stands.

const RECIPES := [
	{"item": "dagger", "silver": 18, "bronze": 1},
	{"item": "short_sword", "silver": 28, "bronze": 2},
	{"item": "hunting_spear", "silver": 22, "bronze": 1},
	{"item": "sickle_sword", "silver": 48, "bronze": 3},
	{"item": "bronze_mace", "silver": 64, "bronze": 4},
	{"item": "bronze_spear", "silver": 56, "bronze": 2},
	{"item": "shod_staff", "silver": 30, "bronze": 2, "needs": "staff"},
	{"item": "rimmed_shield", "silver": 68, "bronze": 3},
	{"item": "duckbill_axe", "silver": 130, "bronze": 5},
	{"item": "spear", "silver": 105, "bronze": 3},
	{"item": "iron_dagger", "silver": 92, "bronze": 2},
	{"item": "bronze_helmet", "silver": 105, "bronze": 4},
	{"item": "bronze_scale", "silver": 120, "bronze": 8},
	{"item": "studded_belt", "silver": 84, "bronze": 2},
	{"item": "iron_sword", "silver": 210, "bronze": 5},
	{"item": "long_sword", "silver": 270, "bronze": 7},
	{"item": "war_axe", "silver": 240, "bronze": 7},
	{"item": "iron_spear", "silver": 225, "bronze": 4},
	{"item": "bronze_shield", "silver": 190, "bronze": 9},
	{"item": "bronze_greaves", "silver": 128, "bronze": 5},
	{"item": "iron_mail", "silver": 225, "bronze": 10},
]
