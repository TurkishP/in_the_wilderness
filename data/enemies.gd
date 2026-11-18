extends RefCounted
## Enemy table. hp and dmg are stage-1 values; each stage multiplies them.
## "xp" is the experience one is worth at stage 1; later stages multiply it as they do health.
## What each one drops is in data/drops.gd. A "champion" is the picked man of a people: he leads
## the later raids and wanders the wilds with a few followers, and may carry a rare weapon.
## "reach" is melee reach in metres, or firing range for ranged enemies.

const ENEMIES := {
	"snake": {"name": "Desert viper", "xp": 6, "shape": "snake", "hp": 18.0, "dmg": 8.0, "speed": 5.2, "reach": 1.5, "aggro": 11.0, "radius": 0.45, "color": Color(0.62, 0.52, 0.3)},
	"scorpion": {"name": "Scorpion", "xp": 8, "shape": "scorpion", "hp": 30.0, "dmg": 12.0, "speed": 3.0, "reach": 1.5, "aggro": 9.0, "radius": 0.5, "color": Color(0.25, 0.18, 0.12)},
	"jackal": {"name": "Jackal", "xp": 8, "shape": "beast", "hp": 24.0, "dmg": 9.0, "speed": 6.4, "reach": 1.7, "aggro": 16.0, "radius": 0.5, "color": Color(0.6, 0.48, 0.3)},
	# The beasts met further out in the wilds (data/encounters.gd). "flee": runs off below this
	# share of its health; "stalk": creeps up low, then springs; "heavy": hard to drive back.
	"wolf": {"name": "Arabian wolf", "xp": 16, "shape": "wolf", "hp": 42.0, "dmg": 12.0, "speed": 7.0, "reach": 1.8, "aggro": 24.0, "radius": 0.55, "color": Color(0.62, 0.57, 0.48)},
	"hyena": {"name": "Striped hyena", "xp": 18, "shape": "hyena", "hp": 55.0, "dmg": 15.0, "speed": 6.2, "reach": 1.8, "aggro": 14.0, "radius": 0.6, "color": Color(0.7, 0.66, 0.57), "flee": 0.4},
	"leopard": {"name": "Leopard", "xp": 30, "shape": "leopard", "hp": 60.0, "dmg": 22.0, "speed": 8.4, "reach": 1.9, "aggro": 28.0, "radius": 0.55, "color": Color(0.82, 0.68, 0.44), "stalk": true},
	"lion": {"name": "Lion", "xp": 70, "shape": "lion", "hp": 160.0, "dmg": 30.0, "speed": 7.8, "reach": 2.3, "aggro": 26.0, "radius": 0.9, "color": Color(0.78, 0.62, 0.4), "stalk": true, "heavy": true},
	"bear": {"name": "Syrian brown bear", "xp": 75, "shape": "bear", "hp": 190.0, "dmg": 28.0, "speed": 5.8, "reach": 2.2, "aggro": 18.0, "radius": 0.95, "color": Color(0.62, 0.5, 0.36), "heavy": true},
	"fiery_serpent": {"name": "Fiery serpent", "xp": 12, "shape": "snake", "hp": 28.0, "dmg": 16.0, "speed": 6.0, "reach": 1.6, "aggro": 14.0, "radius": 0.5, "color": Color(0.85, 0.3, 0.1)},
	"raider": {"name": "Raider", "xp": 20, "shape": "human", "hp": 55.0, "dmg": 14.0, "speed": 4.7, "reach": 2.0, "aggro": 18.0, "radius": 0.45, "color": Color(0.45, 0.2, 0.15)},
	"slinger": {"name": "Slinger", "xp": 18, "shape": "human", "hp": 38.0, "dmg": 10.0, "speed": 4.3, "reach": 17.0, "aggro": 22.0, "radius": 0.45, "color": Color(0.3, 0.32, 0.2), "ranged": true},
	"anak": {"name": "Son of Anak", "xp": 110, "shape": "human", "hp": 240.0, "dmg": 30.0, "speed": 3.8, "reach": 2.2, "aggro": 20.0, "radius": 0.5, "scale": 1.7, "color": Color(0.35, 0.3, 0.28)},
	"champion": {"name": "Champion", "xp": 70, "shape": "human", "hp": 150.0, "dmg": 20.0, "speed": 4.9, "reach": 2.1, "aggro": 20.0, "radius": 0.45, "scale": 1.15, "color": Color(0.5, 0.3, 0.1)},
	"boss": {"name": "Chief", "xp": 250, "shape": "human", "hp": 380.0, "dmg": 24.0, "speed": 4.4, "reach": 2.0, "aggro": 26.0, "radius": 0.45, "scale": 1.35, "color": Color(0.55, 0.1, 0.1)},
}

const HIDE := Color(0.47, 0.34, 0.22)
const LEATHER := Color(0.36, 0.25, 0.16)
const BRONZE := Color(0.8, 0.6, 0.3)
const GOLD := Color(0.9, 0.72, 0.2)
const LINEN := Color(0.86, 0.82, 0.72)
const UNDYED := Color(0.64, 0.56, 0.43)
const DARK_WOOL := Color(0.3, 0.24, 0.2)
const RUST := Color(0.6, 0.3, 0.18)
const OCHRE := Color(0.74, 0.55, 0.25)
const RED := Color(0.6, 0.16, 0.14)
const BLUE := Color(0.2, 0.26, 0.48)
const PURPLE := Color(0.42, 0.16, 0.4)

## The fighting men of each people Israel met (a stage's "foe"), dressed and armed as closely
## to the Late Bronze Age record as the game's pieces allow. What each is based on:
##   Desert, Amalekite  Nothing found in the ground can be tied to Amalek, so they follow the
##                      nomads of Sinai and the Negev as Egypt drew them (the "Shasu" of Seti I's
##                      Karnak reliefs and Ramesses III's tiles): bearded men in short kilts with
##                      a headcloth or a band round long hair, with spears, axes and clubs.
##   Canaanite          City soldiers as on the Megiddo ivories and in Egyptian battle scenes:
##                      kilts or wrapped robes in dyed wool, hair bound with a fillet, spears,
##                      sickle swords and axes, shields rectangular or (later) round. The chariot
##                      nobles (maryannu) wore bronze scale and helmets; about half of those
##                      taken at Megiddo had armour.
##   Amorite            The kingdoms of Sihon and Og. Little from Late Bronze Transjordan
##                      survives, so they follow their Syrian kin (Amurru in Egyptian art): long
##                      wrapped robes, helmets and scale for the king's men. Og's iron is his own
##                      (Deuteronomy 3:11).
##   Midianite          The painted pottery of Qurayyah (14th-12th century BC) shows their men
##                      in skirts, armed with daggers. The gold at the neck and the purple of
##                      their kings are from Judges 8:24-26.
##   Edomite            Egypt knew the herdsmen of Edom as Shasu: Papyrus Anastasi VI (about
##                      1213-1203 BC, under Merneptah) records "Shasu of Edom" let past the
##                      fortress of Tjeku to water their flocks at Pithom. So they are dressed as
##                      the Shasu are drawn: short kilts, headcloths, spears and axes; red and
##                      ochre for the red land (Genesis 25:30). Little else is known of Edom
##                      this early: its copper works at Faynan are later (12th-9th century BC).
##   Moabite            Ramesses II names Moab among his conquests (Luxor). The Balu'a stele,
##                      found in Moab and dated to the 13th-11th century BC, shows a ruler in a
##                      long patterned gown and a headdress of the Shasu kind: that is their
##                      king. A warrior stele from Shihan (its date is uncertain, between about
##                      1200 and 800 BC) shows a man with a spear: their spearmen. The rest
##                      is guessed from their neighbours.
##   Anakim             No remains are known. Their arms follow the one giant the Bible
##                      describes piece by piece, Goliath of Gath (1 Samuel 17:5-7): bronze
##                      helmet, scale coat and greaves, and a heavy spear.
## Each troop: name, what the right and left hands hold, the shield's shape ("round", "hide" or
## "rect"), clothing pieces ("wear") and head pieces ("head") as human.gd takes them ("cloth"
## and "sash" stand for one of the people's colors; a third entry weaves a pattern into the
## piece: "stripes" down it, as Egypt painted the nomads' kilts, or "hem" for the coloured
## borders of Canaan and Syria), and "hair" for a set hair style.
const PEOPLES := {
	"Desert": {
		"cloth": [UNDYED, DARK_WOOL, Color(0.5, 0.4, 0.3)], "sash": [HIDE, DARK_WOOL],
		"troops": [
			{"name": "clubman", "right": "club", "wear": [["skirt_short", "cloth"], ["sash", "sash"]], "head": [["band_wide", "sash"]], "hair": 2},
			{"name": "spearman", "right": "spear", "left": "shield", "shield": "hide", "wear": [["top_short", "cloth"], ["skirt_short", "cloth"], ["sash", "sash"]], "head": [["cap", "cloth"], ["band", "sash"]]},
			{"name": "raider", "right": "dagger", "wear": [["skirt_short", "cloth"], ["sash", "sash"], ["mantle", "sash"]], "head": [["cap", "cloth"], ["shawl", "cloth"]]},
		],
		"slinger": {"name": "slinger", "wear": [["skirt_short", "cloth"], ["sash", "sash"]], "head": [["band_wide", "sash"]], "hair": 2},
		"champion": {"name": "champion", "right": "spear", "left": "shield", "shield": "hide", "wear": [["top_short", "cloth"], ["skirt_short", "cloth"], ["sash", "sash"], ["vest", HIDE], ["bracers", LEATHER]], "head": [["cap", LINEN], ["shawl", LINEN], ["band", "sash"]]},
		"chief": {"name": "chief", "right": "sickle", "left": "shield", "shield": "hide", "wear": [["top_short", "cloth"], ["skirt_short", "cloth"], ["sash", "sash"], ["vest", HIDE], ["mantle", RUST], ["cloak", RUST]], "head": [["cap", LINEN], ["shawl", LINEN], ["band", RUST]]},
	},
	"Amalekite": {
		"cloth": [OCHRE, RUST, UNDYED, Color(0.52, 0.36, 0.22)], "sash": [HIDE, RED, DARK_WOOL],
		"troops": [
			{"name": "spearman", "right": "spear", "left": "shield", "shield": "hide", "wear": [["skirt_short", "cloth", "stripes"], ["sash", "sash"]], "head": [["cap", LINEN], ["band", "sash"]]},
			{"name": "swordsman", "right": "sickle", "left": "shield", "shield": "hide", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "stripes"], ["sash", "sash"], ["vest", HIDE]], "head": [["cap", LINEN], ["shawl", LINEN], ["band", "sash"]]},
			{"name": "clubman", "right": "club", "wear": [["skirt_short", "cloth", "stripes"], ["sash", "sash"]], "head": [["band_wide", "sash"]], "hair": 2},
			{"name": "axeman", "right": "axe", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "stripes"], ["sash", "sash"]], "head": [["cap", "cloth"], ["band", "sash"]]},
		],
		"slinger": {"name": "slinger", "wear": [["skirt_short", "cloth", "stripes"], ["sash", "sash"]], "head": [["band_wide", "sash"]], "hair": 2},
		"champion": {"name": "champion", "right": "sickle", "left": "shield", "shield": "hide", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "stripes"], ["sash", "sash"], ["vest", HIDE], ["bracers", LEATHER], ["mantle", "sash"]], "head": [["cap", LINEN], ["shawl", LINEN], ["band", "sash"]]},
		"chief": {"name": "chief", "right": "sickle", "left": "shield", "shield": "hide", "wear": [["top_short", RUST], ["skirt_short", RUST, "stripes"], ["sash", HIDE], ["vest", HIDE], ["bracers", LEATHER], ["mantle", RED], ["cloak", RED]], "head": [["cap", LINEN], ["shawl", LINEN], ["band", RED]]},
	},
	"Canaanite": {
		"cloth": [RED, BLUE, OCHRE, LINEN], "sash": [OCHRE, RED, BLUE],
		"troops": [
			{"name": "spearman", "right": "spear", "left": "shield", "shield": "rect", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"]], "head": [["helmet", BRONZE]]},
			{"name": "swordsman", "right": "sickle", "left": "shield", "shield": "round", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"], ["vest", LEATHER]], "head": [["cap", "cloth"], ["band", "sash"]]},
			{"name": "axeman", "right": "axe", "wear": [["top_short", "cloth"], ["skirt_long", "cloth", "hem"], ["sash", "sash"]], "head": [["band_wide", "sash"]], "hair": 1},
			{"name": "noble", "right": "sword_short", "left": "shield", "shield": "round", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"], ["vest", BRONZE], ["bracers", LEATHER]], "head": [["helmet", BRONZE]]},
		],
		"slinger": {"name": "slinger", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"]], "head": [["band_wide", "sash"]], "hair": 1},
		"champion": {"name": "champion", "right": "sickle", "left": "shield", "shield": "round", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"], ["vest", BRONZE], ["bracers", BRONZE], ["leg_wraps", LEATHER]], "head": [["helmet", BRONZE]]},
		"chief": {"name": "captain", "right": "sickle", "left": "shield", "shield": "round", "wear": [["top_short", RED], ["skirt_short", RED, "hem"], ["sash", OCHRE], ["vest", BRONZE], ["bracers", BRONZE], ["leg_wraps", LEATHER], ["mantle", BLUE], ["cloak", BLUE]], "head": [["helmet", BRONZE]]},
	},
	"Amorite": {
		"cloth": [Color(0.5, 0.14, 0.13), Color(0.18, 0.22, 0.4), Color(0.4, 0.3, 0.2)], "sash": [OCHRE, LEATHER],
		"troops": [
			{"name": "spearman", "right": "spear", "left": "shield", "shield": "rect", "wear": [["top_short", "cloth"], ["skirt_long", "cloth", "hem"], ["sash", "sash"]], "head": [["helmet", BRONZE]]},
			{"name": "swordsman", "right": "sword_short", "left": "shield", "shield": "round", "wear": [["top_short", "cloth"], ["skirt_long", "cloth", "hem"], ["sash", "sash"], ["vest", BRONZE]], "head": [["helmet", BRONZE]]},
			{"name": "maceman", "right": "mace", "left": "shield", "shield": "round", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"], ["vest", LEATHER], ["leg_wraps", LEATHER]], "head": [["helmet", BRONZE]]},
			{"name": "axeman", "right": "axe", "wear": [["top_short", "cloth"], ["skirt_long", "cloth", "hem"], ["sash", "sash"], ["vest", LEATHER]], "head": [["cap", LEATHER]]},
		],
		"slinger": {"name": "slinger", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"]], "head": [["cap", LEATHER]]},
		"champion": {"name": "champion", "right": "mace", "left": "shield", "shield": "round", "wear": [["top_short", "cloth"], ["skirt_long", "cloth", "hem"], ["sash", "sash"], ["vest", BRONZE], ["bracers", BRONZE]], "head": [["helmet", BRONZE]]},
		"chief": {"name": "king", "right": "sword", "left": "shield", "shield": "round", "wear": [["top_short", PURPLE], ["skirt_long", PURPLE, "hem"], ["sash", GOLD], ["vest", BRONZE], ["bracers", BRONZE], ["mantle", RED], ["cloak", RED]], "head": [["helmet", BRONZE], ["crown", GOLD]]},
	},
	"Midianite": {
		"cloth": [Color(0.7, 0.4, 0.2), Color(0.3, 0.32, 0.5), UNDYED, Color(0.55, 0.2, 0.2)], "sash": [RED, OCHRE, BLUE],
		"troops": [
			{"name": "warrior", "right": "dagger", "left": "shield", "shield": "hide", "wear": [["skirt_short", "cloth", "stripes"], ["sash", "sash"], ["necklace", GOLD]], "head": [["cap", LINEN], ["band", "sash"]]},
			{"name": "spearman", "right": "spear", "left": "shield", "shield": "hide", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "stripes"], ["sash", "sash"]], "head": [["cap", LINEN], ["shawl", LINEN], ["band", "sash"]]},
			{"name": "raider", "right": "dagger", "wear": [["skirt_long", "cloth", "stripes"], ["sash", "sash"], ["mantle", "sash"], ["necklace", GOLD]], "head": [["band_wide", "sash"]], "hair": 2},
		],
		"slinger": {"name": "slinger", "wear": [["skirt_short", "cloth", "stripes"], ["sash", "sash"]], "head": [["cap", LINEN], ["band", "sash"]]},
		"champion": {"name": "champion", "right": "sickle", "left": "shield", "shield": "hide", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "stripes"], ["sash", "sash"], ["vest", HIDE], ["mantle", "sash"], ["necklace", GOLD]], "head": [["cap", LINEN], ["shawl", LINEN], ["band", "sash"]]},
		"chief": {"name": "king", "right": "sickle", "left": "shield", "shield": "hide", "wear": [["top_long", PURPLE], ["skirt_long", PURPLE, "stripes"], ["sash", GOLD], ["mantle", PURPLE], ["cloak", PURPLE], ["necklace", GOLD]], "head": [["cap", LINEN], ["shawl", LINEN], ["crown", GOLD]]},
	},
	"Edomite": {
		"cloth": [RUST, OCHRE, UNDYED, Color(0.55, 0.26, 0.16)], "sash": [RED, HIDE, DARK_WOOL],
		"troops": [
			{"name": "spearman", "right": "spear", "left": "shield", "shield": "hide", "wear": [["skirt_short", "cloth", "stripes"], ["sash", "sash"]], "head": [["cap", "cloth"], ["band", "sash"]]},
			{"name": "axeman", "right": "axe", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "stripes"], ["sash", "sash"]], "head": [["cap", "cloth"], ["shawl", "cloth"], ["band", "sash"]]},
			{"name": "clubman", "right": "club", "left": "shield", "shield": "hide", "wear": [["skirt_short", "cloth", "stripes"], ["sash", "sash"], ["mantle", "sash"]], "head": [["band_wide", "sash"]], "hair": 2},
		],
		"slinger": {"name": "slinger", "wear": [["skirt_short", "cloth", "stripes"], ["sash", "sash"]], "head": [["cap", "cloth"], ["band", "sash"]]},
		"champion": {"name": "champion", "right": "sickle", "left": "shield", "shield": "hide", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "stripes"], ["sash", "sash"], ["vest", HIDE], ["bracers", LEATHER]], "head": [["cap", LINEN], ["shawl", LINEN], ["band", RED]]},
		"chief": {"name": "chief", "right": "sickle", "left": "shield", "shield": "hide", "wear": [["top_short", RED], ["skirt_short", RED, "stripes"], ["sash", OCHRE], ["vest", HIDE], ["mantle", RUST], ["cloak", RUST]], "head": [["cap", LINEN], ["shawl", LINEN], ["band", RED]]},
	},
	"Moabite": {
		"cloth": [Color(0.46, 0.36, 0.26), OCHRE, BLUE, UNDYED], "sash": [RED, OCHRE, DARK_WOOL],
		"troops": [
			{"name": "spearman", "right": "spear", "left": "shield", "shield": "round", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"]], "head": [["band_wide", "sash"]], "hair": 1},
			{"name": "swordsman", "right": "sickle", "left": "shield", "shield": "round", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"], ["vest", LEATHER]], "head": [["cap", "cloth"], ["band", "sash"]]},
			{"name": "axeman", "right": "axe", "wear": [["top_short", "cloth"], ["skirt_long", "cloth", "hem"], ["sash", "sash"]], "head": [["cap", "cloth"], ["shawl", "cloth"]]},
		],
		"slinger": {"name": "slinger", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"]], "head": [["band_wide", "sash"]], "hair": 1},
		"champion": {"name": "champion", "right": "spear", "left": "shield", "shield": "round", "wear": [["top_short", "cloth"], ["skirt_short", "cloth", "hem"], ["sash", "sash"], ["vest", BRONZE], ["bracers", LEATHER]], "head": [["helmet", BRONZE]]},
		"chief": {"name": "king", "right": "sword", "left": "shield", "shield": "round", "wear": [["top_long", BLUE, "hem"], ["skirt_long", BLUE, "hem"], ["sash", GOLD], ["mantle", RED], ["cloak", RED]], "head": [["cap", LINEN], ["shawl", LINEN], ["crown", GOLD]]},
	},
}
const ANAK := {"name": "Son of Anak", "right": "spear_long", "left": "shield", "shield": "round",
	"wear": [["top_short", DARK_WOOL], ["skirt_short", DARK_WOOL], ["sash", LEATHER], ["vest", BRONZE], ["bracers", BRONZE], ["leg_wraps", BRONZE]], "head": [["helmet", BRONZE]]}


## The share of a blow a fighting man's armour stops, from what he wears: a bronze helmet, bronze
## scale on the body, a leather or hide jerkin, bronze on the arms or legs.
static func armour_of(soldier_dress: Dictionary) -> float:
	var a := 0.0
	for piece in soldier_dress.get("head", []):
		if str(piece[0]) == "helmet":
			a += 0.1
	for piece in soldier_dress.get("wear", []):
		var bronze: bool = piece.size() > 1 and piece[1] is Color and (piece[1] as Color).is_equal_approx(BRONZE)
		match str(piece[0]):
			"vest":
				a += 0.16 if bronze else 0.06
			"bracers", "leg_wraps":
				a += 0.03 if bronze else 0.01
	return a


## How one human enemy of `people` is dressed and armed: a troop from PEOPLES with "cloth_color"
## and "sash_color" picked from that people's colors. `kind` is the ENEMIES key.
static func soldier(people: String, kind: String, boss: bool, rng: RandomNumberGenerator) -> Dictionary:
	var p: Dictionary = PEOPLES.get(people, PEOPLES["Desert"])
	var troop: Dictionary
	if kind == "anak":
		troop = ANAK
	elif boss:
		troop = p["chief"]
	elif kind == "slinger":
		troop = p["slinger"]
	elif kind == "champion":
		troop = p["champion"]
	else:
		var troops: Array = p["troops"]
		troop = troops[rng.randi() % troops.size()]
	var out := troop.duplicate()
	out["cloth_color"] = (p["cloth"] as Array)[rng.randi() % (p["cloth"] as Array).size()]
	out["sash_color"] = (p["sash"] as Array)[rng.randi() % (p["sash"] as Array).size()]
	return out
