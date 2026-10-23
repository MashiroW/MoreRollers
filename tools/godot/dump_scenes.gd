extends SceneTree
func _initialize():
	var out = OS.get_environment("DUMP_OUT")
	var f = FileAccess.open(OS.get_environment("DUMP_LIST"), FileAccess.READ)
	var n = 0
	while !f.eof_reached():
		var p = f.get_line().strip_edges()
		if p == "": continue
		var res = ResourceLoader.load(p)
		if res == null:
			print("DUMPFAIL load ", p); continue
		var dest = out + "/" + p.replace("res://", "")
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var err = ResourceSaver.save(res, dest)
		if err != OK: print("DUMPFAIL save ", p, " ", err)
		else: n += 1
	print("DUMPED ", n)
	quit()
