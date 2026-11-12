extends RefCounted
## What ordinary people in the camp say when spoken to.
##
## Each stage has lines for anyone ("any"), for men, for women and for children. They are
## invented remarks by unnamed people, but what they refer to is taken from the passage the
## stage covers (the reference is given beside each group). Nothing here is put in the mouth
## of a biblical figure; where a line reports what such a person said or did, it follows the
## text. EVERYDAY lines fit any stage.

const EVERYDAY := {
	"any": [
		"Peace to you.",
		"Mind the tent ropes.",
		"Have you eaten today?",
		"The goats got into the bedding again.",
		"You are one of the scouts, are you not? Keep your eyes open out there.",
	],
	"man": [
		"I am splicing a tent rope. It never ends.",
		"The flock needs moving to better ground before evening.",
		"My turn on the night watch. I will sleep tomorrow.",
	],
	"woman": [
		"The water will not carry itself.",
		"I am looking for my youngest. If you see a small boy with a stick, send him home.",
		"We air the bedding while the sun is up.",
	],
	"child": [
		"Catch me if you can!",
		"I found a lizard. Do you want to see it?",
		"I am not lost. I know exactly where our tent is. It is... that way.",
	],
}

## Said by people busy with something, whatever the stage. Keyed by the work they are doing.
const WORK := {
	"fire": [
		"Sit a while. The fire is free.",
		"In the evening we tell the old stories here: Abraham, Isaac and Jacob, and Joseph in Egypt.",
		"My feet ache. Do yours?",
	],
	"weave": [
		"Goat hair for tent cloth. A whole tent is a year of evenings.",
		"Keep the warp tight, my mother said. I say it to my daughters now.",
	],
	"spin": [
		"The spindle never stops. Even on the march I spin as I walk.",
		"Wool for a cloak, before the cold nights come.",
	],
	"grind": [
		"Grind it fine or the cakes crumble.",
		"Two stones and a strong back. That is all a mill is.",
	],
	"cook": [
		"It will be ready when it is ready.",
		"Stir, taste, wait. Go and wash your hands.",
	],
	"arms": [
		"A blade is no use dull. I work the edge every day.",
		"Sling stones should be round and smooth. I pick them out of the dry stream beds.",
		"These spear shafts are acacia. Hard to cut, and hard to break.",
	],
	"mend": [
		"A frayed rope brings the tent down in the first wind.",
		"I am carving tent pegs. You can never have too many.",
	],
}

const STAGES := [
	# 1. Wilderness of Shur, two days from the sea (Exodus 12:34-39; 13:19-22; 14-15)
	{
		"any": [
			"Two days since the sea, and not one well. My tongue is like leather.",
			"Look west. You can still see the water. I keep turning round to look.",
			"They carry the bones of Joseph with us, as he made our fathers swear.",
			"I still hear the sea closing over the chariots. I do not think I will ever stop hearing it.",
			"We sang on the far shore until we were hoarse. Nobody is singing now.",
			"The cloud goes ahead of us by day and the fire by night. So we follow.",
		],
		"man": [
			"My father made bricks, and his father before him. I do not know what I am now.",
			"The flocks are suffering worse than we are. If we do not find water soon I will lose the ewes.",
			"In Egypt we had water and no freedom. I would still not go back. Ask me again tomorrow.",
			"The Egyptians gave us silver and gold as we left. What use is silver with no water?",
		],
		"woman": [
			"Miriam and the women danced with timbrels on the shore, and I danced too. My feet remember, even with a dry throat.",
			"I am saving the last cupful for the little ones.",
			"We left in such haste that the dough had no time to rise. I carried the kneading bowl on my shoulder.",
		],
		"child": [
			"Are we there yet? Mother says not to ask.",
			"I saw the water stand up like a wall. Like a WALL.",
			"I am thirsty.",
		],
	},
	# 2. Wilderness of Sin and Rephidim (Exodus 16-17; Deuteronomy 25:17-18)
	{
		"any": [
			"We called it 'What is it?' because nobody knew. The name has stuck.",
			"It tastes like wafers made with honey. I did not expect that.",
			"An omer for each of us, no more and no less. Somehow it always comes out even.",
			"Moses struck the rock at Horeb and water came out of it. I drank it. It was cold.",
		],
		"man": [
			"The Amalekites went for the stragglers at the rear, the tired and the weak. Cowards.",
			"I fought in the valley while Moses stood on the hill. When his hands dropped, we were pushed back. I saw it.",
			"Some went out on the seventh day to gather and found nothing. They looked like fools.",
		],
		"woman": [
			"On the sixth day we gather double and it keeps. Any other day it is crawling by morning.",
			"Quail in the evening, covering the camp. I have never plucked so many birds.",
			"I bake it or I boil it. The children prefer it baked.",
		],
		"child": [
			"The bread comes down with the dew! I get up first to see it.",
			"It melts when the sun gets hot, so you have to be quick.",
			"My brother kept some under his mat. It STANK.",
		],
	},
	# 3. Sinai (Exodus 19-40)
	{
		"any": [
			"The mountain shook, and there was a sound like a trumpet, louder and louder. We stood far off.",
			"We told Moses: you speak to us and we will listen, but do not let God speak to us, or we will die.",
			"They had to tell us to stop bringing gifts for the tent. There was more than enough.",
			"No one goes near the mountain. There is a boundary, and it is kept.",
		],
		"man": [
			"I gave my gold earrings for the calf. I do not like to speak of it.",
			"When Moses came down, his face shone. He wears a veil now when he is among us.",
			"Bezalel can work gold, silver, bronze, stone and wood. I can make bricks.",
		],
		"woman": [
			"I spun goat hair for the curtains. Every woman who could spin did.",
			"The women who serve at the entrance gave their bronze mirrors for the basin. I gave mine.",
			"Blue, purple and scarlet yarn, and fine linen. I have never handled such thread.",
		],
		"child": [
			"There was fire on top of the mountain. I hid under the blanket.",
			"We are not allowed to touch the mountain. Not even the goats.",
			"Father is carving pegs for the tent. He lets me hold the mallet.",
		],
	},
	# 4. From Sinai to Paran (Numbers 9-12)
	{
		"any": [
			"When the cloud lifts we strike the tents, and when it settles we pitch them. A day, a month, a year: we wait on the cloud.",
			"Two silver trumpets now. At the first alarm the camps on the east side set out.",
			"The ark goes ahead of us to find a place to rest.",
			"We waited seven days for Miriam before the camp moved on.",
		],
		"man": [
			"The fish we ate in Egypt cost nothing. The cucumbers, the melons, the leeks... Do not tell the elders I said that.",
			"Fire broke out at the edge of the camp when the complaining began. They named the place Taberah.",
			"Seventy elders share the burden with Moses now.",
		],
		"woman": [
			"I grind it in the handmill or beat it in the mortar, and boil it in the pot. It tastes like cakes baked with oil.",
			"The wind brought quail from the sea, a day's walk deep on every side. Then the sickness came.",
			"Every family at the door of its tent, weeping for meat. I was ashamed, and I was weeping too.",
		],
		"child": [
			"Manna again.",
			"I carry the tent pegs. That is my job when we march.",
			"The trumpets are so loud!",
		],
	},
	# 5. Kadesh and the spies (Numbers 13-14)
	{
		"any": [
			"Forty days they were gone. We counted every one.",
			"Two men carried one cluster of grapes on a pole between them. I saw it with my own eyes.",
			"They said it flows with milk and honey, and then they said we cannot take it.",
			"The whole camp wept that night.",
		],
		"man": [
			"The spies said we looked like grasshoppers beside them. Grasshoppers.",
			"Some are saying we should choose a leader and go back to Egypt. I said nothing. I am not proud of that.",
			"Caleb said we are well able to take it. One voice, with ten against him.",
		],
		"woman": [
			"Pomegranates and figs. I had forgotten what fruit smells like.",
			"Forty years. My children will see the land, and I will not.",
			"They went up to the hill country anyway, without the ark. Not all of them came back.",
		],
		"child": [
			"The grapes were THIS big.",
			"Father says there are giants. Are there giants?",
			"Why is everyone crying?",
		],
	},
	# 6. The wandering years (Numbers 15-19; Deuteronomy 2:14; 8:2-4; 29:5)
	{
		"any": [
			"My sandals have not worn out in all these years. Explain that to me.",
			"We wear tassels on the corners of our garments, with a cord of blue, so that we look at them and remember.",
			"The ground opened under the tents of Korah's company. I was standing as near as you are to me.",
			"Aaron's staff put out buds and blossoms and ripe almonds in a single night.",
		],
		"man": [
			"I was a young man at the sea. Look at my beard now.",
			"We have buried most of those who came out of Egypt. My father is among them.",
			"I teach my sons the words every evening. They will need them more than I do.",
		],
		"woman": [
			"My daughter was born under the cloud. She has never seen a city.",
			"Manna every morning, for all these years. I no longer complain about it.",
			"My feet have not swollen in all these years of walking.",
		],
		"child": [
			"Grandfather tells about Egypt. It sounds like a story.",
			"I can pitch a tent faster than my brother.",
			"What is a river?",
		],
	},
	# 7. Kadesh to Mount Hor (Numbers 20:1-21:3)
	{
		"any": [
			"Miriam is buried here at Kadesh.",
			"We offered to keep to the King's Highway and pay for any water we drank. Edom still came out against us with an army.",
			"Thirty days we wept for Aaron.",
			"Eleazar wears his father's garments now.",
		],
		"man": [
			"The water came from the rock again, enough for us and the cattle. But something went wrong up there. Moses has not been the same since.",
			"The king of Arad took some of ours captive on the road. We will get them back.",
			"Edom is our brother, and he met us with the sword.",
		],
		"woman": [
			"I remember Miriam with her timbrel on the shore. I was a girl then.",
			"Three went up the mountain, and two came down.",
			"My sister's boy was taken on the road. Bring him home.",
		],
		"child": [
			"Why can we not just walk through Edom?",
			"Everyone is sad again.",
			"I am almost tall enough to carry a spear.",
		],
	},
	# 8. Around Edom (Numbers 21:4-9)
	{
		"any": [
			"The long way round, because Edom would not let us pass.",
			"We spoke against God and against Moses, and then the serpents came.",
			"Moses set a serpent of bronze on a pole. I was bitten, I looked, and I am standing here.",
			"Watch where you step. And where you sleep.",
		],
		"man": [
			"I called the manna worthless food. I would take those words back if I could.",
			"We went to Moses and said: we have sinned. Pray that the serpents be taken away.",
			"I shake out my bedding twice now.",
		],
		"woman": [
			"I carried my son to where he could see the pole. That was all it took. He looked.",
			"Many died before the bronze serpent was made.",
			"I keep the children inside the tent ropes after dark.",
		],
		"child": [
			"I saw a red one! Over there! ...It was a rope.",
			"It stopped hurting after I looked.",
			"Are there snakes where we are going?",
		],
	},
	# 9. Sihon and Og (Numbers 21:10-35; Deuteronomy 2-3)
	{
		"any": [
			"At Beer the leaders dug with their staffs and we sang: Spring up, O well!",
			"We asked Sihon for the road and offered to pay for water, as we asked Edom. He chose to fight.",
			"Heshbon is ours now, the city of Sihon.",
			"They say the bed of Og is iron, nine cubits long and four wide.",
		],
		"man": [
			"My father died in the wilderness without ever drawing a sword. I have fought two kings in a season.",
			"Sixty walled cities in Bashan, with gates and bars.",
			"The cattle and the spoil of the towns we kept for ourselves.",
		],
		"woman": [
			"Fields. Real fields, with standing grain. I had only heard of them.",
			"The men came back from Edrei singing.",
			"We have settled in the towns of the Amorites. I have never slept inside a wall before.",
		],
		"child": [
			"How big is nine cubits? Bigger than our tent?",
			"I helped sing the well song.",
			"There are so many cows here.",
		],
	},
	# 10. The plains of Moab (Numbers 22-36; Deuteronomy 31-34)
	{
		"any": [
			"A king hired a seer to curse us from those heights, and three times it came out a blessing.",
			"They say the seer looked down on our camp and said: how lovely are your tents, O Jacob.",
			"They counted us again. Of those counted at Sinai, only Caleb and Joshua are left.",
			"That is Jericho, across the water. The city of palm trees.",
		],
		"man": [
			"Twenty-four thousand died over the matter of Peor. I lost a brother.",
			"Reuben and Gad are building folds for their flocks here, but their fighting men will cross over ahead of us.",
			"Moses laid his hands on Joshua before the whole congregation.",
		],
		"woman": [
			"The daughters of Zelophehad stood before Moses and asked for their father's portion. And they were given it.",
			"Moses speaks to us every day now. He is telling us everything again, so that we will not forget.",
			"He will not cross over with us. He told us so himself.",
		],
		"child": [
			"Is that the land? Right there? Why are we waiting?",
			"The river is too wide. Father says we will cross anyway.",
			"I have never eaten anything but manna. What does bread taste like?",
		],
	},
]


## Everything a person of kind `who` ("man", "woman" or "child") might say at this stage:
## about their work if they have any, then the stage's lines, then the everyday ones.
static func lines_for(stage_index: int, who: String, work: String = "") -> Array:
	var stage: Dictionary = STAGES[clampi(stage_index, 0, STAGES.size() - 1)]
	var out: Array = []
	out.append_array(WORK.get(work, []))
	out.append_array(stage["any"])
	out.append_array(stage.get(who, []))
	out.append_array(EVERYDAY["any"])
	out.append_array(EVERYDAY.get(who, []))
	return out
