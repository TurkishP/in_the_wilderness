extends RefCounted
## The special places of each stage's land (scripts/places.gd builds them). Change anything here.
##
## Each place:
##   id       a name for the save (a place cleared or a landmark seen stays so for the journey)
##   name     shown when the scout comes to it, and on the map
##   kind     rest      water and shade: the waterskin is filled and the scout heals there
##            landmark  a place of the story: its passage is read on arrival, with experience
##            lair      a unique beast and its pack; cleared, it leaves its reward
##            ruin      something built by others, guarded, with goods lying about
##   ref      the scripture it comes from ("" when it is invented or from archaeology)
##   text     read when the scout first comes there
##   where    how its place in the land is found (the same every visit):
##              {"dist": [least, most]}   anywhere that far from the camp
##              {"sea": metres}           this far short of the nearest shore
##              {"high": [least, most]}   the highest ground that far from the camp
##              {"foot": height}          where the ground first rises this high toward the
##                                        mountain (the highest ground near the camp)
##              {"brook": [top, foot]}    down the mountain's flank, from ground this high to this
##   build    what is built there (see scripts/places.gd): oasis, wreckage, split_rock, altar,
##            mines, bounds, brook, ledge
##   ground   how the ground is shaped round it: basin {r, depth}, hill {r, height}, flat {r},
##            gully (along a brook)
##   radius   how near counts as being there
##   guards   {enemy kind: how many}, roaming about it
##   unique   its one guardian: {kind, name, scale, hp, dmg (multipliers), color}
##   loot     [[item id, how many]] lying about it until it is cleared
##   reward   what clearing it leaves: {item (an id, or "rare" for one from the rare table at the
##            land's tier), bronze, silver}
##   xp       experience for a landmark seen, or a lair or ruin cleared (times the stage's mult)

const LIST := {
	# ---------------------------------------------------------------- 1  The Bitter Water
	0: [
		{"id": "elim", "name": "Elim", "kind": "rest", "ref": "Exodus 15:27",
			"text": "\"And they came to Elim, where were twelve wells of water, and threescore and ten palm trees: and they encamped there by the waters.\"",
			"where": {"dist": [120.0, 175.0]}, "build": "oasis", "ground": [{"kind": "basin", "r": 30.0, "depth": 1.2}], "radius": 22.0},
		{"id": "shore", "name": "The shore of the crossing", "kind": "ruin", "ref": "Exodus 14:30-31",
			"text": "\"Thus the LORD saved Israel that day out of the hand of the Egyptians; and Israel saw the Egyptians dead upon the sea shore.\"\n\nThe sea has given back broken chariots, shields and spears. Scavengers have found them first.",
			"where": {"sea": 12.0}, "build": "wreckage", "ground": [{"kind": "flat", "r": 16.0}], "radius": 16.0,
			"guards": {"jackal": 3, "hyena": 1},
			"unique": {"kind": "hyena", "name": "The scarred old hyena", "scale": 1.25, "hp": 3.0, "dmg": 1.4, "color": Color(0.58, 0.55, 0.48)},
			"loot": [["spear", 1]], "reward": {"item": "khopesh", "bronze": 3}, "xp": 50},
	],
	# ---------------------------------------------------------------- 2  Bread from Heaven
	1: [
		{"id": "horeb_rock", "name": "The rock in Horeb", "kind": "rest", "ref": "Exodus 17:5-6",
			"text": "\"Behold, I will stand before thee there upon the rock in Horeb; and thou shalt smite the rock, and there shall come water out of it, that the people may drink.\"",
			"where": {"dist": [90.0, 150.0]}, "build": "split_rock", "ground": [{"kind": "flat", "r": 14.0}], "radius": 14.0},
		{"id": "raised_hands", "name": "The hill of the raised hands", "kind": "landmark", "ref": "Exodus 17:10-16",
			"text": "\"And it came to pass, when Moses held up his hand, that Israel prevailed: and when he let down his hand, Amalek prevailed. But Moses' hands were heavy; and they took a stone, and put it under him, and he sat thereon; and Aaron and Hur stayed up his hands.\"\n\n\"And Moses built an altar, and called the name of it Jehovah-nissi.\" (The LORD is my banner.)",
			"where": {"dist": [110.0, 170.0]}, "build": "altar", "ground": [{"kind": "hill", "r": 26.0, "height": 6.5}], "radius": 9.0, "xp": 40},
		{"id": "turquoise", "name": "The turquoise mines", "kind": "ruin", "ref": "",
			"text": "Egypt's turquoise mines, worked for centuries by expeditions sent from the Nile. Beside the galleries stands the temple of Hathor, whom the miners called Lady of the Turquoise, among upright stones cut with the names of kings.\n\nA clan of striped hyenas has made the galleries its den.",
			"where": {"dist": [130.0, 180.0]}, "build": "mines", "ground": [{"kind": "flat", "r": 20.0}], "radius": 20.0,
			"guards": {"hyena": 2},
			"unique": {"kind": "hyena", "name": "The hyena matriarch", "scale": 1.3, "hp": 3.5, "dmg": 1.5, "color": Color(0.74, 0.69, 0.58)},
			"loot": [["turquoise", 4]], "reward": {"item": "rare", "silver": 20}, "xp": 60},
	],
	# ---------------------------------------------------------------- 3  The Mountain
	2: [
		{"id": "bounds", "name": "The bounds of the mountain", "kind": "landmark", "ref": "Exodus 19:12-13",
			"text": "\"And thou shalt set bounds unto the people round about, saying, Take heed to yourselves, that ye go not up into the mount, or touch the border of it.\"\n\nA line of set stones runs along the mountain's foot.",
			"where": {"foot": 7.0}, "build": "bounds", "radius": 10.0, "xp": 40},
		{"id": "brook", "name": "The brook from the mountain", "kind": "rest", "ref": "Deuteronomy 9:21",
			"text": "\"And I took your sin, the calf which ye had made, and burnt it with fire, and stamped it, and ground it very small, even until it was as small as dust: and I cast the dust thereof into the brook that descended out of the mount.\"",
			"where": {"brook": [22.0, 4.0]}, "build": "brook", "ground": [{"kind": "gully", "w": 7.0, "depth": 2.2}], "radius": 12.0},
		{"id": "leopard_ledge", "name": "The grey leopard's ledge", "kind": "lair", "ref": "",
			"text": "A ledge high on the mountain's flank, with a cave behind it. Shepherds say a grey leopard lives there, larger than any other.",
			"where": {"high": [80.0, 175.0]}, "build": "ledge", "radius": 12.0,
			"unique": {"kind": "leopard", "name": "The grey leopard", "scale": 1.3, "hp": 3.0, "dmg": 1.4, "color": Color(0.66, 0.65, 0.62)},
			"reward": {"item": "rare", "loot": "leopard_skin"}, "xp": 60},
	],
}


## The places of the land of stage `index` (0 for the first).
static func for_stage(index: int) -> Array:
	return LIST.get(index, [])
