extends RefCounted
## Equipment table. "power" is damage for weapons and the blocked fraction for armor.
## Items with price 0 are never sold by the trader (starting gear and special drops).

const ITEMS := {
	"staff": {"slot": "melee", "name": "Shepherd's staff", "tier": 1, "power": 12.0, "price": 0},
	"dagger": {"slot": "melee", "name": "Bronze dagger", "tier": 2, "power": 18.0, "price": 45},
	"sickle_sword": {"slot": "melee", "name": "Bronze sickle-sword", "tier": 3, "power": 26.0, "price": 120},
	"spear": {"slot": "melee", "name": "Raider's spear", "tier": 4, "power": 35.0, "price": 260},
	"iron_sword": {"slot": "melee", "name": "Iron sword", "tier": 5, "power": 47.0, "price": 520},
	"bashan_blade": {"slot": "melee", "name": "Blade of Bashan", "tier": 6, "power": 62.0, "price": 0},
	"wool_sling": {"slot": "sling", "name": "Wool sling", "tier": 1, "power": 9.0, "price": 0},
	"braided_sling": {"slot": "sling", "name": "Braided sling", "tier": 2, "power": 14.0, "price": 40},
	"war_sling": {"slot": "sling", "name": "War sling", "tier": 3, "power": 21.0, "price": 140},
	"long_sling": {"slot": "sling", "name": "Long sling", "tier": 4, "power": 28.0, "price": 300},
	"master_sling": {"slot": "sling", "name": "Master slinger's sling", "tier": 5, "power": 36.0, "price": 540},
	"cloak": {"slot": "armor", "name": "Travel cloak", "tier": 1, "power": 0.05, "price": 0},
	"linen": {"slot": "armor", "name": "Padded linen", "tier": 2, "power": 0.12, "price": 50},
	"leather": {"slot": "armor", "name": "Leather cuirass", "tier": 3, "power": 0.20, "price": 130},
	"bronze_scale": {"slot": "armor", "name": "Bronze scale coat", "tier": 4, "power": 0.28, "price": 300},
	"iron_mail": {"slot": "armor", "name": "Iron-studded coat", "tier": 5, "power": 0.36, "price": 560},
}
