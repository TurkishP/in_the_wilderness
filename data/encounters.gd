extends RefCounted
## What the scout may meet out in the wilds (scripts/encounters.gd runs it). Change anything here.
##
## Once the scout is FAR metres beyond the tents, an encounter comes after FIRST seconds of
## wandering, and after each one GAP seconds more (at random between the two numbers). Only one
## at a time. KINDS says how often it is beasts, a band of fighting men, or a trading caravan.
## An encounter the scout walks LEAVE metres away from is left behind, and goes.
##
## BEASTS and BANDS: one line is picked by weight among those whose stages (first and last, 0 for
## the first stage) take in the current stage.
##   kind     the animal (a key of data/enemies.gd); count [least, most] of them
##   hunt     true: they come for the scout from far off. false: they keep to where they are
##            and only go for the scout who comes close.
##   say      what the scout is told; %s is the direction it lies in
##   people   a people of data/enemies.gd PEOPLES; their men come in bands of BAND_SIZE

const FAR := 85.0
const FIRST := [35.0, 60.0]
const GAP := [70.0, 150.0]
const LEAVE := 110.0
const KINDS := {"beasts": 6.0, "band": 3.0, "caravan": 1.0}

## Where each animal is believed to have lived in the time of the Exodus. Wolves, striped hyenas,
## jackals and leopards ranged over all of Sinai, the Negev, the Arabah and Transjordan into the
## last two centuries. Lions lived in the southern Levant until the Middle Ages; the Bible places
## them in the thickets of the Jordan (Jeremiah 49:19) and the hill country (Judges 14:5,
## 1 Samuel 17:34), so here they come from Kadesh and the Negev on. The Syrian brown bear lived in
## the wooded highlands (1 Samuel 17:34, 2 Kings 2:24), so it comes only in Gilead, Bashan and
## the heights of Moab.
const BEASTS := [
	{"kind": "wolf", "count": [2, 4], "weight": 5.0, "stages": [0, 9], "hunt": true, "say": "Wolves! A pack is closing in from the %s."},
	{"kind": "jackal", "count": [3, 5], "weight": 3.0, "stages": [0, 9], "hunt": true, "say": "Jackals come yapping out of the %s."},
	{"kind": "hyena", "count": [1, 2], "weight": 4.0, "stages": [0, 9], "hunt": false, "say": "A striped hyena is skulking to the %s."},
	{"kind": "leopard", "count": [1, 1], "weight": 2.0, "stages": [0, 9], "hunt": true, "say": "Something is creeping up on you from the %s..."},
	{"kind": "lion", "count": [1, 1], "weight": 1.5, "stages": [4, 9], "hunt": true, "say": "A lion! It is stalking you from the %s."},
	{"kind": "bear", "count": [1, 1], "weight": 2.0, "stages": [8, 9], "hunt": false, "say": "A bear stands up to look at you, to the %s."},
]

## The peoples whose men might be met on the way, and where. Amalek fought Israel at Rephidim
## and again at Hormah (Exodus 17, Numbers 14:45). Midian ranged from Sinai to Moab (Exodus 2-3,
## 18; Numbers 22, 25, 31). Edom turned Israel back from its border near Kadesh (Numbers 20:14-21).
## Moab is passed at the end (Numbers 21-25); Canaanites came out from Arad (Numbers 21:1); the
## Amorites are Sihon's and Og's (Numbers 21:21-35).
const BANDS := [
	{"people": "Amalekite", "weight": 3.0, "stages": [0, 5]},
	{"people": "Midianite", "weight": 2.0, "stages": [0, 9]},
	{"people": "Edomite", "weight": 3.0, "stages": [4, 7]},
	{"people": "Canaanite", "weight": 2.0, "stages": [4, 6]},
	{"people": "Moabite", "weight": 3.0, "stages": [7, 9]},
	{"people": "Amorite", "weight": 2.0, "stages": [8, 9]},
]
const BAND_SIZE := [2, 4]
const BAND_CHAMPION := 0.15    # how often a champion of theirs leads them

## The trading caravans: Ishmaelites and Midianites, whom Genesis 37:25-28 has carrying goods
## between Gilead and Egypt. Their animals are donkeys: the camel was not yet a beast of burden in
## the region (dromedaries first appear at the copper mines of the Arabah about 930 BC), and
## donkey caravans are what Egyptian art of the time shows. They sell only rare pieces (the "rare"
## table of data/drops.gd), RARE in number; legendary weapons are never for sale. The price is what
## ordinary gear of the piece's tier would cost, times PRICE.
const CARAVAN := {
	"peoples": ["Ishmaelite", "Midianite"],
	"rare": [2, 3],
	"price": [1.0, 2.0, 3.5],
}


## What a caravan asks for a find of `tier` and `rarity` (1 rare, 2 legendary), before bargaining.
static func price_of(tier: int, rarity: int) -> int:
	return int((60 + 70 * tier) * float(CARAVAN["price"][clampi(rarity, 0, 2)]))
