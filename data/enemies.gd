extends RefCounted
## Enemy table. hp and dmg are stage-1 values; each stage multiplies them.
## "reach" is melee reach in metres, or firing range for ranged enemies.

const ENEMIES := {
	"snake": {"name": "Desert viper", "shape": "snake", "hp": 18.0, "dmg": 8.0, "speed": 5.2, "reach": 1.5, "aggro": 11.0, "radius": 0.45, "color": Color(0.62, 0.52, 0.3), "silver": [0, 2]},
	"scorpion": {"name": "Scorpion", "shape": "scorpion", "hp": 30.0, "dmg": 12.0, "speed": 3.0, "reach": 1.5, "aggro": 9.0, "radius": 0.5, "color": Color(0.25, 0.18, 0.12), "silver": [0, 3]},
	"jackal": {"name": "Jackal", "shape": "beast", "hp": 24.0, "dmg": 9.0, "speed": 6.4, "reach": 1.7, "aggro": 16.0, "radius": 0.5, "color": Color(0.6, 0.48, 0.3), "silver": [0, 0]},
	"fiery_serpent": {"name": "Fiery serpent", "shape": "snake", "hp": 28.0, "dmg": 16.0, "speed": 6.0, "reach": 1.6, "aggro": 14.0, "radius": 0.5, "color": Color(0.85, 0.3, 0.1), "silver": [0, 4]},
	"raider": {"name": "Raider", "shape": "human", "hp": 55.0, "dmg": 14.0, "speed": 4.7, "reach": 2.0, "aggro": 18.0, "radius": 0.45, "color": Color(0.45, 0.2, 0.15), "silver": [3, 9]},
	"slinger": {"name": "Slinger", "shape": "human", "hp": 38.0, "dmg": 10.0, "speed": 4.3, "reach": 17.0, "aggro": 22.0, "radius": 0.45, "color": Color(0.3, 0.32, 0.2), "silver": [3, 9], "ranged": true},
	"anak": {"name": "Son of Anak", "shape": "human", "hp": 240.0, "dmg": 30.0, "speed": 3.8, "reach": 2.2, "aggro": 20.0, "radius": 0.5, "scale": 1.7, "color": Color(0.35, 0.3, 0.28), "silver": [15, 30]},
	"boss": {"name": "Chief", "shape": "human", "hp": 380.0, "dmg": 24.0, "speed": 4.4, "reach": 2.0, "aggro": 26.0, "radius": 0.45, "scale": 1.35, "color": Color(0.55, 0.1, 0.1), "silver": [40, 70]},
}
