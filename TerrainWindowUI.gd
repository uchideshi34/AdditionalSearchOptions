class_name TerrainWindowUI

var global = null
var terrainwindow = null
var texturemenu = null
var reference_to_script = null
var target = null
var used_button = null
var search_hbox = null

var search_lineedit = null

var pattern_searchable_types = ["Simple Tiles","PatternShapeTool","Patterns Colorable"]

signal terrain_selected

# Logging functions
const ENABLE_LOGGING = true
const LOGGING_LEVEL = 2

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= LOGGING_LEVEL:
			printraw("(%d) <TerrainWindowUI>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Function to look at resource string and return the texture
func load_image_texture(texture_path: String):

	var image = Image.new()
	var texture = ImageTexture.new()

	# If it isn't an internal resource
	if not "res://" in texture_path:
		image.load(global.Root + texture_path)
		texture.create_from_image(image)
	# If it is an internal resource then just use the ResourceLoader
	else:
		texture = ResourceLoader.load(texture_path)
	
	return texture


# Loads an image texture from ResourceLoader if that is possible or direct from a file if not
func safe_load_texture(path: String) -> Texture:

	outputlog("safe_load_texture: " + str(path),2)

	var texture = null
	if ResourceLoader.exists(path):
		texture = ResourceLoader.load(path)
	else:
		var file = File.new()
		if file.file_exists(path):
			texture = load_runtime_image(path)
			if texture != null:
				texture.resource_path = path

	return texture

# Load an image from a file
func load_runtime_image(path: String) -> Texture:
	var img := Image.new()
	if img.load(path) != OK:
		return null

	var tex := ImageTexture.new()
	tex.create_from_image(img)
	return tex

# Function to return the thumbnail url from a resource path
func find_thumbnail_url(resource_path: String):

	var thumbnail_extension = ".png"
	var thumbnail_url

	thumbnail_url = "user://.thumbnails/" + resource_path.md5_text() + thumbnail_extension

	# Check if the thumbnail url is valid, if not create a thumbnail url for the embedded thumbnail
	if not ResourceLoader.exists(thumbnail_url):
		thumbnail_url = "res://packs/" + resource_path.split('/')[3] + "/thumbnails/" + resource_path.md5_text() + thumbnail_extension

	return thumbnail_url

# Function to return the texture of the thumbnail based on the core texture's resource path
func return_thumbnail_texture(resource_path: String):

	var texture
	var thumbnail_url = find_thumbnail_url(resource_path)
	if ResourceLoader.exists(thumbnail_url):
		texture = ResourceLoader.load(thumbnail_url)
	else:
		outputlog("Error in return_thumbnail_texture: no thumbnail found for this texture path - " + resource_path)
		return null

	return texture

func downscale_and_remove_alpha(tex: ImageTexture) -> ImageTexture:
	if tex == null:
		return null

	# Get CPU image
	var img: Image = tex.get_data()

	# Resize to 32x32
	img.resize(64, 64, Image.INTERPOLATE_LANCZOS)

	# Convert to RGB (drops alpha)
	img.convert(Image.FORMAT_RGB8)

	# Upload back to GPU
	var out := ImageTexture.new()
	out.create_from_image(img, Texture.FLAG_FILTER)

	return out

# Return the name of the texture and the pack it is in from the resource path string as a dictionary
func find_texture_name_and_pack(texture_string):

	var texture_name
	var pack_name
	var pack_id
	var array: Array

	# If this is a custom pack then find the pack name and split out the 
	if texture_string.left(12) == "res://packs/":
		array = texture_string.right(12).split("/")
		pack_id = array[0]
		texture_name = array[-1].split(".")[0]
		for pack in global.Header.AssetManifest:
			if pack.ID == pack_id:
				pack_name = pack.Name
	# If this is a native DD pack, then return the name
	elif texture_string.left(15) == "res://textures/":
		array = texture_string.right(6).split("/")
		texture_name = array[-1].split(".")[0]
		pack_id = "nativeDD"
		pack_name = "Default"
	# Otherwise return a "Not Set" string
	else:
		texture_name = "Not Set"
		pack_id = "n/a"
		pack_name = "Not Set"
	
	return {"texture_name": texture_name,"pack_name": pack_name, "pack_id": pack_id}

# Function to set a property on an object but block any signals for it
func set_property_but_block_signals(obj: Object, property: String, value):

	outputlog("set_property_but_block_signals: " + str(obj) + " property: " + str(property) + " value: " + str(value),3)

	obj.set_block_signals(true)
	if obj.get(property) != null:
		obj.set(property,value)
	obj.set_block_signals(false)

#########################################################################################################
##
## CORE FUNCTIONS
##
#########################################################################################################

func _init(glbl = null, ref_to_script = null):

	if glbl == null || ref_to_script == null: return

	global = glbl
	reference_to_script = ref_to_script

	var terrainwindow_template = ResourceLoader.load(global.Root + "ui/terrainwindow.tscn", "", true)
	terrainwindow = terrainwindow_template.instance()
	outputlog("terrainwindow: " + str(terrainwindow),1)
	global.Editor.get_child("Windows").add_child(terrainwindow)
	terrainwindow.connect("about_to_show", self, "_update_terrainwindow_pack_list")
	terrainwindow.find_node("PackList").connect("item_selected", self, "_on_pack_list_item_selected")
	terrainwindow.find_node("TextureMenu").connect("item_selected", self, "_on_terrain_item_selected")

	var vbox = VBoxContainer.new()
	texturemenu = terrainwindow.find_node("TextureMenu")
	terrainwindow.find_node("Splitter").remove_child(texturemenu)
	terrainwindow.find_node("Splitter").add_child(vbox)

	search_hbox = HBoxContainer.new()
	search_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var search_label = Label.new()
	search_label.text = "Search "
	search_lineedit = LineEdit.new()
	search_lineedit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	used_button = Button.new()
	used_button.icon = ResourceLoader.load("res://ui/icons/tools/pattern_shape_tool.png")
	used_button.hint_tooltip = "Load (where possible) the set of terrain textures matching the pattern textures already used on this map."
	used_button.connect("pressed",self,"_on_used_assets_button_pressed",["TerrainBrush","main","PatternShapeTool"])

	var search_clearbutton = Button.new()
	search_clearbutton.icon = load_image_texture("ui/trash_icon.png")
	search_clearbutton.connect("pressed", self, "_on_clearbutton_pressed", [search_lineedit])
	search_lineedit.connect("text_entered",self,"_on_new_search_text")
	search_lineedit.connect("text_changed",self,"_on_new_search_text")
	
	search_hbox.add_child(search_label)
	search_hbox.add_child(search_lineedit)
	search_hbox.add_child(used_button)
	search_hbox.add_child(search_clearbutton)
	
	vbox.add_child(search_hbox)
	vbox.add_child(texturemenu)


func show():
	terrainwindow.popup_centered_ratio(0.5)

func hide():
	terrainwindow.visible = false


#########################################################################################################
##
## TERRAIN WINDOW FUNCTIONS
##
#########################################################################################################

# sorter for reducing array in place
class MyCustomSorter:
	static func sort_ascending_pack_name(a, b):
		return a["pack_name"] < b["pack_name"]
	
func _update_terrainwindow_pack_list():

	outputlog("_update_terrainwindow_pack_list",2)

	var terrain_list = reference_to_script.GetAssetList("Terrain")

	if terrain_list == null: return

	var pack_list = []
	var pack_id_list = []
	
	for terrain_path in terrain_list:
		var entry = find_texture_name_and_pack(terrain_path)
		if not entry["pack_id"] in pack_id_list && entry["pack_id"] != "nativeDD":
			pack_id_list.append(entry["pack_id"])
			pack_list.append(entry.duplicate(true))
	
	pack_list.sort_custom(MyCustomSorter,"sort_ascending_pack_name")

	if global.Header.UsesDefaultAssets:
		pack_list.push_front({"pack_id": "nativeDD", "pack_name": "Default"})

	pack_list.push_front({"pack_id": "all", "pack_name": "All"})
	var packListPath = terrainwindow.find_node("PackList")

	packListPath.clear()
	for pack_entry in pack_list:
		packListPath.add_item(pack_entry["pack_name"])
		packListPath.set_item_metadata(packListPath.get_item_count()-1,pack_entry["pack_id"])
		packListPath.set_item_tooltip(packListPath.get_item_count()-1,pack_entry["pack_name"])
	
	if packListPath.get_item_count() > 0:
		packListPath.select(0)
		_on_pack_list_item_selected(0)

func _on_pack_list_item_selected(index: int):

	outputlog("_on_pack_list_item_selected: " + str(index),2)

	_on_new_search_text(search_lineedit.text)

func _on_terrain_item_selected(index: int):

	outputlog("_on_terrain_item_selected",2)

	if target != null:
		outputlog("target: " + str(target),2)
		var texture_path = texturemenu.get_item_metadata(index)
		outputlog("texture_path: " + str(texture_path),2)
		self.emit_signal("terrain_selected", target, texture_path)

	texturemenu.clear()
	terrainwindow.hide()

func _on_clearbutton_pressed(lineedit: LineEdit):

	outputlog("_on_clearbutton_pressed",2)

	lineedit.text = ""
	_on_new_search_text(lineedit.text)

func _on_new_search_text(search_text: String):

	outputlog("_on_new_search_text",2)

	if terrainwindow.find_node("PackList").selected < 0: return
	texturemenu.clear()
	
	var selected_packs = terrainwindow.find_node("PackList").get_selected_items()
	var selected = 0
	if selected_packs.size() > 0: selected = selected_packs[0]
	var pack_id = terrainwindow.find_node("PackList").get_item_metadata(selected)

	var terrain_list = reference_to_script.GetAssetList("Terrain")
	for terrain_path in terrain_list:
		var entry = find_texture_name_and_pack(terrain_path)
		if (entry["pack_id"] == pack_id || pack_id == "all") && _is_valid_search_result(entry["texture_name"], search_text):
			texturemenu.add_item(entry["texture_name"], downscale_and_remove_alpha(safe_load_texture(find_thumbnail_url(terrain_path))))
			texturemenu.set_item_metadata(texturemenu.get_item_count()-1, terrain_path)

# Algorithm to check if the search term matches the string
func _is_valid_search_result(search_in_this: String, for_this: String):

	var list_of_words
	var return_value = false

	if for_this == "": return true
	for_this = for_this.to_lower()
	search_in_this = search_in_this.to_lower()

	# Replace - and _ with space and then separate as needed
	for_this = for_this.replace("-"," ")
	for_this = for_this.replace("_"," ")

	# If there is a space then treat each space separated word as a required value
	if for_this.find(" ") > -1:
		# Split the string into words
		list_of_words = for_this.split(" ")
		# For each word in the list
		for word in list_of_words:
			# Default to true
			return_value = true
			# Check if the word is found and if not then set the whole thing as not found
			if not (search_in_this.find(word) > -1) && word != "":
				return_value = false
				break
	# Otherwise we are in the simply one word case
	else:
		# Check is we find the search term
		if search_in_this.find(for_this) > -1:
			return_value = true

	return return_value

# Function to find and return a list of resource paths for assets already used in the map. sort_types are: 0 - alphabetical including pack, 1 - alphabetical asset_name only, 2 - by node_id ascending, 3 - by node_id descending
func find_assets_used_in_map(tool_type: String, source_category: String, sort_type: int):

	var array_of_texture_paths = []
	var url_match_array = {
		"Simple Tiles": "tilesets/simple/",
		"PatternShapeTool": "patterns/normal/",
		"Patterns Colorable": "patterns/colorable/",
		"TerrainBrush": "terrain/",
		"LightTool": "lights/",
		"PortalTool": "portals/"
	}
	var temp_resource_path: String
	var resource_path_data: Dictionary
	var array_of_asset_data = []
	var thumbnail_url

	# For each level in the world
	for level in global.World.levels:
		# If patterns then look for patterns
		if tool_type == "PatternShapeTool":
			# If this is a normal search then look for pattern shapes
			if source_category == tool_type:
				for patternshape in level.PatternShapes.GetShapes():
					# If the resource path of the pattern matches the value for the category the add it
					for category in pattern_searchable_types:
						if url_match_array[category] in patternshape._Texture.resource_path:
							array_of_texture_paths.append(patternshape._Texture.resource_path)
			# If the source category is Terrain
			elif source_category == "TerrainBrush":
				# For each terrain on the level
				for terrain in level.Terrain.textures:
					array_of_texture_paths.append(terrain.resource_path)

		# If Terrain then look for used pattern shapes and record those to be sorted and made unique
		elif tool_type == "TerrainBrush":
			for patternshape in level.PatternShapes.GetShapes():
				# If the resource path of the pattern matches the value for the category the add it
				array_of_texture_paths.append(patternshape._Texture.resource_path)

	array_of_texture_paths = filter_unique_array_of_texture_paths(array_of_texture_paths)

	# If we are looking at different source categories then we need to take the array of source textures and turn them into current tool textures where possible
	if tool_type != source_category:
		# Make a copy of the pattern texture paths
		var copy_of_array = array_of_texture_paths.duplicate()
		# Clear the destination array which will be rebuilt with terrain texture paths
		array_of_texture_paths.clear()
		# For each (now unique) pattern resource path, look for a matching and validate terrain resource path
		for texture_resource_path in copy_of_array:
			# Extract the dictionary of resource data {"texture_name": texture_name,"pack_name": pack_name, "pack_id": pack_id}
			resource_path_data = find_texture_name_and_pack(texture_resource_path)
			# Construct a potential resource path for the matching terrain asset
			temp_resource_path = "res://packs/" + resource_path_data["pack_id"] + "/textures/" + url_match_array[tool_type] + resource_path_data["texture_name"] + "." + texture_resource_path.split(".")[1]
			# If there exists a thumbnail file for this path then add the url of the resource path to the array of textures. Not sure why I can't directly use ResourceLoader on the file itself!
			thumbnail_url = find_thumbnail_url(temp_resource_path)
			if thumbnail_url != null:
				array_of_texture_paths.append(load(thumbnail_url))

	return array_of_texture_paths

# Function to take an array of things, sort it and remove any duplicates
func filter_unique_array_of_texture_paths(array: Array):

	# Sort the data so that it is in order of texture path
	array.sort()
	
	if array.size() < 2:
		return array
	var index = 1
	while index < array.size():
		if array[index] == array[index-1]:
			array.remove(index)
		else:
			index = index + 1
	return array

# Function to update the grid menu to list all the assets previously used on this map (all levels)
func _on_used_assets_button_pressed(tool_type: String, location: String, source_category: String):

	outputlog("on_used_assets_button_pressed: " + str(tool_type) + "location: " + str(location) + " source_category: " + str(source_category))

	if terrainwindow.find_node("PackList").selected < 0: return
	if terrainwindow.find_node("PackList").get_item_count() > 0:
		terrainwindow.find_node("PackList").select(0)

	search_lineedit.clear()
	# Get a list of all possible assets in the right category
	var array_textures = find_assets_used_in_map(tool_type, source_category, 0)
	
	texturemenu.clear()

	for terrain_path in array_textures:
		var entry = find_texture_name_and_pack(terrain_path)
		texturemenu.add_item(entry["texture_name"], downscale_and_remove_alpha(safe_load_texture(find_thumbnail_url(terrain_path))))
		texturemenu.set_item_metadata(texturemenu.get_item_count()-1, terrain_path)

var max_history_search_terms = 10

# Function to make a search history capability for Object Library Panel
func make_search_history_ui():

	outputlog("make_search_history_ui")

	# Make a new menu button and add it to the search hbox
	var menubutton = MenuButton.new()
	search_hbox.add_child(menubutton)
	search_hbox.move_child(menubutton,1)

	menubutton.icon = load_image_texture("ui/history-icon.png")
	menubutton.hint_tooltip = "Select from a list of previous searches."

	# Connect to the signal when a text has been entered
	search_lineedit.connect("text_entered", self, "on_store_new_search_history_item",[menubutton])

	# Connect to the id pressed signal to respond when the search history item has been selected.
	menubutton.get_popup().connect("id_pressed", self, "on_search_history_item_selected", [menubutton, search_lineedit])

# Function to remove all matching text from popupmenu of text items
func remove_matching_text_item_from_popupmenu(text: String, popupmenu: PopupMenu) -> bool:

	var removed_item = false

	var _i = 0
	while _i < popupmenu.get_item_count():
		if text == popupmenu.get_item_text(_i):
			popupmenu.remove_item(_i)
			removed_item = true
		else:
			_i += 1

	return removed_item

# Function to respond when a new search text is entered in the object panel to record it in the search history
func on_store_new_search_history_item(search_text: String, menubutton: MenuButton):

	var history_popup = menubutton.get_popup()

	outputlog("on_store_new_search_history_item")

	# Do nothing if the search is blank
	if search_text == "":
		return

	# Check if this is duplicate of the current top entry and do nothing if so
	if history_popup.get_item_count() > 0:
		remove_matching_text_item_from_popupmenu(search_text, history_popup)
	
	# Add the new search term and put it at the top of the list
	history_popup.add_item(search_text)
	move_item_to_top_of_popupmenu(history_popup.get_item_count()-1,history_popup)

	# Limit the number of history records to MAX_HISTORY_SEARCH_TERMS
	if history_popup.get_item_count() > max_history_search_terms:
		history_popup.remove_item(history_popup.get_item_count()-1)


# Function to respond when a search history is selected
func on_search_history_item_selected(id: int, search_button: MenuButton, search_lineedit: LineEdit):

	var search_text = ""

	# If the search controls are valid
	if search_lineedit != null && search_button != null:
		# Set the search text
		search_text = search_button.get_popup().get_item_text(id)
		search_lineedit.text = search_text
		# Emit the signal for text_entered
		search_lineedit.emit_signal("text_entered",search_text)

# Function to put a text item at the top of a popupmenu of text items
func move_item_to_top_of_popupmenu(id: int, popupmenu: PopupMenu):

	if not id < popupmenu.get_item_count():
		return
	
	var store_list = []
	# Put the required item at the top
	store_list.append(popupmenu.get_item_text(id))

	# Get the remaining items and log them into the array
	for _i in popupmenu.get_item_count():
		if _i != id:
			store_list.append(popupmenu.get_item_text(_i))

	# Clear the popup menu
	popupmenu.clear()
	# Write the stored values back into the array in order.
	for _i in store_list.size():
		popupmenu.add_item(store_list[_i])
	


