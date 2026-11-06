extends RefCounted
## Aim-down-sight optics. A weapon aims through its fitted optic attachment, or
## through the sight its model is built with: assault rifles, SMGs and LMGs carry
## a reflex sight, the MK14 a 3x scope and both sniper rifles a 6x scope.
## Shotguns, pistols and launchers without an optic use their iron sights.
##
##   kind     reflex  see-through window with a reticle projected at the aim point
##            scope   magnified; full aim looks through the eyepiece
##            iron    no glass, a mild zoom over the sights
##   zoom     magnification at full aim; the field of view divides by it
##   reticle  the pattern the HUD draws at the point of aim
const Data = preload("res://scripts/core/game_data.gd")
const NONE := {"kind": "none", "zoom": 1.0, "reticle": "", "name": ""}
const IRON := {"kind": "iron", "zoom": 1.15, "reticle": "post", "name": "Iron sights"}
const REFLEX := {"kind": "reflex", "zoom": 1.35, "reticle": "dot", "name": "Reflex sight"}
const ATTACHMENTS := {
	"reddot": {"kind": "reflex", "zoom": 1.5, "reticle": "dot", "name": "Red dot"},
	"holo": {"kind": "reflex", "zoom": 1.4, "reticle": "holo", "name": "Holographic"},
	"acog": {"kind": "scope", "zoom": 4.0, "reticle": "acog", "name": "ACOG 4x"},
}
const BUILT_IN := {
	"assault": REFLEX,
	"smg": REFLEX,
	"lmg": REFLEX,
	"marksman": {"kind": "scope", "zoom": 3.0, "reticle": "marksman", "name": "Marksman scope 3x"},
	"sniper": {"kind": "scope", "zoom": 6.0, "reticle": "sniper", "name": "Sniper scope 6x"},
}

static func profile(weapon_id: String, attachments: Array = []) -> Dictionary:
	if weapon_id == "knife":
		return NONE
	for attachment in attachments:
		var id: String = str(attachment.get("id", "")) if attachment is Dictionary else str(attachment)
		if ATTACHMENTS.has(id):
			return ATTACHMENTS[id]
	return BUILT_IN.get(str(Data.weapon(weapon_id).get("category", "")), IRON)

## Field of view through a sight magnifying `zoom` times. Magnification divides
## the tangent of the half-angle rather than the angle, which is what keeps the
## picture an exact enlargement.
static func zoomed_fov(base_fov: float, zoom: float) -> float:
	if zoom <= 1.0:
		return base_fov
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / zoom))
