extends SceneTree
func _initialize():
	var sm = root.get_node_or_null("SplitMod")
	print("CHECK SplitMod node: ", sm, " enabled=", sm.enabled if sm else "n/a")
	var paths = []
	var f = FileAccess.open(OS.get_environment("CHECK_LIST"), FileAccess.READ)
	while !f.eof_reached():
		var p = f.get_line().strip_edges()
		if p != "": paths.append(p)
	var bad = 0
	for p in paths:
		var s = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
		if s == null or (s is Script and !s.can_instantiate()):
			print("CHECK FAIL ", p); bad += 1
		else:
			print("CHECK OK ", p)
	print("CHECK DONE bad=", bad)
	quit()
