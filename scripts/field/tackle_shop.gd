class_name TackleShop
extends BirdLab
## The bait and tackle shop on Mends Street, South Perth, up from the jetty:
## the fishing side's dock. Pull into the bay (or walk up to the sign) and
## press F / A to weigh in the esky, buy ice, and look at rods, eskies and
## the crab net.


func _group() -> StringName:
	return &"tackle_shops"


func _color() -> Color:
	return Color(0.4, 0.75, 0.95)


func _sign_text() -> String:
	return "BAIT & TACKLE\nweigh-ins  ice\nrods  eskies"


func _prompt_text() -> String:
	return "F / A  Bait and tackle (esky %d of %d)" % [FieldJournal.esky.size(), FieldJournal.esky_size()]
