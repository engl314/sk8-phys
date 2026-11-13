extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var crop := Vector2i(int(args[1]), int(args[2]))
	var files: Array = []
	for f in args.slice(3):
		if FileAccess.file_exists(f):
			files.append(f)
	if files.is_empty():
		quit()
		return
	var columns := mini(files.size(), 3)
	var rows := ceili(files.size() / float(columns))
	var sheet := Image.create(crop.x * columns, crop.y * rows, false, Image.FORMAT_RGB8)
	for i in files.size():
		var image := Image.load_from_file(files[i])
		image.convert(Image.FORMAT_RGB8)
		var origin := (image.get_size() - crop) / 2
		sheet.blit_rect(image, Rect2i(origin, crop), Vector2i(i % columns * crop.x, i / columns * crop.y))
	sheet.save_png(out)
	quit()
