extends RefCounted
## The weapon skill trees: one for each family of weapons, learned by using it. Change anything
## here; the numbers each skill uses are its "v" (and "t", seconds, where it lasts a while).
##
## "icon" is the skill's picture on the lampstand: one of those drawn in scripts/skill_icons.gd,
## or two joined by "+" (the second small, as a badge).
##
## Learning by use: every blow that lands with a weapon (a stone or an arrow that strikes counts
## the same) gives its family BLOW, felling an enemy KILL, a champion, chief or son of Anak
## GREAT_KILL. When that reaches the next step (the first needs STEP_FIRST, each after STEP_MORE
## more than the last, up to MAX_STEPS) the tree gets a point. Levels give stat points, not these.
##
## A skill costs COST[tier] points. A tier opens when OPENS[tier] points have been spent in that
## tree; the capstone (tier 4) also needs CAPSTONE_LEVEL. Points once spent stay spent.
##
## Which blow is which, where a skill names one: the first blow of a combo (A), the second (B),
## the third (C). Sickle sword: A the hook, B the low sweep, C the overhead cut. Axe: B the level
## chop, C the great chop. Club and mace: A the slam, C the wide swing. Spear: C the lunge.
## Dagger: C the rising stab. Sword: B the sweep, C the diagonal cut.

const BLOW := 1
const KILL := 5
const GREAT_KILL := 25
const STEP_FIRST := 20
const STEP_MORE := 15
const MAX_STEPS := 12
const COST := [0, 1, 1, 2, 3]
const OPENS := [0, 0, 2, 5, 8]
const CAPSTONE_LEVEL := 12
const TIER_NAMES := ["", "Tier I", "Tier II", "Tier III", "Capstone"]

## The trees in the order the menu shows them. "styles": the weapon styles (HumanScript.STYLE_OF)
## whose blows train it.
const ORDER := ["sword", "dagger", "sickle", "axe", "club", "spear", "staff", "sling", "bow"]
const TREES := {
	"sword": {"name": "Sword", "title": "The Blade", "styles": ["sword"], "weapons": "Short sword, iron sword, long sword",
		"idea": "Balance: cuts that flow into each other.", "skills": [
		{"id": "measured_breath", "name": "Measured Breath", "icon": "wind", "tier": 1, "v": 0.2, "text": "Each blow's recovery is 20% shorter, so a combo flows without a pause."},
		{"id": "third_cut", "name": "Third Cut", "icon": "slashes3", "tier": 1, "v": 0.3, "text": "The diagonal cut that ends the combo does 30% more."},
		{"id": "riposte", "name": "Riposte", "icon": "blade+return", "tier": 2, "v": 0.6, "t": 1.5, "text": "After you slip a blow (Dexterity), your next sword blow within 1.5 s does 60% more."},
		{"id": "wide_sweep", "name": "Wide Sweep", "icon": "sweep", "tier": 2, "text": "The sweep reaches all round you, not just ahead."},
		{"id": "fourth_cut", "name": "Fourth Cut", "icon": "rising", "tier": 2, "v": 3.0, "text": "Adds a fourth blow to the combo: a rising cut that throws the enemy back."},
		{"id": "long_point", "name": "Long Point", "icon": "blade+motion", "tier": 3, "v": 1.0, "text": "Hold attack for a thrust that reaches a metre further."},
		{"id": "cleave_onward", "name": "Cleave Onward", "icon": "skull+chevrons", "tier": 3, "v": 0.3, "text": "A blow that kills makes your next blow land 30% sooner."},
		{"id": "captain", "name": "Captain of Thousands", "icon": "crown", "tier": 4, "v": 0.1, "t": 6.0, "ref": "Exodus 18:21", "text": "Each kill within 6 seconds of the last adds 10% damage and speed, up to three times."},
	]},
	"dagger": {"name": "Dagger", "title": "The Knife", "styles": ["dagger"], "weapons": "Flint knife, daggers",
		"idea": "Speed and closeness: strike first, strike where they are not looking.", "skills": [
		{"id": "quick_hands", "name": "Quick Hands", "icon": "dagger+chevrons", "tier": 1, "v": 0.15, "text": "Dagger blows land 15% sooner."},
		{"id": "low_strike", "name": "Low Strike", "icon": "dagger+return", "tier": 1, "v": 0.5, "text": "Blows from behind or the side do 50% more."},
		{"id": "second_knife", "name": "Second Knife", "icon": "cross_daggers", "tier": 2, "v": 0.5, "text": "With a dagger in the left hand as well, it joins every blow, not only the second."},
		{"id": "open_vein", "name": "Open Vein", "icon": "drop", "tier": 2, "v": 0.4, "t": 4.0, "text": "The rising stab bleeds: 40% of its damage again over 4 seconds."},
		{"id": "slip_away", "name": "Slip Away", "icon": "retreat", "tier": 2, "text": "Press jump during a stab to step back out of reach."},
		{"id": "thrown_knife", "name": "Thrown Knife", "icon": "dagger+motion", "tier": 3, "v": 1.2, "text": "Hold attack to throw the dagger; pick it up where it falls."},
		{"id": "finishing_stab", "name": "Finishing Stab", "icon": "skull", "tier": 3, "v": 0.2, "text": "An enemy under a fifth of its health dies to one stab (not chiefs)."},
		{"id": "unseen_blade", "name": "Unseen Blade", "icon": "eye_shut", "tier": 4, "v": 3.0, "text": "The first blow on an enemy that has not seen you does triple damage."},
	]},
	"sickle": {"name": "Sickle sword", "title": "The Hook", "styles": ["sickle"], "weapons": "Sickle swords and the khopesh",
		"idea": "Control: hook, pull, disarm.", "skills": [
		{"id": "hook_pull", "name": "Hook and Pull", "icon": "hook", "tier": 1, "text": "The hook pulls the enemy a step toward you and breaks its swing."},
		{"id": "crescent_edge", "name": "Crescent Edge", "icon": "crescent", "tier": 1, "v": 0.25, "text": "The overhead cut does 25% more."},
		{"id": "disarm", "name": "Disarm", "icon": "blade+x", "tier": 2, "v": 0.25, "text": "One hook in four tears a raider's weapon from his hand: he fights on with his fists."},
		{"id": "reaping_sweep", "name": "Reaping Sweep", "icon": "hook+hourglass", "tier": 2, "v": 0.5, "t": 3.0, "text": "The low sweep slows those it hits for 3 seconds."},
		{"id": "hooked_shield", "name": "Hooked Shield", "icon": "shield+hook", "tier": 2, "t": 2.0, "text": "A hooked enemy's shield is pulled aside: your next blow ignores it."},
		{"id": "royal_edge", "name": "Royal Edge", "icon": "hook+chevrons", "tier": 3, "v": 0.15, "text": "Sickle sword blows land 15% sooner."},
		{"id": "turn_blade", "name": "Turn the Blade", "icon": "hook+stars", "tier": 3, "t": 1.0, "text": "When you slip a blow (Dexterity), you hook the attacker's weapon and stagger him for a second."},
		{"id": "pharaohs", "name": "Blade of the Pharaohs", "icon": "slashes2+crown", "tier": 4, "t": 2.0, "text": "After a hook, your next blow within 2 seconds strikes twice."},
	]},
	"axe": {"name": "Axe", "title": "The Bite", "styles": ["axe"], "weapons": "Duckbill axe, iron war axe",
		"idea": "Weight in the edge: break what stands in front.", "skills": [
		{"id": "deep_bite", "name": "Deep Bite", "icon": "axe+plus", "tier": 1, "v": 0.25, "text": "25% more damage against enemies still above half their health."},
		{"id": "woodsman", "name": "Woodsman's Swing", "icon": "axe+chevrons", "tier": 1, "v": 0.1, "text": "Axe blows land 10% sooner."},
		{"id": "shield_splitter", "name": "Shield Splitter", "icon": "shield_broken", "tier": 2, "v": 2.0, "text": "Two axe blows on a raider's shield break it."},
		{"id": "wide_chop", "name": "Wide Chop", "icon": "axe+sweep", "tier": 2, "text": "The level chop hits all round you."},
		{"id": "rending_cut", "name": "Rending Cut", "icon": "axe+drop", "tier": 2, "v": 0.3, "t": 4.0, "text": "Chops bleed: 30% of the damage again over 4 seconds."},
		{"id": "heavy_cleave", "name": "Heavy Cleave", "icon": "axe+down", "tier": 3, "v": 0.8, "text": "Hold attack to raise the axe higher: 80% more damage, slower."},
		{"id": "armour_breaker", "name": "Armour Breaker", "icon": "helmet_broken", "tier": 3, "v": 0.34, "t": 8.0, "text": "Struck enemies lose a third of their armour for 8 seconds."},
		{"id": "felling_blow", "name": "Felling Blow", "icon": "axe+skull", "tier": 4, "v": 0.35, "text": "The great chop fells any enemy under 35% of its health outright; chiefs take 50% more."},
	]},
	"club": {"name": "Club and mace", "title": "The Weight", "styles": ["bludgeon"], "weapons": "Clubs, stone and bronze maces",
		"idea": "Shock: stop them, drive them back, knock them down.", "skills": [
		{"id": "stunning_blow", "name": "Stunning Blow", "icon": "stars", "tier": 1, "v": 2.0, "text": "The slam breaks the enemy's swing and drives it back twice as far."},
		{"id": "bone_crusher", "name": "Bone Crusher", "icon": "mace+helmet", "tier": 1, "v": 0.2, "text": "20% more damage against enemies in a helmet or scale."},
		{"id": "daze", "name": "Daze", "icon": "spiral", "tier": 2, "t": 1.5, "text": "The wide swing dazes those it hits for 1.5 seconds: they cannot strike."},
		{"id": "ground_shake", "name": "Ground Shake", "icon": "waves", "tier": 2, "v": 2.0, "text": "The slam knocks back every enemy within 2 metres."},
		{"id": "heavy_hand", "name": "Heavy Hand", "icon": "mace+chevrons", "tier": 2, "v": 0.2, "text": "Club and mace blows chain 20% sooner."},
		{"id": "cripple", "name": "Cripple", "icon": "hourglass", "tier": 3, "v": 0.3, "t": 4.0, "text": "Struck enemies move 30% slower for 4 seconds."},
		{"id": "unbroken", "name": "Unbroken", "icon": "shield_plus", "tier": 3, "v": 0.25, "text": "While you swing a club or mace, blows you take do 25% less."},
		{"id": "breaker_of_ranks", "name": "Breaker of Ranks", "icon": "waves+stars", "tier": 4, "v": 3.0, "t": 1.5, "text": "Every third blow that lands knocks down all enemies within 3 metres."},
	]},
	"spear": {"name": "Spear", "title": "The Reach", "styles": ["spear"], "weapons": "Hunting, bronze, raider's and iron spears; the spear of the Anakim",
		"idea": "Distance: strike first and keep them there.", "skills": [
		{"id": "long_reach", "name": "Long Reach", "icon": "spear+plus", "tier": 1, "v": 0.5, "text": "Half a metre more reach."},
		{"id": "first_strike", "name": "First Strike", "icon": "spear+target", "tier": 1, "v": 0.4, "text": "Your first blow on each enemy does 40% more."},
		{"id": "brace", "name": "Brace", "icon": "brace", "tier": 2, "t": 1.5, "text": "Standing still, an enemy that comes at you is struck before it can swing."},
		{"id": "quick_recovery", "name": "Quick Recovery", "icon": "spear+chevrons", "tier": 2, "v": 0.25, "text": "Thrusts chain 25% sooner."},
		{"id": "keep_away", "name": "Keep Away", "icon": "push", "tier": 2, "v": 2.0, "text": "Thrusts drive enemies back twice as far."},
		{"id": "hurl_spear", "name": "Hurl the Spear", "icon": "spear+motion", "tier": 3, "v": 2.0, "text": "Hold attack to throw the spear for double damage; walk over it to take it back."},
		{"id": "skewer", "name": "Skewer", "icon": "through", "tier": 3, "v": 2.5, "text": "Thrusts go on to hit a second enemy behind the first."},
		{"id": "through_both", "name": "Through Both", "icon": "through3", "tier": 4, "v": 0.5, "ref": "Numbers 25:7-8", "text": "The lunge runs through every enemy in a line, with 50% more damage."},
	]},
	"staff": {"name": "Staff", "title": "The Shepherd", "styles": ["staff"], "weapons": "Shepherd's staff, bronze-shod staff, Aaron's staff",
		"idea": "Endurance and control: drive off what threatens the flock.", "skills": [
		{"id": "walking_staff", "name": "Walking Staff", "icon": "staff+wind", "tier": 1, "v": 0.25, "text": "Stamina comes back 25% faster with a staff in hand."},
		{"id": "drive_back", "name": "Drive Them Back", "icon": "staff+push", "tier": 1, "v": 2.0, "text": "The butt thrust drives enemies twice as far back."},
		{"id": "ward_off", "name": "Ward Off", "icon": "shield", "tier": 2, "text": "The thrust breaks an enemy's swing."},
		{"id": "against_wolves", "name": "Against the Wolves", "icon": "paw", "tier": 2, "v": 2.0, "text": "Animals take double damage from the staff."},
		{"id": "stomp", "name": "Stomp", "icon": "stomp", "tier": 2, "v": 2.5, "t": 1.2, "text": "Press attack again during the thrust: the staff is lifted upright in both hands for a moment, then its butt is driven into the ground. Enemies within 2.5 metres are knocked off their feet or dazed, and take damage."},
		{"id": "heavy_stomp", "name": "Heavy Stomp", "icon": "stomp_big", "tier": 3, "v": 4.0, "t": 2.0, "text": "The stomp reaches 4 metres, and those it dazes stay dazed twice as long."},
		{"id": "steady_guard", "name": "Steady Guard", "icon": "staff+shield", "tier": 3, "v": 0.2, "text": "With the staff in hand, blows from the front do 20% less."},
		{"id": "shepherd", "name": "Shepherd of the Camp", "icon": "crook", "tier": 4, "v": 0.3, "t": 5.0, "text": "Each thrust that lands gives back 5 stamina and makes the next one 30% quicker."},
	]},
	"sling": {"name": "Sling", "title": "The Slinger", "styles": [], "weapons": "All slings",
		"idea": "Precision from afar, and never running short.", "skills": [
		{"id": "quick_whirl", "name": "Quick Whirl", "icon": "sling+chevrons", "tier": 1, "v": 0.3, "text": "The sling is ready to loose 30% sooner."},
		{"id": "smooth_stones", "name": "Smooth Stones", "icon": "stone+plus", "tier": 1, "v": 0.2, "text": "20% more sling damage."},
		{"id": "stone_gatherer", "name": "Stone Gatherer", "icon": "stones", "tier": 2, "v": 2.0, "text": "Stony ground gives 2 more stones."},
		{"id": "stunning_stone", "name": "Stunning Stone", "icon": "stone+stars", "tier": 2, "t": 1.0, "text": "A stone that strikes the head dazes for a second."},
		{"id": "long_cast", "name": "Long Cast", "icon": "stone+motion", "tier": 2, "v": 0.3, "text": "Stones fly 30% faster and further."},
		{"id": "thrifty", "name": "Thrifty", "icon": "stone+return", "tier": 3, "v": 0.34, "text": "One stone in three can be picked up again."},
		{"id": "second_stone", "name": "Second Stone", "icon": "stone+chevrons", "tier": 3, "t": 1.5, "text": "Right after a throw the sling is ready again, with no wind-up."},
		{"id": "hairs_breadth", "name": "Not a Hair's Breadth", "icon": "target", "tier": 4, "v": 3.0, "t": 1.5, "ref": "Judges 20:16", "text": "A stone whirled for 1.5 seconds does triple damage."},
	]},
	"bow": {"name": "Bow", "title": "The Archer", "styles": [], "weapons": "Hunting, composite, war and horn bows",
		"idea": "Power held at full draw.", "skills": [
		{"id": "steady_draw", "name": "Steady Draw", "icon": "bow+chevrons", "tier": 1, "v": 0.2, "text": "The bow draws 20% faster."},
		{"id": "keen_eye", "name": "Keen Eye", "icon": "eye", "tier": 1, "v": 0.15, "text": "15% more bow damage."},
		{"id": "gather_arrows", "name": "Gather Arrows", "icon": "arrow+return", "tier": 2, "v": 0.5, "text": "Half of your arrows can be taken back from where they fell."},
		{"id": "pinning_shot", "name": "Pinning Shot", "icon": "arrow+hourglass", "tier": 2, "v": 0.5, "t": 3.0, "text": "Arrows slow the enemy they strike for 3 seconds."},
		{"id": "power_draw", "name": "Power Draw", "icon": "bow+plus", "tier": 2, "v": 0.5, "t": 1.0, "text": "Held at full draw for a second: 50% more damage."},
		{"id": "quick_nock", "name": "Quick Nock", "icon": "arrows2", "tier": 3, "text": "Loose two arrows one after the other."},
		{"id": "through_gap", "name": "Through the Gap", "icon": "arrow+shield_broken", "tier": 3, "v": 0.5, "text": "Arrows ignore half the enemy's armour and shield."},
		{"id": "volley", "name": "Volley", "icon": "split", "tier": 4, "v": 3.5, "text": "A full-drawn arrow loosed high splits into three where it falls."},
	]},
}


## The tree a skill is in, and the skill: {"tree", "skill"}; {} for an unknown id.
static func find(id: String) -> Dictionary:
	for tree in ORDER:
		for s in TREES[tree]["skills"]:
			if str(s["id"]) == id:
				return {"tree": tree, "skill": s}
	return {}


## The experience a weapon needs, in all, to reach step `n` of its skill.
static func xp_for_step(n: int) -> int:
	return STEP_FIRST * n + STEP_MORE * n * (n - 1) / 2


## Which tree the blows of a weapon style ("sword", "bludgeon"...) train; "" for none.
static func tree_of_style(style: String) -> String:
	for tree in ORDER:
		if (TREES[tree]["styles"] as Array).has(style):
			return tree
	return ""
