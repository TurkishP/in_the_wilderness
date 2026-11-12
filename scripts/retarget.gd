extends RefCounted
## Converts animations from the Universal Animation Library rig (bones named "DEF-...") to the
## Universal Base Characters rig (bones named "pelvis", "spine_01", ...).
##
## The two rigs have different bone names, bone axes and proportions, so tracks cannot be
## copied. Instead every frame is rebuilt: for each bone we take how far the source bone has
## turned in model space since its T-pose, and apply the same turn to the target bone's rest
## pose (which is also a T-pose). Hips movement is scaled by the difference in hip height.

const BONE_MAP := {
	"DEF-hips": "pelvis",
	"DEF-spine.001": "spine_01", "DEF-spine.002": "spine_02", "DEF-spine.003": "spine_03",
	"DEF-neck": "neck_01", "DEF-head": "Head",
	"DEF-shoulder.L": "clavicle_l", "DEF-upper_arm.L": "upperarm_l", "DEF-forearm.L": "lowerarm_l", "DEF-hand.L": "hand_l",
	"DEF-shoulder.R": "clavicle_r", "DEF-upper_arm.R": "upperarm_r", "DEF-forearm.R": "lowerarm_r", "DEF-hand.R": "hand_r",
	"DEF-thigh.L": "thigh_l", "DEF-shin.L": "calf_l", "DEF-foot.L": "foot_l", "DEF-toe.L": "ball_l",
	"DEF-thigh.R": "thigh_r", "DEF-shin.R": "calf_r", "DEF-foot.R": "foot_r", "DEF-toe.R": "ball_r",
	"DEF-f_index.01.L": "index_01_l", "DEF-f_index.02.L": "index_02_l", "DEF-f_index.03.L": "index_03_l",
	"DEF-f_middle.01.L": "middle_01_l", "DEF-f_middle.02.L": "middle_02_l", "DEF-f_middle.03.L": "middle_03_l",
	"DEF-f_ring.01.L": "ring_01_l", "DEF-f_ring.02.L": "ring_02_l", "DEF-f_ring.03.L": "ring_03_l",
	"DEF-f_pinky.01.L": "pinky_01_l", "DEF-f_pinky.02.L": "pinky_02_l", "DEF-f_pinky.03.L": "pinky_03_l",
	"DEF-thumb.01.L": "thumb_01_l", "DEF-thumb.02.L": "thumb_02_l", "DEF-thumb.03.L": "thumb_03_l",
	"DEF-f_index.01.R": "index_01_r", "DEF-f_index.02.R": "index_02_r", "DEF-f_index.03.R": "index_03_r",
	"DEF-f_middle.01.R": "middle_01_r", "DEF-f_middle.02.R": "middle_02_r", "DEF-f_middle.03.R": "middle_03_r",
	"DEF-f_ring.01.R": "ring_01_r", "DEF-f_ring.02.R": "ring_02_r", "DEF-f_ring.03.R": "ring_03_r",
	"DEF-f_pinky.01.R": "pinky_01_r", "DEF-f_pinky.02.R": "pinky_02_r", "DEF-f_pinky.03.R": "pinky_03_r",
	"DEF-thumb.01.R": "thumb_01_r", "DEF-thumb.02.R": "thumb_02_r", "DEF-thumb.03.R": "thumb_03_r",
}
const SRC_HIPS := "DEF-hips"
const DST_HIPS := "pelvis"
const TPOSE := "A_TPose"
const FPS := 30.0


## Returns a library holding `names` converted for `dst`. `dst_path` is the path of the target
## skeleton relative to the node the AnimationPlayer treats as its root.
static func convert(src: Skeleton3D, src_player: AnimationPlayer, dst: Skeleton3D, names: Array, dst_path: String) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var n_src := src.get_bone_count()
	var n_dst := dst.get_bone_count()

	# Source reference pose: the library's T-pose animation, so both rigs start from the same shape.
	var ref_anim: Animation = src_player.get_animation(TPOSE) if src_player.has_animation(TPOSE) else null
	var ref: Array = _source_pose(src, ref_anim, 0.0)
	var ref_inv: Array = []
	for i in n_src:
		ref_inv.append((ref[i] as Transform3D).basis.inverse())
	var src_hips := src.find_bone(SRC_HIPS)
	var dst_hips := dst.find_bone(DST_HIPS)
	var hips_scale := dst.get_bone_global_rest(dst_hips).origin.y / maxf((ref[src_hips] as Transform3D).origin.y, 0.01)

	# Target rest pose and which source bone drives each target bone (-1 = stays at rest).
	var dst_rest_g: Array = []
	var driver: Array = []
	for j in n_dst:
		dst_rest_g.append(dst.get_bone_global_rest(j))
		driver.append(-1)
	for src_name in BONE_MAP:
		var i := src.find_bone(src_name)
		var j := dst.find_bone(BONE_MAP[src_name])
		if i >= 0 and j >= 0:
			driver[j] = i

	for anim_name in names:
		if not src_player.has_animation(anim_name):
			continue
		var a: Animation = src_player.get_animation(anim_name)
		var out := Animation.new()
		out.length = a.length
		out.loop_mode = a.loop_mode
		var rot_track: Array = []
		for j in n_dst:
			if driver[j] >= 0:
				var t := out.add_track(Animation.TYPE_ROTATION_3D)
				out.track_set_path(t, NodePath("%s:%s" % [dst_path, dst.get_bone_name(j)]))
				rot_track.append(t)
			else:
				rot_track.append(-1)
		var pos_track := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(pos_track, NodePath("%s:%s" % [dst_path, DST_HIPS]))

		var tracks := _track_index(src, a)
		var frames := maxi(1, int(ceil(a.length * FPS)))
		for f in frames + 1:
			var time := minf(a.length, f / FPS)
			var pose: Array = _source_pose(src, a, time, tracks)
			var g: Array = []   # target global transforms for this frame
			g.resize(n_dst)
			for j in n_dst:
				var parent := dst.get_bone_parent(j)
				var parent_g: Transform3D = g[parent] if parent >= 0 else Transform3D.IDENTITY
				var rest_g: Transform3D = dst_rest_g[j]
				var cur: Transform3D
				if driver[j] >= 0:
					var i: int = driver[j]
					var turn: Basis = (pose[i] as Transform3D).basis * (ref_inv[i] as Basis)
					cur.basis = turn * rest_g.basis
				else:
					cur.basis = parent_g.basis * dst.get_bone_rest(j).basis
				# Bones keep their rest offset from the parent; only the hips also translate.
				cur.origin = parent_g * dst.get_bone_rest(j).origin
				if j == dst_hips:
					var moved: Vector3 = (pose[src_hips] as Transform3D).origin - (ref[src_hips] as Transform3D).origin
					cur.origin = rest_g.origin + moved * hips_scale
					out.position_track_insert_key(pos_track, time, parent_g.affine_inverse() * cur.origin)
				g[j] = cur
				if driver[j] >= 0:
					var local := parent_g.basis.inverse() * cur.basis
					out.rotation_track_insert_key(rot_track[j], time, local.orthonormalized().get_rotation_quaternion())
		lib.add_animation(anim_name, out)
	return lib


## Maps source bone index -> [rotation track, position track] (-1 where absent).
static func _track_index(src: Skeleton3D, a: Animation) -> Array:
	var out: Array = []
	for i in src.get_bone_count():
		out.append([-1, -1])
	for t in a.get_track_count():
		var bone := src.find_bone(str(a.track_get_path(t).get_concatenated_subnames()))
		if bone < 0:
			continue
		match a.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				out[bone][0] = t
			Animation.TYPE_POSITION_3D:
				out[bone][1] = t
	return out


## Global transform of every source bone at `time` of `a` (rest pose where `a` is null or has no track).
static func _source_pose(src: Skeleton3D, a: Animation, time: float, tracks: Array = []) -> Array:
	if a != null and tracks.is_empty():
		tracks = _track_index(src, a)
	var g: Array = []
	g.resize(src.get_bone_count())
	for i in src.get_bone_count():
		var local := src.get_bone_rest(i)
		if a != null:
			var rt: int = tracks[i][0]
			var pt: int = tracks[i][1]
			if rt >= 0:
				local.basis = Basis(a.rotation_track_interpolate(rt, time))
			if pt >= 0:
				local.origin = a.position_track_interpolate(pt, time)
		var parent := src.get_bone_parent(i)
		g[i] = (g[parent] as Transform3D) * local if parent >= 0 else local
	return g
