# Dungeondraft mod to add ability to search for walls, terrain and patterns in the tool panel
var script_class = "tool"

# Variables
var ui_config: Dictionary
var pattern_types = ["All","Simple Tiles","PatternShapeTool","Patterns Colorable"]
var pattern_searchable_types = ["Simple Tiles","PatternShapeTool","Patterns Colorable"]
var _lib_mod_config
var terrainwindowui = null

const CATEGORY_LOOKUP = {"PatternShapeTool": "Patterns", "WallTool": "Walls", "PortalTool": "Portals", "LightTool": "Lights","RoofTool": "Roofs", "TerrainBrush": "Terrain"}

var max_history_search_terms = 10

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 2

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <AdditionalSearchOptions>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

# Customer sort options for objects
class MyCustomSorter:
	static func sort_ascending_texture_path(a: Dictionary, b: Dictionary):
		return a["texture_path"] < b["texture_path"]

	static func sort_ascending_asset_name(a: Dictionary, b: Dictionary):
		return a["asset_name"] < b["asset_name"]
	
	static func sort_ascending_node_id(a: Dictionary, b: Dictionary):
		return a["node_id"] < b["node_id"]
	
	static func sort_descending_node_id(a: Dictionary, b: Dictionary):
		return a["node_id"] > b["node_id"]

# Function to see if a structure that looks like a copied dd data entry is the same
func is_the_same(a, b) -> bool:

	if a is Dictionary:
		if not b is Dictionary:
			return false
		if a.keys().size() != b.keys().size():
			return false
		for key in a.keys():
			if not b.has(key):
				return false
			if not is_the_same(a[key], b[key]):
				return false
	elif a is Array:
		if not b is Array:
			return false
		if a.size() != b.size():
			return false
		for _i in a.size():
			if not is_the_same(a[_i], b[_i]):
				return false
	elif a != b:
		return false

	return true

# Function to look at a node and determine what type it is based on its properties
func get_node_type(node):

	if node.get("WallID") != null:
		return "PortalTool"

	# Note this is also true of portals but we caught those with WallID
	elif node.get("Sprite") != null:
		return "ObjectTool"
	elif node.get("FadeIn") != null:
		return "PathTool"
	elif node.get("HasOutline") != null:
		return "pattern_shapes"
	elif node.get("Joint") != null:
		return "WallTool"

	return null

# Function to look at resource string and return the texture
func load_image_texture(texture_path: String):

	var image = Image.new()
	var texture = ImageTexture.new()

	# If it isn't an internal resource
	if not "res://" in texture_path:
		image.load(Global.Root + texture_path)
		texture.create_from_image(image)
	# If it is an internal resource then just use the ResourceLoader
	else:
		texture = ResourceLoader.load(texture_path)
	
	return texture


# Function to return the custom asset thumbnail url from a resource path
func find_thumbnail_url(resource_path: String):

	var thumbnail_extension = ".png"
	var thumbnail_url

	thumbnail_url = "user://.thumbnails/" + resource_path.md5_text() + thumbnail_extension

	# Check if the thumbnail url is valid, if not create a thumbnail url for the embedded thumbnail
	if not ResourceLoader.exists(thumbnail_url):
		thumbnail_url = "res://packs/" + resource_path.split('/')[3] + "/thumbnails/" + resource_path.md5_text() + thumbnail_extension
	# If the thumbnail can't be found then return null
	if not ResourceLoader.exists(thumbnail_url):
		thumbnail_url = null
		outputlog("thumbnail not found: " + str(thumbnail_url),2)

	return thumbnail_url

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
		for pack in Global.Header.AssetManifest:
			if pack.ID == pack_id:
				pack_name = pack.Name
	# If this is a native DD pack, then return the name
	elif texture_string.left(15) == "res://textures/":
		array = texture_string.right(6).split("/")
		texture_name = array[-1].split(".")[0]
		pack_id = "nativeDD"
		pack_name = "Native DD"
	# Otherwise return a "Not Set" string
	else:
		texture_name = "Not Set"
		pack_id = "n/a"
		pack_name = "Not Set"
	
	return {"texture_name": texture_name,"pack_name": pack_name, "pack_id": pack_id}


# Function to find the grid menu category so we can put UI around it and modify it.
func find_select_grid_menu(tool_type: String):

	var select_tool_panel = Global.Editor.Toolset.GetToolPanel("SelectTool")

	match tool_type:
		"PatternShapeTool":
			return select_tool_panel.patternTextureMenu
		"WallTool":
			return select_tool_panel.wallTextureMenu
		"LightTool":
			return select_tool_panel.lightTextureMenu
		"PortalTool":
			return select_tool_panel.portalTextureMenu
		_:
			outputlog("Error in find_select_grid_menu: vbox section not found. " + tool_type)
			return null

# Set the Global SearchHasFocus value
func on_search_entry_changed_focus(search_has_focus):

	outputlog("on_search_entry_changed_focus: " + str(search_has_focus),2)
	Global.Editor.SearchHasFocus = search_has_focus


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


#########################################################################################################
##
## RESET FUNCTIONS
##
#########################################################################################################

# Main function to clear the grid and reset
func on_clear_button_pressed(tool_type: String, location: String):

	outputlog("on_clear_button_pressed")

	# Clear everything if needed
	if ui_config[tool_type][location]["search_entry"].text.length() > 0:
		ui_config[tool_type][location]["search_entry"].clear()
	ui_config[tool_type][location]["search_entry_last_value"] = ""

	# Reload the pattern types in turn
	if tool_type == "ObjectTool":
		if Global.Editor.ObjectLibraryPanel.tagsButton.pressed:
			# Rest the list
			if Global.Editor.ActiveToolName in ["ObjectTool", "ScatterTool"]:
				Global.Editor.TagsPanels[Global.Editor.ActiveToolName].ShowCurrentTagSet()
		if Global.Editor.ObjectLibraryPanel.usedButton.pressed:
			on_used_objects_reset()
	else:
		# If Patterns with "All" selected, reload all categories instead of just Reset
		if tool_type == "PatternShapeTool":
			# Standard reset function
			for _i in range(pattern_searchable_types.size()):
				ui_config[tool_type][location]["grid_menu"].Load(pattern_searchable_types[_i])
				if _i == 0:
					ui_config[tool_type][location]["grid_menu"].Reset()
		else:
			ui_config[tool_type][location]["grid_menu"].Reset()
		# If this is a portal search and we are in the main tool, the PostInit() function will add back the null portal
		if tool_type == "PortalTool" && location == "main":
			Global.Editor.Tools["PortalTool"].PostInit()

	# Check whether there are any items in the list and if we are not in the pattern tool, then cycle through all the items to update the default colours
	refresh_colours_in_grid_menu(tool_type,location)
	
# A litte function to run through and select each grid item menu in turn, note this isn't effective if no initial selection has been made
func select_each_item_in_grid_menu(tool_type: String, location: String):

	outputlog("select_each_item_in_grid_menu: tool_type: " + str(tool_type) + " location: " + str(location),2)

	var grid_menu = ui_config[tool_type][location]["grid_menu"]

	grid_menu.select(0)

	for _i in grid_menu.get_item_count():
		grid_menu.SelectNext()

# When the list of used objects needs to be completely reset
func on_used_objects_reset():

	outputlog("on_used_objects_reset", 2)

	var tool_type = "ObjectTool"
	var location = "main"

	var array_textures = []
	var thumbnail_textures = []
	var thumbnail_url

	array_textures = find_assets_used_in_map(tool_type, tool_type, ui_config[tool_type][location]["sort_type"])

	# Find all the thumbnails
	for texture_path in array_textures:
		thumbnail_url = find_thumbnail_url(texture_path)
		if thumbnail_url != null:
			thumbnail_textures.append(load(thumbnail_url))

	# Set the pattern grid menu to only show the list of thumbnail textures
	ui_config["ObjectTool"]["main"]["grid_menu"].ShowSet(thumbnail_textures)

	
#########################################################################################################
##
## CORE SEARCH FUNCTIONS
##
#########################################################################################################

# Algorithm to check if the search term matches the string
func is_valid_search_result(search_in_this: String, for_this: String):

	var list_of_words
	var return_value = false

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

# Function to process the output of new pattern search text
func on_new_search_text(search_text: String, tool_type: String, location: String, source_type: String):

	var array_textures = []
	var result
	var thumbnail_textures = []
	var grid_menu = ui_config[tool_type][location]["grid_menu"]
	var thumbnail_url

	outputlog("on_new_search_text: " + str(search_text) + " tool_type: " + str(tool_type) + " location: " + str(location),2)

	# If we have installed _Lib check for the search_on_text_changed status
	if Engine.has_signal("_lib_register_mod"):
		# If search_on_text_changed not active and the source is a text_changed signal then do nothing
		if not _lib_mod_config.search_on_text_changed && source_type == "text_changed":
			return

	# If the search is blank then reset everything using the clear button feature
	if search_text.length() < 1:
		outputlog("search_text length is : " + str(search_text.length()),2)
		on_clear_button_pressed(tool_type,location)
		return

	# Set the search text to lower just to improve matching
	search_text = search_text.to_lower()
	
	if tool_type == "PatternShapeTool":
		# Set the category according to the drop down selection
		
		# Load all categories and capture Lookup after each Load to build a complete index-to-path mapping
		# (Lookup only contains the last-loaded category's entries, so we must capture after each Load)
		var all_index_to_path = {}
		for _i in range(pattern_searchable_types.size()):
			grid_menu.Load(pattern_searchable_types[_i])
			if _i == 0:
				grid_menu.Reset()
			for resource_path in grid_menu.Lookup.keys():
				all_index_to_path[grid_menu.Lookup[resource_path]] = resource_path
		# Remove non-matching items directly from the ItemList (iterate in reverse to preserve indices)
		for idx in range(grid_menu.get_item_count() - 1, -1, -1):
			if all_index_to_path.has(idx):
				result = all_index_to_path[idx].split("/")[-1].split(".")[0].to_lower()
				if not is_valid_search_result(result, search_text):
					grid_menu.remove_item(idx)
			else:
				grid_menu.remove_item(idx)
		outputlog("search results size (All): " + str(grid_menu.get_item_count()),2)
		refresh_colours_in_grid_menu(tool_type,location)
		return
	
	# Get a list of all possible assets in the right category
	match tool_type:
		"ObjectTool":
			if Global.Editor.ObjectLibraryPanel.tagsButton.pressed:
				# Rest the list
				if Global.Editor.ActiveToolName in ["ObjectTool", "ScatterTool"]:
					Global.Editor.TagsPanels[Global.Editor.ActiveToolName].ShowCurrentTagSet()

				# Get the current keys
				array_textures = Global.Editor.ObjectLibraryPanel.objectMenu.Lookup.keys()
				array_textures.sort()
				array_textures.invert()

			if Global.Editor.ObjectLibraryPanel.usedButton.pressed:
				array_textures = find_assets_used_in_map(tool_type, tool_type, ui_config[tool_type][location]["sort_type"])
		_:
			array_textures = Script.GetAssetList(CATEGORY_LOOKUP[tool_type])


	# Look through each asset and determine if it matches the search string
	for texture_path in array_textures:
		# If it is Roof then the name of the roof is the part before the final piece e.g. /roof_name/tiles.png
		if tool_type == "RoofTool":
			result = texture_path.split("/")[-2].to_lower()
		# find the name of the asset by looking at the right hand side of the url and stripping off the extension then changing to lower
		else:
			result = texture_path.split("/")[-1].split(".")[0].to_lower()
		# If the search string is contained in the asset name then do something with it

		if is_valid_search_result(result, search_text):
			# Take the url of the texture, derive the url of the thumbnail, load the texture of that thumbnail and add it to a list
			thumbnail_url = find_thumbnail_url(texture_path)
			if thumbnail_url != null:
				thumbnail_textures.append(load(thumbnail_url))
	
	outputlog("search results size: " + str(thumbnail_textures.size()),2)
	grid_menu.ShowSet(thumbnail_textures)

	# If this is a portal search and we are in the main tool, the PostInit() function will add back the null portal
	if tool_type == "PortalTool" && location == "main":
		Global.Editor.Tools["PortalTool"].PostInit()

	# Check whether there are any items in the list and if we are not in the pattern tool, then cycle through all the items to update the default colours
	refresh_colours_in_grid_menu(tool_type,location)

	outputlog("finished show set",2)

# Function to update the grid menu to list all the assets previously used on this map (all levels)
func on_used_assets_button_pressed(tool_type: String, location: String, source_category: String):

	var array_textures = []
	var result
	var thumbnail_textures = []
	var grid_menu = ui_config[tool_type][location]["grid_menu"]
	var category: String
	var thumbnail_url

	outputlog("on_used_assets_button_pressed: " + str(tool_type) + "location: " + str(location) + " source_category: " + str(source_category))

	# If the search is blank then reset everything using the clear button feature, but don't do this for paths as we don't own the search text field
	if tool_type != "PathTool":
		ui_config[tool_type][location]["search_entry"].clear()
		ui_config[tool_type][location]["search_entry_last_value"] = ""
	
	# If the category is patterns
	if tool_type == "PatternShapeTool":
		# Set the category according to the drop down selection
		# Load all categories and capture Lookup after each Load
		var all_index_to_path = {}
		for _i in range(pattern_searchable_types.size()):
			grid_menu.Load(pattern_searchable_types[_i])
			if _i == 0:
				grid_menu.Reset()
			for resource_path in grid_menu.Lookup.keys():
				all_index_to_path[grid_menu.Lookup[resource_path]] = resource_path
		# Gather used assets from all searchable pattern categories
		var used_paths = {}
		for searchable_category in pattern_searchable_types:
			for asset_path in find_assets_used_in_map(tool_type, source_category, 0):
				used_paths[asset_path] = true
		# Remove items that are NOT used (iterate in reverse to preserve indices)
		for idx in range(grid_menu.get_item_count() - 1, -1, -1):
			if all_index_to_path.has(idx):
				if not used_paths.has(all_index_to_path[idx]):
					grid_menu.remove_item(idx)
			else:
				grid_menu.remove_item(idx)
		refresh_colours_in_grid_menu(tool_type,location)
		return

	# Get a list of all possible assets in the right category
	array_textures = find_assets_used_in_map(tool_type, source_category, 0)

	# Look through each asset and get its thumbnail
	for texture_path in array_textures:
		# Take the url of the texture, derive the url of the thumbnail, load the texture of that thumbnail and add it to a list
		thumbnail_url = find_thumbnail_url(texture_path)
		if thumbnail_url != null:
			thumbnail_textures.append(load(thumbnail_url))

	# Set the pattern grid menu to only show the list of thumbnail textures
	grid_menu.ShowSet(thumbnail_textures)

	# If this is a portal search and we are in the main tool, the PostInit() function will add back the null portal
	if tool_type == "PortalTool" && location == "main":
		Global.Editor.Tools["PortalTool"].PostInit()

	# Check whether there are any items in the list and if we are not in the pattern tool, then cycle through all the items to update the default colours
	refresh_colours_in_grid_menu(tool_type,location)

# Function that refreshes the visible colours in the grid menu
func refresh_colours_in_grid_menu(tool_type: String, location: String):

	var grid_menu = ui_config[tool_type][location]["grid_menu"]

	# If _Lib installed and the refresh grid colours not active then don't refresh the grid colours
	if Engine.has_signal("_lib_register_mod"):
		if not _lib_mod_config.refresh_grid_colours:
			return

	# Check whether there are any items in the list and if we are not in the pattern tool, then cycle through all the items to update the default colours
	if grid_menu.get_item_count() > 0 && location != "select":
		# Select the first item in the list if there is anything in the list
		grid_menu.select(0)
		# This tells the GridMenu to actually use this value
		grid_menu.OnItemSelected(0)
		# Make a loop for all the items being displayed
		# In order to display custom colours on walls and tile sets
		if tool_type == "WallTool" && Global.Header.UsesDefaultAssets:
			select_each_item_in_grid_menu(tool_type,location)
		# If this is about patterns and specifically for Simple Tiles or All (which includes Simple Tiles).
		if tool_type == "PatternShapeTool":
			var selected_pattern_type = pattern_types[ui_config[tool_type][location]["dropdown"].selected]
			if selected_pattern_type == "Simple Tiles" || selected_pattern_type == "All":
				select_each_item_in_grid_menu(tool_type,location)


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

# Function to take an array of things, sort it and remove any duplicates
func filter_unique_array_of_asset_data(array_of_asset_data: Array, sort_type: int):

	if array_of_asset_data.size() < 2:
		return array_of_asset_data
	
	# Sort the data so that it is in order of texture path
	array_of_asset_data.sort_custom(MyCustomSorter, "sort_ascending_texture_path")
	
	var index = 1
	while index < array_of_asset_data.size():
		# If the texture paths are the same then remove one of them, but keep the highest/lowest node id. Noting we can leave the asset name alone.
		if array_of_asset_data[index]["texture_path"] == array_of_asset_data[index-1]["texture_path"]:
			if array_of_asset_data[index]["node_id"] > array_of_asset_data[index-1]["node_id"]:
				# If sorting descending keep the highest
				if sort_type == 2:
					array_of_asset_data.remove(index-1)
				else:
					array_of_asset_data.remove(index)
			else:
				if sort_type == 2:
					array_of_asset_data.remove(index)
				else:
					array_of_asset_data.remove(index-1)
		else:
			index = index + 1
	return array_of_asset_data

#########################################################################################################
##
## USED ASSET SEARCH FUNCTIONS
##
#########################################################################################################

# Function to find and return a list of resource paths for assets already used in the map. sort_types are: 0 - alphabetical including pack, 1 - alphabetical asset_name only, 2 - by node_id ascending, 3 - by node_id descending
func find_assets_used_in_map(tool_type: String, source_category: String, sort_type: int):

	outputlog("find_assets_used_in_map",2)

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
	for level in Global.World.levels:
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
				
		# If walls then look for walls
		elif tool_type == "WallTool":
			for wall in level.Walls.get_children():
				array_of_texture_paths.append(wall.Texture.resource_path)
		
		# If paths then look for paths
		elif tool_type == "PathTool":
			for pathway in level.Pathways.get_children():
				array_of_texture_paths.append(pathway.get_texture().resource_path)

		# If Terrain then look for used pattern shapes and record those to be sorted and made unique
		elif tool_type == "TerrainBrush":
			for patternshape in level.PatternShapes.GetShapes():
				# If the resource path of the pattern matches the value for the category the add it
				array_of_texture_paths.append(patternshape._Texture.resource_path)
		
		# If Lights then look for used lights
		elif tool_type == "LightTool":
			for light in level.Lights.get_children():
				# If the resource path of the pattern matches the value for the category the add it
				array_of_texture_paths.append(light.get_texture().resource_path)
		
		# If Roofs then look for used roofs
		elif tool_type == "RoofTool":
			for roof in level.Roofs.get_children():
				# If the resource path of the pattern matches the value for the category the add it
				array_of_texture_paths.append(roof.TilesTexture.resource_path)
		
		# If Lights then look for used portals
		elif tool_type == "PortalTool":
			for portal in level.Portals.get_children():
				# If the resource path of the portal matches the value for the category the add it
				array_of_texture_paths.append(portal.Texture.resource_path)
			# Look through all the walls and get and portals in them
			for wall in level.Walls.get_children():
				for portal in wall.Portals:
					array_of_texture_paths.append(portal.Texture.resource_path)

		# If searching for Objects in the Used tab
		elif tool_type == "ObjectTool":
			for prop in level.Objects.get_children():
				# Avoid Weird props no node_id and with default asset textures
				if "node_id" in prop.get_meta_list():
					array_of_asset_data.append({"texture_path": prop.Texture.resource_path, "asset_name": find_texture_name_and_pack(prop.Texture.resource_path)["texture_name"], "node_id": ("0x" + str(prop.get_meta("node_id"))).hex_to_int()})

	# If we need to build a new array of textures from a array of dictionary entries
	if tool_type == "ObjectTool":

		# Make the list unique to texture_path keeping the highest/lowest node id
		array_of_asset_data = filter_unique_array_of_asset_data(array_of_asset_data,sort_type)
		# Sort the array according to sort type
		if sort_type == 1:
			array_of_asset_data.sort_custom(MyCustomSorter, "sort_ascending_asset_name")
		if sort_type == 2:
			# Note that we want the most recently used on the top of the grid so we sort descending
			array_of_asset_data.sort_custom(MyCustomSorter, "sort_descending_node_id")
		if sort_type == 3:
			# Note that we want the least recently used on the top of the grid so we sort ascending
			array_of_asset_data.sort_custom(MyCustomSorter, "sort_ascending_node_id")

		array_of_texture_paths.clear()
		for asset in array_of_asset_data:
			array_of_texture_paths.append(asset["texture_path"])

	# If these are not objects then just filter the list, nothing complicated required
	else:
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

#########################################################################################################
##
## TERRAIN SPECIFIC FUNCTIONS
##
#########################################################################################################

# If we press the set terrain button, then set the terrain slot texture based on the grid value selected and the slot in the drop down
func on_set_terrain_slot_button_pressed():

	var category_type = "TerrainBrush"
	var tool_name = "main"
	var texture = ui_config[category_type][tool_name]["grid_menu"].Selected
	var terrain_list = Global.Editor.Tools["TerrainBrush"].terrainList

	var index = Global.Editor.Tools["TerrainBrush"].TerrainID
	
	# If we have a valid texture selected then set it
	if texture:

		# Get the details of the terrain's thumbnail so we can update the UI
		var thumbnail_path = find_thumbnail_url(texture.resource_path)
		if thumbnail_path != null:
		
			var thumbnail_name = texture.resource_path.split("/")[-1].split(".")[0]
			var thumbnail_texture = ResourceLoader.load(thumbnail_path)

			# Update the visuals of the terrain brush tool to reflect the change we have made
			terrain_list.set_item_text(index,thumbnail_name)
			terrain_list.set_item_icon(index,thumbnail_texture)
			terrain_list.set_item_tooltip(index,thumbnail_name)

			# Set the texture on the map itself
			Global.World.GetCurrentLevel().Terrain.SetTexture(texture, index)

#########################################################################################################
##
## UI DRIVEN FUNCTIONS
##
#########################################################################################################

# Hide the search bar unless the "Used" tab is open
func on_object_filter_button_toggled(button_pressed: bool, button: Button):

	outputlog("on_object_filter_button_toggled",2)
	var tool_type = "ObjectTool"
	var location = "main"

	if button_pressed:
		match button:
			Global.Editor.ObjectLibraryPanel.usedButton:
				for button in ui_config[tool_type][location]["sort_type_buttons"]:
					button.visible = true

				ui_config[tool_type][location]["hbox"].visible = true
				refresh_object_search_after_delay()
				
			Global.Editor.ObjectLibraryPanel.tagsButton:
				for button in ui_config[tool_type][location]["sort_type_buttons"]:
					button.visible = false
				ui_config[tool_type][location]["hbox"].visible = true
				refresh_object_search_after_delay()
			_:
				ui_config[tool_type][location]["hbox"].visible = false
	
# After a delay re-run the object search based on current value of search entry
func refresh_object_search_after_delay(delay: float = 0.1):

	outputlog("refresh_object_search_after_delay",2)

	var tool_type = "ObjectTool"
	var location = "main"
	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	Global.Editor.get_node("Windows").add_child(timer)

	timer.start(delay)
	yield(timer,"timeout")
	on_new_search_text(ui_config[tool_type][location]["search_entry"].text, tool_type, location, "text_entered")

	Global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

func on_tagspanel_multi_selected(_ignore_this, _ignore_this_too):

	outputlog("on_tagspanel_multi_selected",2)

	refresh_object_search_after_delay()

# If the visibility is true
func on_toolpanel_visibility_changed(tool_type: String):

	outputlog("on_toolpanel_visibility_changed: " + str(tool_type))
	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	Global.Editor.get_node("Windows").add_child(timer)

	# Do something if this is a launch event
	if Global.Editor.Toolset.ToolPanels[tool_type].visible:
		# Double check that this is a Object or Scatter launch
		if tool_type in ["ObjectTool","ScatterTool"]:
			# Check if the usedbutton is active
			if Global.Editor.ObjectLibraryPanel.allButton.pressed:
				# Wait a bit as this seems necessary as DD is doing something else
				timer.start(0.05)
				yield(timer,"timeout")
				# Emit the signal so that it tells DD that the object panel should be filtered by the search entry
				if ui_config["ObjectTool"]["main"].has("dd_search_entry"):
					ui_config["ObjectTool"]["main"]["dd_search_entry"].emit_signal("text_entered",ui_config["ObjectTool"]["main"]["dd_search_entry"].text)
	
	Global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

# Function to toggle sorting state
func on_used_object_sorting_button_toggled(new_state: bool, sort_type: int):

	var tool_type = "ObjectTool"
	var location = "main"

	if not new_state:
		return
	
	# Set the other buttons to not pressed
	for _i in 4:
		if _i != sort_type:
			ui_config[tool_type][location]["sort_type_buttons"][_i].pressed = false
	
	# Record the current sort type
	ui_config[tool_type][location]["sort_type"] = sort_type
	on_clear_button_pressed(tool_type,location)

#########################################################################################################
##
## UI CREATION FUNCTIONS
##
#########################################################################################################

# Function to hide a mod tool button with a defined category and name
func hide_mod_tool(category: String, name: String):

	for button in Global.Editor.Toolset.Toolbars[category].find_node("Divider").find_node("Buttons").get_children():
		if button.text == name:
			button.visible = false

# Making a general function for creating the elements of UI for search
func make_search_ui(tool_type: String, location: String):

	var label = Label.new()
	var type_label = Label.new()
	var clear_button = Button.new()
	var used_button = Button.new()
	var tool_panel = Global.Editor.Toolset.GetToolPanel(tool_type)

	var ui_index
	var vbox
	
	outputlog("make_search_ui: " + str(tool_type) + " location: " + str(location))

	# Load the clear icon from file path
	var icon_texture = load_image_texture("ui/trash_icon.png")

	# Create dictionary entries for the UI
	if not ui_config.has(tool_type):
		ui_config[tool_type] = {}
	
	if not ui_config[tool_type].has(location):
		ui_config[tool_type][location] = {}
	
	# Find grid menu reference
	# If we are looking to construct the main panel search
	if location == "main":
		if tool_type != "TerrainBrush":
			# vbox is the main tool panel align vbox
			vbox = tool_panel.Align
			# Look for the grid menu in the tool panel
			ui_config[tool_type][location]["grid_menu"] = Global.Editor.Tools[tool_type].Controls["Texture"]
		else:
			# Begin a section that will get hidden if the option button is not selected
			ui_config[tool_type][location]["section"] = tool_panel.BeginSection(true)
			# Make a button to set the terrain slot
			ui_config[tool_type][location]["set_button"] = tool_panel.CreateButton("Set Terrain Slot", "res://ui/icons/tools/terrain_brush.png")
			ui_config[tool_type][location]["set_button"].connect("pressed",self,"on_set_terrain_slot_button_pressed")
			# Make a grid menu
			ui_config[tool_type][location]["grid_menu"] = tool_panel.CreateTextureGridMenu("TerrainTextureGridID","Terrain",true)
			ui_config[tool_type][location]["grid_menu"].ShowsPreview = false
			tool_panel.EndSection()

			ui_config[tool_type][location]["section"].visible = true
			vbox = ui_config[tool_type][location]["section"]

	# Or if we are looking at the Select tool
	elif location == "select":
		# find the select grid menu, noting that tool_type in the labels is the singular version of the tool_type
		ui_config[tool_type][location]["grid_menu"] = find_select_grid_menu(tool_type)
		# Apparent get_parent is bad practice in general but we are probably safe in this context. Find the parent node in the select ui which should be the section made visible when that category of asset is found.
		vbox = ui_config[tool_type][location]["grid_menu"].get_parent()
	# Set the index to start adding things
	ui_index = ui_config[tool_type][location]["grid_menu"].get_index()

	# Make a line for the search entry
	ui_config[tool_type][location]["hbox"] = HBoxContainer.new()
	
	# Create search entry reference
	ui_config[tool_type][location]["search_entry"] = LineEdit.new()

	if tool_type == "TerrainBrush":
		used_button.icon = ResourceLoader.load("res://ui/icons/tools/pattern_shape_tool.png")
		used_button.hint_tooltip = "Load (where possible) the set of pattern textures matching the terrain textures already used on this map."
		used_button.connect("pressed",self,"on_used_assets_button_pressed",[tool_type,location,"PatternShapeTool"])
	else:
		# Make the hbox search entry with a label, the lineedit and a clear button
		used_button.icon = ResourceLoader.load("res://ui/icons/tools/map_settings.png")
		used_button.hint_tooltip = "Load the set of " + str(tool_type.rstrip("s").to_lower()) + " textures already used on this map."
		used_button.connect("pressed",self,"on_used_assets_button_pressed",[tool_type,location,tool_type])

	# Configure the clear button with its icon & tooltip
	clear_button.icon = icon_texture
	clear_button.hint_tooltip = "Clear Search"
	# Listen for the pressed signal
	clear_button.connect("pressed",self,"on_clear_button_pressed",[tool_type,location])

	# Line 1 (hbox): "Search" label + dropdown + used_button + terrain_used_button
	# Line 2 (search_hbox): LineEdit (full width) + clear_button
	var search_hbox = HBoxContainer.new()
	ui_config[tool_type][location]["search_hbox"] = search_hbox

	# Populate buttons line
	label.text = "Search"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_config[tool_type][location]["hbox"].add_child(label)
	ui_config[tool_type][location]["hbox"].add_child(used_button)
	if tool_type == "PatternShapeTool":
		var terrain_used_button = Button.new()
		terrain_used_button.icon = ResourceLoader.load("res://ui/icons/tools/terrain_brush.png")
		terrain_used_button.hint_tooltip = "Load (where possible) the set of pattern textures matching the terrain textures already used on this map."
		terrain_used_button.connect("pressed",self,"on_used_assets_button_pressed",[tool_type,location,"TerrainBrush"])
		ui_config[tool_type][location]["hbox"].add_child(terrain_used_button)

	# Populate search bar line
	search_hbox.add_child(ui_config[tool_type][location]["search_entry"])
	search_hbox.add_child(clear_button)
	ui_config[tool_type][location]["search_entry"].size_flags_horizontal = 3

	# Add both lines to the vbox
	vbox.add_child(ui_config[tool_type][location]["hbox"])
	vbox.move_child(ui_config[tool_type][location]["hbox"],ui_index)
	ui_index += 1
	vbox.add_child(search_hbox)
	vbox.move_child(search_hbox,ui_index)

	# Listen for the text being entered and do the search
	ui_config[tool_type][location]["search_entry"].connect("text_entered",self,"on_new_search_text",[tool_type,location,"text_entered"])
	ui_config[tool_type][location]["search_entry"].connect("text_changed",self,"on_new_search_text",[tool_type,location,"text_changed"])
	ui_config[tool_type][location]["search_entry"].connect("focus_exited",self,"on_search_entry_changed_focus", [false])
	ui_config[tool_type][location]["search_entry"].connect("focus_entered",self,"on_search_entry_changed_focus", [true])


# Make a search ui for used objects tab taking over the current version
func make_search_ui_used_paths():

	var tool_type = "PathTool"
	var location = "main"
	var hbox = Global.Editor.PathLibraryPanel.find_node("Search")

	# Set up the base parameters
	ui_config[tool_type] = {}
	ui_config[tool_type][location] = {}
	ui_config[tool_type][location]["grid_menu"] = Global.Editor.PathLibraryPanel.PathMenu

	# Configure the clear button with its icon & tooltip
	var list_used_button = Button.new()
	list_used_button.icon = load_image_texture("res://ui/icons/tools/map_settings.png")
	list_used_button.hint_tooltip = "Search for paths already used on this map."
	# Listen for the pressed signal
	#func on_used_assets_button_pressed(tool_type: String, location: String, source_category: String):
	list_used_button.connect("pressed",self,"on_used_assets_button_pressed",[tool_type,location,tool_type])
	
	hbox.add_child(list_used_button)
	hbox.move_child(list_used_button,2)

# Make a search ui for used objects tab taking over the current version
func make_search_ui_used_objects():

	var tool_type = "ObjectTool"
	var location = "main"
	var vbox = Global.Editor.ObjectLibraryPanel.find_node("VAlign")
	var icon_texture = load_image_texture("ui/trash_icon.png")
	var label = Label.new()
	var sort_type_buttons = []

	# Set up the base parameters
	ui_config[tool_type] = {}
	ui_config[tool_type][location] = {}
	ui_config[tool_type][location]["hbox"] = HBoxContainer.new()
	ui_config[tool_type][location]["grid_menu"] = Global.Editor.ObjectLibraryPanel.objectMenu
	ui_config[tool_type][location]["sort_type"] = 0

	vbox.add_child(ui_config[tool_type][location]["hbox"])
	vbox.move_child(ui_config[tool_type][location]["hbox"],3)

	# Create search entry reference
	ui_config[tool_type][location]["search_entry"] = LineEdit.new()
	ui_config[tool_type][location]["search_entry_last_value"] = ""
	
	# Configure the clear button with its icon & tooltip
	var clear_button = Button.new()
	clear_button.icon = icon_texture
	clear_button.hint_tooltip = "Clear Search"
	# Listen for the pressed signal
	clear_button.connect("pressed",self,"on_clear_button_pressed",[tool_type,location])

	for _i in 4:
		sort_type_buttons.append(Button.new())
		sort_type_buttons[_i].toggle_mode = true
		# Listen for the pressed signal
		sort_type_buttons[_i].connect("toggled",self,"on_used_object_sorting_button_toggled",[_i])

	sort_type_buttons[0].icon = load_image_texture("res://ui/icons/menu/assets.png")
	sort_type_buttons[0].hint_tooltip = "Sort by pack & asset name"
	sort_type_buttons[1].icon = load_image_texture("ui/ascending-a-z.png")
	sort_type_buttons[1].hint_tooltip = "Sort by asset name only"
	sort_type_buttons[2].icon = load_image_texture("ui/recent.png")
	sort_type_buttons[2].hint_tooltip = "Sort most recently used first"
	sort_type_buttons[3].icon = load_image_texture("ui/oldest.png")
	sort_type_buttons[3].hint_tooltip = "Sort least recently used first"

	ui_config[tool_type][location]["sort_type_buttons"] = sort_type_buttons

	# Add the elements into the hbox
	label.text = "Search"
	ui_config[tool_type][location]["hbox"].add_child(label)
	ui_config[tool_type][location]["hbox"].add_child(ui_config[tool_type][location]["search_entry"])
	for _i in 4:
		ui_config[tool_type][location]["hbox"].add_child(ui_config[tool_type][location]["sort_type_buttons"][_i])
	
	ui_config[tool_type][location]["hbox"].add_child(clear_button)
	ui_config[tool_type][location]["search_entry"].size_flags_horizontal = 3
	# Listen for the text being entered and do the search
	ui_config[tool_type][location]["search_entry"].connect("text_entered",self,"on_new_search_text",[tool_type,location,"text_entered"])
	ui_config[tool_type][location]["search_entry"].connect("text_changed",self,"on_new_search_text",[tool_type,location,"text_changed"])
	ui_config[tool_type][location]["search_entry"].connect("focus_exited",self,"on_search_entry_changed_focus", [false])
	ui_config[tool_type][location]["search_entry"].connect("focus_entered",self,"on_search_entry_changed_focus", [true])

	# Listen to the toggles on all, used and tags buttons in order to show the search bar or not
	Global.Editor.ObjectLibraryPanel.allButton.connect("toggled", self, "on_object_filter_button_toggled",[Global.Editor.ObjectLibraryPanel.allButton])
	Global.Editor.ObjectLibraryPanel.usedButton.connect("toggled", self, "on_object_filter_button_toggled",[Global.Editor.ObjectLibraryPanel.usedButton])
	Global.Editor.ObjectLibraryPanel.tagsButton.connect("toggled", self, "on_object_filter_button_toggled",[Global.Editor.ObjectLibraryPanel.tagsButton])
	on_object_filter_button_toggled(true, Global.Editor.ObjectLibraryPanel.allButton)

#########################################################################################################
##
## TERRAIN WINDOW FUNCTIONS
##
#########################################################################################################

func setup_terrain_window():

	outputlog("setup_terrain_window")

	if terrainwindowui == null:
		var TerrainWindowUI = ResourceLoader.load(Global.Root + "TerrainWindowUI.gd", "GDScript", true)
		terrainwindowui = TerrainWindowUI.new(Global, Script)
		terrainwindowui.connect("terrain_selected", self, "_on_terrain_selected")
		Global.Editor.Toolset.GetToolPanel("TerrainBrush").connect("visibility_changed", self, "_connect_to_terrain_buttons",[null, 0.1])
		Global.Editor.Tools["TerrainBrush"].Controls["ExpandSlotsButton"].connect("toggled", self, "_connect_to_terrain_buttons",[0.1])
		terrainwindowui.make_search_history_ui()

func _connect_to_terrain_buttons(_ignore_this, delay: float = 0.1):

	outputlog("_connect_to_terrain_buttons",2)

	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	Global.Editor.get_node("Windows").add_child(timer)
	timer.start(delay)

	yield(timer,"timeout")

	var buttons = Global.Editor.Tools["TerrainBrush"].terrainButtonBox.get_children()

	for _i in buttons.size():
		if not buttons[_i].is_connected("pressed", self, "_on_terrain_selection_button_pressed"):
			buttons[_i].connect("pressed", self, "_on_terrain_selection_button_pressed",[_i])

	Global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

func _on_terrain_selection_button_pressed(index: int):

	terrainwindowui.target = index
	if Global.Editor.Windows["TerrainWindow"].visible:
		Global.Editor.Windows["TerrainWindow"].visible = false
		terrainwindowui.show()

func _on_terrain_selected(target: int, texture_path: String):

	outputlog("_on_terrain_selected: target: " +str(target) + " texture_path: " + str(texture_path),2)

	var texture = safe_load_texture(texture_path)
	Global.Editor.Tools["TerrainBrush"].SetTextureFromWindow(texture, target)




#########################################################################################################
##
## SEARCH HISTORY FUNCTIONS
##
#########################################################################################################

# Function to make a search history capability for Object Library Panel
func make_search_history_for_tool_ui(tool_type: String, location: String):

	outputlog("make_search_history_for_tool_ui: tool_type" + str(tool_type) + " location: " + str(location))

	var search_hbox = null
	var search_lineedit = null

	if tool_type in ["ObjectTool","PathTool"]:
		# Ignore select requests for objects and paths and the library and search entry is common
		if location == "select": return
		# Finf the search hbox containers
		match tool_type:
			"ObjectTool":
				search_hbox = Global.Editor.ObjectLibraryPanel.filters.find_node("Search")
			"PathTool":
				search_hbox = Global.Editor.PathLibraryPanel.filters.find_node("Search")
			_:
				return

		# Find the nodes for the in built search box and line edit
		if search_hbox == null:
			return
		# Look for the search line edit
		search_lineedit = search_hbox.find_node("SearchLineEdit")
		ui_config[tool_type][location]["dd_search_entry"] = search_lineedit
	else:
		search_hbox = ui_config[tool_type][location]["hbox"]
		search_lineedit = ui_config[tool_type][location]["search_entry"]


	if search_hbox != null && search_lineedit != null:
		make_search_history_ui(search_hbox, search_lineedit)

# Function to make a search history capability for Object Library Panel
func make_search_history_ui(search_hbox: HBoxContainer, search_lineedit: LineEdit):

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

#########################################################################################################
##
## APPLY PREFERENCES FUNCTION
##
#########################################################################################################

func on_preferences_apply_pressed():

	outputlog("on_preferences_apply_pressed")

	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	Global.Editor.get_node("Windows").add_child(timer)

	timer.start(0.5)
	yield(timer,"timeout")
	
	max_history_search_terms = int(_lib_mod_config.search_entries_slider)
	logging_level = int(_lib_mod_config.core_log_level)

	Global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

#########################################################################################################
##
## VERSION CHECKER FUNCTIONS
##
#########################################################################################################

# Check whether a semver strng 2 is greater than string one. Only works on simple comparisons - DO NOT USE THIS FUNCTION OUTSIDE THIS CONTEXT
func compare_semver(semver1: String, semver2: String) -> bool:

	outputlog("compare_semver: semver1: " + str(semver1) + " semver2" + str(semver2),2)
	var semver1data = get_semver_data(semver1)
	var semver2data = get_semver_data(semver2)

	if semver1data == null || semver2data == null : return false

	if semver1data["major"] != semver2data["major"]:
		return semver1data["major"] < semver2data["major"]
	if semver1data["minor"] != semver2data["minor"]:
		return semver1data["minor"] < semver2data["minor"]
	if semver1data["patch"] != semver2data["patch"]:
		return semver1data["major"] < semver2data["major"]
	
	return false

# Parse the semver string
func get_semver_data(semver: String):

	var data = {}

	if semver.split(".").size() < 3: return null

	return {
		"major": int(semver.split(".")[0]),
		"minor": int(semver.split(".")[1]),
		"patch": int(semver.split(".")[2].split("-")[0])
	}

#########################################################################################################
##
## START FUNCTION
##
#########################################################################################################

# Function to update the config label
func update_config_label(value, label: Label):

	label.text =  "%0d" % value

# Main Script
func start() -> void:

	outputlog("AdditionalSearchOptions Mod Has been loaded.")

	# If _Lib is installed then register with it
	if Engine.has_signal("_lib_register_mod"):
		
		# Register this mod with _lib
		Engine.emit_signal("_lib_register_mod", self)

		# Create a config builder to ensure we can store the keys if changed in preferences
		var _lib_config_builder = Global.API.ModConfigApi.create_config()
		_lib_config_builder\
			.check_button("search_on_text_changed", true, "Enable search on any text changed without requiring carriage return.")\
			.check_button("refresh_grid_colours", false, "Refresh the wall and pattern colours in the grid when searching.")\
			.h_box_container().enter()\
				.label("Max Search Entries: ")\
				.label().ref("slider_label")\
				.label(" ")\
				.h_slider("search_entries_slider",10)\
					.with("max_value",30)\
					.with("min_value",1)\
					.with("step",1)\
					.connect_current("loaded", self, "update_config_label", [_lib_config_builder.get_ref("slider_label")])\
					.connect_current("value_changed", self, "update_config_label", [_lib_config_builder.get_ref("slider_label")])\
					.size_flags_h(Control.SIZE_EXPAND_FILL)\
					.size_flags_v(Control.SIZE_FILL)\
			.exit()\
			.h_box_container().enter()\
				.label("Core Log Level ")\
				.option_button("core_log_level", 0, ["0","1","2","3","4"])\
			.exit()
		_lib_mod_config = _lib_config_builder.build()
		max_history_search_terms = int(_lib_mod_config.search_entries_slider)
		update_config_label(max_history_search_terms,_lib_config_builder.get_ref("slider_label"))

		# Link to the pressed field so we can update the search terms and logging
		Global.API.PreferencesWindowApi.connect("apply_pressed", self, "on_preferences_apply_pressed")
				
		logging_level = int(_lib_mod_config.core_log_level)
		var _lib_mod_meta = Global.API.ModRegistry.get_mod_info("CreepyCre._Lib").mod_meta
		if _lib_mod_meta != null:
			if compare_semver("1.1.2", _lib_mod_meta["version"]):
				var update_checker = Global.API.UpdateChecker
				
				update_checker.register(Global.API.UpdateChecker.builder()\
														.fetcher(update_checker.github_fetcher("uchideshi34", "AdditionalSearchOptions"))\
														.downloader(update_checker.github_downloader("uchideshi34", "AdditionalSearchOptions"))\
														.build())

	# Make the UI elements for the search capability
	make_search_ui("PatternShapeTool", "main")
	make_search_ui("PatternShapeTool", "select")
	make_search_ui("WallTool", "main")
	make_search_ui("WallTool", "select")
	make_search_ui("LightTool", "main")
	make_search_ui("LightTool", "select")
	make_search_ui("RoofTool", "main")
	make_search_ui("PortalTool", "main")
	make_search_ui("TerrainBrush", "main")

	make_search_ui_used_objects()
	make_search_ui_used_paths()

	setup_terrain_window()

	# Check for the launch of the Object or Scatter Tool and refresh the Used
	for tool_type in ["ObjectTool","ScatterTool"]:
		Global.Editor.Toolset.ToolPanels[tool_type].connect("visibility_changed",self, "on_toolpanel_visibility_changed",[tool_type])
		Global.Editor.TagsPanels[tool_type].tagsList.connect("multi_selected", self, "on_tagspanel_multi_selected")

	Global.Editor.Toolset.ToolPanels["TerrainBrush"].connect("visibility_changed",self, "setup_terrain_window")

	for tool_type in ["PatternShapeTool", "ObjectTool", "PathTool", "WallTool", "LightTool", "RoofTool", "PortalTool", "TerrainBrush"]:
		for location in ["main","select"]:
			if location == "select" && tool_type in ["RoofTool","ObjectTool","PathTool","TerrainBrush"]:
				continue
			make_search_history_for_tool_ui(tool_type, location)
	

