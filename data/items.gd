extends RefCounted
## Everything the scout can carry, wear or wield.
##
## slot    where it is worn: hand (either hand), head, neck, belt, top, bottom, body (a one-piece
##         garment that takes the place of top and bottom), sling, or ammo (stones, arrows)
## kind    the shape it has in the hand or on the body (human.gd); for ammo, which ammo it is
## size    [columns, rows] it takes in the bag or the chest
## weight  kilograms. A heavier weapon swings more slowly (Game.swing_speed).
## damage, defense, hp (more health), thirst (thirst regained per second, against the heat),
## stamina (stamina regained per second): what it gives while it is equipped. Missing = 0.
## hands   2 for a weapon that takes both hands (bows)
## stack   how many fit in one place in the bag (ammo)
## wear    the clothing pieces it shows on the figure, [piece, color]. A color may be "cloth" or
##         "sash" for the colors chosen in the character creator.
## Items with price 0 are never sold by the trader (starting gear and special finds).

const WOOD := Color(0.42, 0.28, 0.16)
const BRONZE := Color(0.8, 0.6, 0.3)
const IRON := Color(0.66, 0.68, 0.72)
const LEATHER := Color(0.36, 0.25, 0.16)
const LINEN := Color(0.88, 0.85, 0.76)
const GOLD := Color(0.92, 0.74, 0.26)

const ITEMS := {
	# ---- daggers: light and quick
	"flint_knife": {"slot": "hand", "kind": "dagger", "name": "Flint knife", "tier": 1, "price": 15, "size": [1, 2], "weight": 0.3, "damage": 9.0, "color": Color(0.5, 0.47, 0.42)},
	"dagger": {"slot": "hand", "kind": "dagger", "name": "Bronze dagger", "tier": 2, "price": 45, "size": [1, 2], "weight": 0.4, "damage": 18.0, "color": BRONZE},
	"iron_dagger": {"slot": "hand", "kind": "dagger", "name": "Iron dagger", "tier": 4, "price": 230, "size": [1, 2], "weight": 0.5, "damage": 29.0, "color": IRON},
	"gilded_dagger": {"slot": "hand", "kind": "dagger", "name": "Gilded dagger of Egypt", "tier": 5, "price": 0, "size": [1, 2], "weight": 0.5, "damage": 36.0, "stamina": 1.0, "color": GOLD},
	# ---- clubs, maces and axes: heavy and slow
	"club": {"slot": "hand", "kind": "club", "name": "Acacia club", "tier": 1, "price": 18, "size": [1, 3], "weight": 1.6, "damage": 14.0, "color": WOOD},
	"stone_mace": {"slot": "hand", "kind": "mace", "name": "Stone mace", "tier": 2, "price": 60, "size": [1, 3], "weight": 2.2, "damage": 22.0, "color": Color(0.55, 0.52, 0.47)},
	"bronze_mace": {"slot": "hand", "kind": "mace", "name": "Bronze mace", "tier": 3, "price": 160, "size": [1, 3], "weight": 2.4, "damage": 32.0, "color": BRONZE},
	"duckbill_axe": {"slot": "hand", "kind": "axe", "name": "Duckbill axe", "tier": 4, "price": 330, "size": [2, 3], "weight": 2.8, "damage": 45.0, "color": BRONZE},
	"war_axe": {"slot": "hand", "kind": "axe", "name": "Iron war axe", "tier": 5, "price": 600, "size": [2, 3], "weight": 3.2, "damage": 60.0, "color": IRON},
	# ---- swords
	"short_sword": {"slot": "hand", "kind": "sword_short", "name": "Bronze short sword", "tier": 2, "price": 70, "size": [1, 3], "weight": 0.9, "damage": 21.0, "color": BRONZE},
	"sickle_sword": {"slot": "hand", "kind": "sickle", "name": "Bronze sickle-sword", "tier": 3, "price": 120, "size": [1, 3], "weight": 1.2, "damage": 27.0, "color": BRONZE},
	"iron_sword": {"slot": "hand", "kind": "sword", "name": "Iron sword", "tier": 5, "price": 520, "size": [1, 3], "weight": 1.6, "damage": 47.0, "color": IRON},
	"long_sword": {"slot": "hand", "kind": "sword_long", "name": "Sea-raider's long sword", "tier": 5, "price": 680, "size": [1, 4], "weight": 2.1, "damage": 56.0, "color": IRON},
	"bashan_blade": {"slot": "hand", "kind": "sword_long", "name": "Blade of Bashan", "tier": 6, "price": 0, "size": [1, 4], "weight": 2.4, "damage": 66.0, "hp": 10.0, "color": Color(0.5, 0.52, 0.58)},
	# ---- staffs
	"staff": {"slot": "hand", "kind": "staff", "name": "Shepherd's staff", "tier": 1, "price": 0, "size": [1, 4], "weight": 1.4, "damage": 12.0, "color": WOOD},
	"shod_staff": {"slot": "hand", "kind": "staff", "name": "Bronze-shod staff", "tier": 3, "price": 110, "size": [1, 4], "weight": 2.0, "damage": 25.0, "stamina": 0.5, "color": WOOD},
	# ---- spears: long reach
	"hunting_spear": {"slot": "hand", "kind": "spear", "name": "Hunting spear", "tier": 2, "price": 55, "size": [1, 4], "weight": 1.5, "damage": 19.0, "color": Color(0.55, 0.52, 0.47)},
	"bronze_spear": {"slot": "hand", "kind": "spear", "name": "Bronze spear", "tier": 3, "price": 140, "size": [1, 4], "weight": 1.8, "damage": 29.0, "color": BRONZE},
	"spear": {"slot": "hand", "kind": "spear", "name": "Raider's spear", "tier": 4, "price": 260, "size": [1, 4], "weight": 2.0, "damage": 36.0, "color": BRONZE},
	"iron_spear": {"slot": "hand", "kind": "spear", "name": "Iron-headed spear", "tier": 5, "price": 560, "size": [1, 4], "weight": 2.3, "damage": 50.0, "color": IRON},
	"anak_spear": {"slot": "hand", "kind": "spear_long", "name": "Spear of the Anakim", "tier": 6, "price": 0, "size": [1, 4], "weight": 3.6, "damage": 72.0, "color": IRON},
	# ---- bows: both hands, need arrows
	"hunting_bow": {"slot": "hand", "kind": "bow", "hands": 2, "name": "Hunting bow", "tier": 2, "price": 75, "size": [2, 3], "weight": 0.8, "damage": 16.0, "color": WOOD},
	"composite_bow": {"slot": "hand", "kind": "bow", "hands": 2, "name": "Composite bow", "tier": 4, "price": 300, "size": [2, 3], "weight": 1.0, "damage": 30.0, "color": Color(0.5, 0.33, 0.18)},
	"war_bow": {"slot": "hand", "kind": "bow", "hands": 2, "name": "Egyptian war bow", "tier": 5, "price": 580, "size": [2, 4], "weight": 1.2, "damage": 43.0, "color": Color(0.3, 0.2, 0.12)},
	# ---- shields
	"wicker_shield": {"slot": "hand", "kind": "shield", "name": "Wicker shield", "tier": 1, "price": 20, "size": [2, 2], "weight": 2.0, "defense": 4.0, "color": Color(0.72, 0.6, 0.38)},
	"hide_shield": {"slot": "hand", "kind": "shield", "name": "Hide shield", "tier": 2, "price": 60, "size": [2, 2], "weight": 3.0, "defense": 7.0, "color": Color(0.6, 0.45, 0.3)},
	"rimmed_shield": {"slot": "hand", "kind": "shield", "name": "Bronze-rimmed shield", "tier": 3, "price": 170, "size": [2, 3], "weight": 4.5, "defense": 11.0, "color": LEATHER},
	"bronze_shield": {"slot": "hand", "kind": "shield", "name": "Bronze shield", "tier": 5, "price": 480, "size": [2, 3], "weight": 6.0, "defense": 16.0, "color": BRONZE},
	# ---- slings (right mouse)
	"wool_sling": {"slot": "sling", "kind": "sling", "name": "Wool sling", "tier": 1, "price": 0, "size": [1, 2], "weight": 0.1, "damage": 9.0, "color": Color(0.85, 0.82, 0.74)},
	"braided_sling": {"slot": "sling", "kind": "sling", "name": "Braided sling", "tier": 2, "price": 40, "size": [1, 2], "weight": 0.1, "damage": 14.0, "color": Color(0.7, 0.6, 0.45)},
	"war_sling": {"slot": "sling", "kind": "sling", "name": "War sling", "tier": 3, "price": 140, "size": [1, 2], "weight": 0.15, "damage": 21.0, "color": LEATHER},
	"long_sling": {"slot": "sling", "kind": "sling", "name": "Long sling", "tier": 4, "price": 300, "size": [1, 2], "weight": 0.15, "damage": 28.0, "color": Color(0.5, 0.3, 0.2)},
	"master_sling": {"slot": "sling", "kind": "sling", "name": "Master slinger's sling", "tier": 5, "price": 540, "size": [1, 2], "weight": 0.2, "damage": 36.0, "color": Color(0.6, 0.18, 0.16)},
	# ---- head
	"headcloth": {"slot": "head", "kind": "cap", "name": "Linen headcloth", "tier": 1, "price": 12, "size": [2, 2], "weight": 0.2, "defense": 1.0, "thirst": 0.03, "color": LINEN, "wear": [["cap", LINEN], ["band", "sash"]]},
	"leather_cap": {"slot": "head", "kind": "cap", "name": "Leather cap", "tier": 2, "price": 40, "size": [2, 2], "weight": 0.5, "defense": 3.0, "color": LEATHER, "wear": [["cap", LEATHER]]},
	"bronze_helmet": {"slot": "head", "kind": "helmet", "name": "Bronze helmet", "tier": 4, "price": 260, "size": [2, 2], "weight": 1.8, "defense": 7.0, "color": BRONZE, "wear": [["helmet", BRONZE]]},
	"crested_helmet": {"slot": "head", "kind": "helmet", "name": "Crested bronze helmet", "tier": 5, "price": 0, "size": [2, 2], "weight": 2.0, "defense": 9.0, "hp": 10.0, "color": GOLD, "wear": [["helmet", BRONZE], ["crown", GOLD]]},
	# ---- neck
	"cord_amulet": {"slot": "neck", "kind": "necklace", "name": "Cord amulet", "tier": 1, "price": 15, "size": [1, 1], "weight": 0.05, "stamina": 0.5, "color": Color(0.55, 0.45, 0.3), "wear": [["necklace", Color(0.55, 0.45, 0.3)]]},
	"carnelian_beads": {"slot": "neck", "kind": "necklace", "name": "Carnelian beads", "tier": 2, "price": 70, "size": [1, 1], "weight": 0.1, "hp": 8.0, "color": Color(0.75, 0.25, 0.15), "wear": [["necklace", Color(0.75, 0.25, 0.15)]]},
	"faience_collar": {"slot": "neck", "kind": "necklace", "name": "Faience collar", "tier": 3, "price": 150, "size": [1, 1], "weight": 0.2, "stamina": 1.0, "thirst": 0.02, "color": Color(0.2, 0.6, 0.62), "wear": [["necklace", Color(0.2, 0.6, 0.62)]]},
	"gold_pectoral": {"slot": "neck", "kind": "necklace", "name": "Gold pectoral", "tier": 5, "price": 600, "size": [1, 1], "weight": 0.4, "hp": 20.0, "stamina": 1.5, "color": GOLD, "wear": [["necklace", GOLD]]},
	# ---- belt
	"rope_girdle": {"slot": "belt", "kind": "belt", "name": "Rope girdle", "tier": 1, "price": 0, "size": [2, 1], "weight": 0.2, "stamina": 0.3, "color": Color(0.7, 0.62, 0.45), "wear": [["sash", "sash"]]},
	"leather_belt": {"slot": "belt", "kind": "belt", "name": "Leather belt", "tier": 2, "price": 35, "size": [2, 1], "weight": 0.4, "defense": 1.0, "stamina": 0.6, "color": LEATHER, "wear": [["sash", LEATHER]]},
	"studded_belt": {"slot": "belt", "kind": "belt", "name": "Bronze-studded belt", "tier": 4, "price": 210, "size": [2, 1], "weight": 0.9, "defense": 3.0, "hp": 5.0, "stamina": 0.6, "color": Color(0.55, 0.42, 0.24), "wear": [["sash", Color(0.55, 0.42, 0.24)]]},
	# ---- upper body
	"linen_tunic": {"slot": "top", "kind": "tunic", "name": "Linen tunic", "tier": 1, "price": 0, "size": [2, 3], "weight": 0.4, "defense": 1.0, "thirst": 0.02, "color": LINEN, "wear": [["top_short", "cloth"]]},
	"linen": {"slot": "top", "kind": "tunic", "name": "Padded linen", "tier": 2, "price": 50, "size": [2, 3], "weight": 1.5, "defense": 5.0, "color": Color(0.85, 0.8, 0.68), "wear": [["top_short", "cloth"], ["vest", Color(0.85, 0.8, 0.68)]]},
	"leather": {"slot": "top", "kind": "armor", "name": "Leather cuirass", "tier": 3, "price": 130, "size": [2, 3], "weight": 4.0, "defense": 9.0, "color": LEATHER, "wear": [["top_short", "cloth"], ["vest", LEATHER], ["bracers", LEATHER]]},
	"bronze_scale": {"slot": "top", "kind": "armor", "name": "Bronze scale coat", "tier": 4, "price": 300, "size": [2, 3], "weight": 9.0, "defense": 14.0, "color": BRONZE, "wear": [["top_short", "cloth"], ["vest", BRONZE], ["bracers", LEATHER]]},
	"iron_mail": {"slot": "top", "kind": "armor", "name": "Iron-studded coat", "tier": 5, "price": 560, "size": [2, 3], "weight": 11.0, "defense": 19.0, "color": IRON, "wear": [["top_short", "cloth"], ["vest", IRON], ["bracers", IRON]]},
	# ---- lower body
	"linen_kilt": {"slot": "bottom", "kind": "kilt", "name": "Linen kilt", "tier": 1, "price": 0, "size": [2, 2], "weight": 0.3, "defense": 1.0, "color": LINEN, "wear": [["skirt_short", "cloth"]]},
	"wool_wrap": {"slot": "bottom", "kind": "skirt", "name": "Long wool wrap", "tier": 2, "price": 30, "size": [2, 2], "weight": 0.8, "defense": 2.0, "thirst": 0.02, "color": Color(0.62, 0.32, 0.2), "wear": [["skirt_long", Color(0.62, 0.32, 0.2)]]},
	"leg_wraps": {"slot": "bottom", "kind": "kilt", "name": "Kilt and leg wraps", "tier": 3, "price": 90, "size": [2, 2], "weight": 1.2, "defense": 4.0, "stamina": 0.3, "color": LEATHER, "wear": [["skirt_short", "cloth"], ["leg_wraps", LEATHER]]},
	"bronze_greaves": {"slot": "bottom", "kind": "kilt", "name": "Kilt and bronze greaves", "tier": 5, "price": 320, "size": [2, 2], "weight": 3.0, "defense": 7.0, "color": BRONZE, "wear": [["skirt_short", "cloth"], ["leg_wraps", BRONZE]]},
	# ---- one-piece: top and bottom in one
	"long_robe": {"slot": "body", "kind": "robe", "name": "Long robe", "tier": 1, "price": 25, "size": [2, 4], "weight": 1.0, "defense": 2.0, "thirst": 0.04, "color": LINEN, "wear": [["top_long", "cloth"], ["skirt_long", "cloth"]]},
	"cloak": {"slot": "body", "kind": "robe", "name": "Robe and travel cloak", "tier": 2, "price": 70, "size": [2, 4], "weight": 2.2, "defense": 4.0, "thirst": 0.05, "color": Color(0.4, 0.27, 0.17), "wear": [["top_long", "cloth"], ["skirt_long", "cloth"], ["mantle", Color(0.4, 0.27, 0.17)], ["cloak", Color(0.4, 0.27, 0.17)]]},
	"dress": {"slot": "body", "kind": "dress", "name": "Embroidered dress", "tier": 2, "price": 80, "size": [2, 4], "weight": 0.9, "defense": 2.0, "hp": 5.0, "thirst": 0.03, "color": Color(0.6, 0.18, 0.16), "wear": [["top_long", Color(0.6, 0.18, 0.16)], ["skirt_long", Color(0.6, 0.18, 0.16)], ["mantle", Color(0.2, 0.26, 0.48)]]},
	"priestly_robe": {"slot": "body", "kind": "robe", "name": "Fine blue robe", "tier": 4, "price": 280, "size": [2, 4], "weight": 1.4, "defense": 5.0, "hp": 12.0, "thirst": 0.06, "stamina": 0.8, "color": Color(0.2, 0.26, 0.48), "wear": [["top_long", Color(0.2, 0.26, 0.48)], ["skirt_long", Color(0.2, 0.26, 0.48)], ["mantle", Color(0.9, 0.86, 0.74)]]},
	# ---- ammunition
	"stones": {"slot": "ammo", "kind": "stones", "name": "Sling stones", "tier": 1, "price": 0, "size": [1, 1], "weight": 0.15, "stack": 5, "color": Color(0.62, 0.58, 0.52)},
	"arrows": {"slot": "ammo", "kind": "arrows", "name": "Arrows", "tier": 1, "price": 0, "size": [1, 3], "weight": 0.03, "stack": 20, "color": WOOD},
}

## Where things can be worn, in the order the equipment panel lists them.
const EQUIP_SLOTS := ["head", "neck", "hand_r", "hand_l", "top", "belt", "bottom", "sling"]
const SLOT_NAMES := {
	"head": "Head", "neck": "Neck", "hand_r": "Right hand", "hand_l": "Left hand", "top": "Upper body",
	"belt": "Belt", "bottom": "Lower body", "sling": "Sling",
}
const STAT_NAMES := {
	"damage": "Damage", "defense": "Defense", "hp": "Health", "thirst": "Thirst regen", "stamina": "Stamina regen",
}

## What the scout carries things in: a grid of places. The trader sells the bigger ones, in order.
const PACKS := {
	"pouch": {"name": "Belt pouch", "grid": [6, 4], "price": 0},
	"shoulder_bag": {"name": "Shoulder bag", "grid": [8, 5], "price": 60},
	"pack": {"name": "Traveller's pack", "grid": [10, 6], "price": 200},
}
const PACK_ORDER := ["pouch", "shoulder_bag", "pack"]
## The chest in the scout's tent.
const CHEST_GRID := [14, 10]
