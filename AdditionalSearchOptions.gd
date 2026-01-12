# Dungeondraft mod to add ability to search for walls, terrain and patterns in the tool panel
var script_class = "tool"

# Variables
var ui_config: Dictionary
var invisible_tool_panel
var pattern_tool_panel 
var pattern_types = ["No Search","Simple Tiles","Patterns","Patterns Colorable"]
var floor_types = ["No Search","Simple Tiles","Smart Tiles","Smart Tiles Double"]
var select_tool_panel
var wall_tool_panel
var terrain_tool_panel
var light_tool_panel
var roof_tool_panel
var portal_tool_panel
var last_delta
var search_focus = null
var last_entry = ""
var _lib_mod_config
var store_last_valid_selection = null

const UNIQUE_ID = "uchideshi34.AdditionalSearchOptions"

var MAX_HISTORY_SEARCH_TERMS = 10

# Logging Functions
const ENABLE_LOGGING = true
const LOGGING_LEVEL = 0

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= LOGGING_LEVEL:
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
		return "portals"

	# Note this is also true of portals but we caught those with WallID
	elif node.get("Sprite") != null:
		return "objects"
	elif node.get("FadeIn") != null:
		return "paths"
	elif node.get("HasOutline") != null:
		return "pattern_shapes"
	elif node.get("Joint") != null:
		return "walls"

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
func find_select_grid_menu(category_type: String):

	match category_type:
		"Patterns":
			return select_tool_panel.patternTextureMenu
		"Walls":
			return select_tool_panel.wallTextureMenu
		"Lights":
			return select_tool_panel.lightTextureMenu
		"Portals":
			return select_tool_panel.portalTextureMenu
		_:
			outputlog("Error in find_select_grid_menu: vbox section not found. " + category_type)
			return null

# Make a check button in an invisible tool panel so we don't get a silly error
func make_check_button(vbox, button_text: String, default_state: bool, ui_index: int, on_toggled_function: String):

	# Make a Check Button in the invisible tool panel
	var button = invisible_tool_panel.CreateCheckButton(button_text,"",default_state)
	# Remove it from that tool panel
	invisible_tool_panel.Align.remove_child(button)
	# Add it to the required vbox
	vbox.add_child(button)
	# Listen for toggled signal and call the right function
	button.connect("toggled",self,on_toggled_function)

	# Might as well put it in the right place in this function
	if ui_index > -1:
		vbox.move_child(button,ui_index)

	return button

# Set the Global SearchHasFocus value
func on_search_entry_changed_focus(search_has_focus):

	outputlog("on_search_entry_changed_focus: " + str(search_has_focus),2)
	Global.Editor.SearchHasFocus = search_has_focus


#########################################################################################################
##
## RESET FUNCTIONS
##
#########################################################################################################

# Main function to clear the grid and reset
func on_clear_button_pressed(category_type: String, tool_name: String):

	outputlog("on_clear_button_pressed")

	# Clear everything if needed
	if ui_config[category_type][tool_name]["search_entry"].text.length() > 0:
		ui_config[category_type][tool_name]["search_entry"].clear()
	ui_config[category_type][tool_name]["search_entry_last_value"] = ""

	# Reload the pattern types in turn
	if category_type == "Objects":
		on_used_objects_reset()
	else:
		ui_config[category_type][tool_name]["grid_menu"].Reset()
		# If this is a portal search and we are in the main tool, the PostInit() function will add back the null portal
		if category_type == "Portals" && tool_name == "Main":
			Global.Editor.Tools["PortalTool"].PostInit()

	# Check whether there are any items in the list and if we are not in the pattern tool, then cycle through all the items to update the default colours
	refresh_colours_in_grid_menu(category_type,tool_name)
	
# A litte function to run through and select each grid item menu in turn, note this isn't effective if no initial selection has been made
func select_each_item_in_grid_menu(category_type: String, tool_name: String):

	outputlog("select_each_item_in_grid_menu: category_type: " + str(category_type) + " tool_name: " + str(tool_name),2)

	var grid_menu = ui_config[category_type][tool_name]["grid_menu"]

	grid_menu.select(0)

	for _i in grid_menu.get_item_count():
		grid_menu.SelectNext()

# Perform a full reset on a Patterns grid
func full_Patterns_grid_reset(tool_name: String):

	var category_type = "Patterns"

	# Clear everything
	ui_config[category_type][tool_name]["search_entry"].clear()

	# Reload the pattern types in turn
	for _i in range(1,pattern_types.size(),1):
		# Load the type
		ui_config[category_type][tool_name]["grid_menu"].Load(pattern_types[_i])
		# Once we have loaded one category then reset to blank all but that category
		if _i == 1:
			ui_config[category_type][tool_name]["grid_menu"].Reset()
	
	# If we are in the Main tool and there are non-zero numbers of simple tiles then in order to display custom colours, cycle through those and select them. Don't do this on the select tool.
	if tool_name == "Main" && Script.GetAssetList("Simple Tiles").size() > 0:
		# Check whether there are any items in the list and if we are not in the pattern tool, then cycle through all the items to update the default colours
		refresh_colours_in_grid_menu(category_type,tool_name)

# When the list of used objects needs to be completely reset
func on_used_objects_reset():

	var category_type = "Objects"
	var tool_name = "Main"

	var array_textures = []
	var thumbnail_textures = []
	var thumbnail_url

	array_textures = find_assets_used_in_map(category_type, "n/a", category_type,ui_config[category_type][tool_name]["sort_type"])

	# Find all the thumbnails
	for texture_path in array_textures:
		thumbnail_url = find_thumbnail_url(texture_path)
		if thumbnail_url != null:
			thumbnail_textures.append(load(thumbnail_url))

	# Set the pattern grid menu to only show the list of thumbnail textures
	ui_config["Objects"]["Main"]["grid_menu"].ShowSet(thumbnail_textures)

	
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
func on_new_search_text(search_text: String, category_type: String, tool_name: String, source_type: String):

	var array_textures = []
	var result
	var thumbnail_textures = []
	var grid_menu = ui_config[category_type][tool_name]["grid_menu"]
	var category: String
	var thumbnail_url

	outputlog("on_new_search_text: " + str(search_text) + " category_type: " + str(category_type) + " tool_name: " + str(tool_name))

	# If we have installed _Lib check for the search_on_text_changed status
	if Engine.has_signal("_lib_register_mod"):
		# If search_on_text_changed not active and the source is a text_changed signal then do nothing
		if not _lib_mod_config.search_on_text_changed && source_type == "text_changed":
			return

	# If the search is blank then reset everything using the clear button feature
	if search_text.length() < 1:
		outputlog("search_text length is : " + str(search_text.length()),2)
		on_clear_button_pressed(category_type,tool_name)
		return

	# Set the search text to lower just to improve matching
	search_text = search_text.to_lower()
	
	if category_type == "Patterns":
		# Set the category according to the drop down selection
		category = pattern_types[ui_config[category_type][tool_name]["dropdown"].selected]
		# Reset the grid menu so it knows that thumbnails of this category are coming just to be sure although this should be the case already.
		grid_menu.Load(category)
	else:
		category = category_type
	
	# Get a list of all possible assets in the right category
	if category_type == "Objects":
		array_textures = find_assets_used_in_map(category_type, category, category_type,ui_config[category_type][tool_name]["sort_type"])
	else:
		array_textures = Script.GetAssetList(category)
	
	outputlog("array_textures size: " + str(array_textures.size()),2)

	# Look through each asset and determine if it matches the search string
	for texture_path in array_textures:
		# If it is Roof then the name of the roof is the part before the final piece e.g. /roof_name/tiles.png
		if category == "Roofs":
			result = texture_path.split("/")[-2].to_lower()
		# find the name of the asset by looking at the right hand side of the url and stripping off the extension then changing to lower
		else:
			result = texture_path.split("/")[-1].split(".")[0].to_lower()
		# If the search string is contained in the asset name then do something with it
		#if result.find(search_text) > -1:
		if is_valid_search_result(result, search_text):
			# Take the url of the texture, derive the url of the thumbnail, load the texture of that thumbnail and add it to a list
			thumbnail_url = find_thumbnail_url(texture_path)
			if thumbnail_url != null:
				thumbnail_textures.append(load(thumbnail_url))
	
	outputlog("search results size: " + str(thumbnail_textures.size()),2)
	
	# Set the pattern grid menu to only show the list of thumbnail textures
	grid_menu.ShowSet(thumbnail_textures)

	# If this is a portal search and we are in the main tool, the PostInit() function will add back the null portal
	if category_type == "Portals" && tool_name == "Main":
		Global.Editor.Tools["PortalTool"].PostInit()

	# Check whether there are any items in the list and if we are not in the pattern tool, then cycle through all the items to update the default colours
	refresh_colours_in_grid_menu(category_type,tool_name)

	outputlog("finished show set",2)


# Function to update the grid menu to list all the assets previously used on this map (all levels)
func on_used_assets_button_pressed(category_type: String, tool_name: String, source_category: String):

	var array_textures = []
	var result
	var thumbnail_textures = []
	var grid_menu = ui_config[category_type][tool_name]["grid_menu"]
	var category: String
	var thumbnail_url

	outputlog("on_used_assets_button_pressed: " + str(category_type) + "location: " + str(tool_name) + " source_category: " + str(source_category))

	# If the search is blank then reset everything using the clear button feature, but don't do this for paths as we don't own the search text field
	if category_type != "Paths":
		ui_config[category_type][tool_name]["search_entry"].clear()
		ui_config[category_type][tool_name]["search_entry_last_value"] = ""
	
	# If the category is patterns
	if category_type == "Patterns":
		# Set the category according to the drop down selection
		category = pattern_types[ui_config[category_type][tool_name]["dropdown"].selected]
		# Reset the grid menu so it knows that thumbnails of this category are coming just to be sure although this should be the case already.
		grid_menu.Load(category)
	else:
		category = category_type

	# Get a list of all possible assets in the right category
	array_textures = find_assets_used_in_map(category_type, category, source_category,0)

	# Look through each asset and get its thumbnail
	for texture_path in array_textures:
		# Take the url of the texture, derive the url of the thumbnail, load the texture of that thumbnail and add it to a list
		thumbnail_url = find_thumbnail_url(texture_path)
		if thumbnail_url != null:
			thumbnail_textures.append(load(thumbnail_url))

	# Set the pattern grid menu to only show the list of thumbnail textures
	grid_menu.ShowSet(thumbnail_textures)

	# If this is a portal search and we are in the main tool, the PostInit() function will add back the null portal
	if category_type == "Portals" && tool_name == "Main":
		Global.Editor.Tools["PortalTool"].PostInit()

	# Check whether there are any items in the list and if we are not in the pattern tool, then cycle through all the items to update the default colours
	refresh_colours_in_grid_menu(category_type,tool_name)

# Function that refreshes the visible colours in the grid menu
func refresh_colours_in_grid_menu(category_type: String, tool_name: String):

	var grid_menu = ui_config[category_type][tool_name]["grid_menu"]

	# If _Lib installed and the refresh grid colours not active then don't refresh the grid colours
	if Engine.has_signal("_lib_register_mod"):
		if not _lib_mod_config.refresh_grid_colours:
			return

	# Check whether there are any items in the list and if we are not in the pattern tool, then cycle through all the items to update the default colours
	if grid_menu.get_item_count() > 0 && tool_name != "Select":
		# Select the first item in the list if there is anything in the list
		grid_menu.select(0)
		# This tells the GridMenu to actually use this value
		grid_menu.OnItemSelected(0)
		# Make a loop for all the items being displayed
		# In order to display custom colours on walls and tile sets
		if category_type == "Walls" && Global.Header.UsesDefaultAssets:
			select_each_item_in_grid_menu(category_type,tool_name)
		# If this is about patterns and specifically for Simple Tiles.
		if category_type == "Patterns":
			if pattern_types[ui_config[category_type][tool_name]["dropdown"].selected] == "Simple Tiles":
				select_each_item_in_grid_menu(category_type,tool_name)


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
func find_assets_used_in_map(category_type: String, category: String, source_category: String, sort_type: int):

	var array_of_texture_paths = []
	var url_match_array = {
		"Simple Tiles": "tilesets/simple/",
		"Patterns": "patterns/normal/",
		"Patterns Colorable": "patterns/colorable/",
		"Terrain": "terrain/",
		"Lights": "lights/",
		"Portals": "portals/"
	}
	var temp_resource_path: String
	var resource_path_data: Dictionary
	var array_of_asset_data = []
	var thumbnail_url

	# For each level in the world
	for level in Global.World.levels:
		# If patterns then look for patterns
		if category_type == "Patterns":
			# If this is a normal search then look for pattern shapes
			if source_category == category_type:
				for patternshape in level.PatternShapes.GetShapes():
					# If the resource path of the pattern matches the value for the category the add it
					if url_match_array[category] in patternshape._Texture.resource_path:
						array_of_texture_paths.append(patternshape._Texture.resource_path)
			# If the source category is Terrain
			elif source_category == "Terrain":
				# For each terrain on the level
				for terrain in level.Terrain.textures:
					array_of_texture_paths.append(terrain.resource_path)
				
		# If walls then look for walls
		elif category_type == "Walls":
			for wall in level.Walls.get_children():
				array_of_texture_paths.append(wall.Texture.resource_path)
		
		# If paths then look for paths
		elif category_type == "Paths":
			for pathway in level.Pathways.get_children():
				array_of_texture_paths.append(pathway.get_texture().resource_path)

		# If Terrain then look for used pattern shapes and record those to be sorted and made unique
		elif category_type == "Terrain":
			for patternshape in level.PatternShapes.GetShapes():
				# If the resource path of the pattern matches the value for the category the add it
				array_of_texture_paths.append(patternshape._Texture.resource_path)
		
		# If Lights then look for used lights
		elif category_type == "Lights":
			for light in level.Lights.get_children():
				# If the resource path of the pattern matches the value for the category the add it
				array_of_texture_paths.append(light.get_texture().resource_path)
		
		# If Roofs then look for used roofs
		elif category_type == "Roofs":
			for roof in level.Roofs.get_children():
				# If the resource path of the pattern matches the value for the category the add it
				array_of_texture_paths.append(roof.TilesTexture.resource_path)
		
		# If Lights then look for used portals
		elif category_type == "Portals":
			for portal in level.Portals.get_children():
				# If the resource path of the portal matches the value for the category the add it
				array_of_texture_paths.append(portal.Texture.resource_path)
			# Look through all the walls and get and portals in them
			for wall in level.Walls.get_children():
				for portal in wall.Portals:
					array_of_texture_paths.append(portal.Texture.resource_path)

		# If searching for Objects in the Used tab
		elif category_type == "Objects":
			for prop in level.Objects.get_children():
				# Avoid Weird props no node_id and with default asset textures
				if "node_id" in prop.get_meta_list():
					array_of_asset_data.append({"texture_path": prop.Texture.resource_path, "asset_name": find_texture_name_and_pack(prop.Texture.resource_path)["texture_name"], "node_id": ("0x" + str(prop.get_meta("node_id"))).hex_to_int()})

	# If we need to build a new array of textures from a array of dictionary entries
	if category_type == "Objects":

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
	if category_type != source_category:
		# Make a copy of the pattern texture paths
		var copy_of_array = array_of_texture_paths.duplicate()
		# Clear the destination array which will be rebuilt with terrain texture paths
		array_of_texture_paths.clear()
		# For each (now unique) pattern resource path, look for a matching and validate terrain resource path
		for texture_resource_path in copy_of_array:
			# Extract the dictionary of resource data {"texture_name": texture_name,"pack_name": pack_name, "pack_id": pack_id}
			resource_path_data = find_texture_name_and_pack(texture_resource_path)
			# Construct a potential resource path for the matching terrain asset
			temp_resource_path = "res://packs/" + resource_path_data["pack_id"] + "/textures/" + url_match_array[category_type] + resource_path_data["texture_name"] + "." + texture_resource_path.split(".")[1]
			# If there exists a thumbnail file for this path then add the url of the resource path to the array of textures. Not sure why I can't directly use ResourceLoader on the file itself!
			thumbnail_url = find_thumbnail_url(temp_resource_path)
			if thumbnail_url != null:
				array_of_texture_paths.append(load(thumbnail_url))

	return array_of_texture_paths



#########################################################################################################
##
## UI DRIVEN FUNCTIONS
##
#########################################################################################################

# Function to reset the grid menu if a different category is selected.
func on_Patterns_dropdown_selected(selected_index, tool_name):

	var category_type = "Patterns"

	# If non-search parameter is selected, then disable the search field
	if selected_index == 0:
		# Call the reset function to restore the visibility of all pattern types
		full_Patterns_grid_reset(tool_name)
		# Make the search entry hbox hidden
		ui_config[category_type][tool_name]["hbox"].visible = false
	# Otherwise show the pattern list and run the search
	else:
		# Unhide the search entry hbox
		ui_config[category_type][tool_name]["hbox"].visible = true
		# Clear everything that's in the grid
		# Load the new assets.
		ui_config[category_type][tool_name]["grid_menu"].Load(pattern_types[selected_index])
		# Run the current search against them
		on_new_search_text(ui_config[category_type][tool_name]["search_entry"].text, category_type, tool_name, "internal")

# Toggle terrain search visibility
func on_terrain_active_button_pressed(value):

	var category_type = "Terrain"
	var tool_name = "Main"

	if value:
		ui_config[category_type][tool_name]["section"].visible = true
		for ui_element in ui_config[category_type][tool_name]["hide_ui"]:
			ui_element.visible = false
	else:
		ui_config[category_type][tool_name]["section"].visible = false
		for ui_element in ui_config[category_type][tool_name]["hide_ui"]:
			ui_element.visible = true

# If we press the set terrain button, then set the terrain slot texture based on the grid value selected and the slot in the drop down
func on_set_terrain_slot_button_pressed():

	var category_type = "Terrain"
	var tool_name = "Main"
	var thumbnail_path
	var thumbnail_texture
	var thumbnail_name
	var index
	var texture = ui_config[category_type][tool_name]["grid_menu"].Selected
	var terrain_list = Global.Editor.Tools["TerrainBrush"].terrainList

	index = Global.Editor.Tools["TerrainBrush"].TerrainID
	
	# If we have a valid texture selected then set it
	if texture:

		# Get the details of the terrain's thumbnail so we can update the UI
		thumbnail_path = find_thumbnail_url(texture.resource_path)
		if thumbnail_path != null:
		
			thumbnail_name = texture.resource_path.split("/")[-1].split(".")[0]
			thumbnail_texture = ResourceLoader.load(thumbnail_path)

			# Update the visuals of the terrain brush tool to reflect the change we have made
			terrain_list.set_item_text(index,thumbnail_name)
			terrain_list.set_item_icon(index,thumbnail_texture)
			terrain_list.set_item_tooltip(index,thumbnail_name)

			# Set the texture on the map itself
			Global.World.GetCurrentLevel().Terrain.SetTexture(texture, index)

# If requested to move the panel to the rightside
func on_terrain_rh_panel_button_pressed(value):

	var category_type = "Terrain"
	var tool_name = "Main"

	if value:
		# If there isn't a rightside panel created then make one
		if not ui_config[category_type][tool_name].has("rh_panel"):
			ui_config[category_type][tool_name]["rh_panel"] = terrain_tool_panel.CreateRightsidePanel("Search Terrain")
		
		# Make the right hand panel visible as you need to flash away to get this working
		ui_config[category_type][tool_name]["rh_panel"].visible = true
		Global.Editor.Toolset.Quickswitch("ObjectTool")
		Global.Editor.Toolset.Quickswitch("TerrainBrush")
		
		# Move the section containing all of the buttons and grid and stuff to the right hand side
		terrain_tool_panel.Align.remove_child(ui_config[category_type][tool_name]["section"])
		ui_config[category_type][tool_name]["rh_panel"].Align.add_child(ui_config[category_type][tool_name]["section"])
		
	else:
		# If the panel doesn't exist for some strange reason then do nothing
		if not ui_config[category_type][tool_name].has("rh_panel"):
			return
		
		# Hide the right hand panel - note this doesn't work for some reason
		ui_config[category_type][tool_name]["rh_panel"].visible = false
		Global.Editor.Toolset.Quickswitch("ObjectTool")
		Global.Editor.Toolset.Quickswitch("TerrainBrush")

		# Move the section containing all of the buttons and grid and stuff back to the left hand side
		ui_config[category_type][tool_name]["rh_panel"].Align.remove_child(ui_config[category_type][tool_name]["section"])
		terrain_tool_panel.Align.add_child(ui_config[category_type][tool_name]["section"])



# Hide the search bar unless the "Used" tab is open
func on_object_filter_button_toggled(new_state):
	var category_type = "Objects"
	var tool_name = "Main"

	if Global.Editor.ObjectLibraryPanel.usedButton.pressed:
		ui_config[category_type][tool_name]["hbox"].visible = true
	elif Global.Editor.ObjectLibraryPanel.tagsButton.pressed:
		ui_config[category_type][tool_name]["hbox"].visible = false
	else:
		ui_config[category_type][tool_name]["hbox"].visible = false
	

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
				ui_config["Objects"]["Main"]["dd_search_entry"].emit_signal("text_entered",ui_config["Objects"]["Main"]["dd_search_entry"].text)
	
	Global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

# Function to toggle sorting state
func on_used_object_sorting_button_toggled(new_state: bool, sort_type: int):

	var category_type = "Objects"
	var tool_name = "Main"

	if not new_state:
		return
	
	# Set the other buttons to not pressed
	for _i in 4:
		if _i != sort_type:
			ui_config[category_type][tool_name]["sort_type_buttons"][_i].pressed = false
	
	# Record the current sort type
	ui_config[category_type][tool_name]["sort_type"] = sort_type
	on_clear_button_pressed(category_type,tool_name)

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

# Find the UI elements of the terrain tool that we can hide if search is enabled
func find_terrain_ui_to_be_suppressed():

	outputlog("find_terrain_ui_to_be_suppressed")

	var category_type = "Terrain"
	var tool_name = "Main"

	ui_config[category_type][tool_name]["hide_ui"] = []

	# Look through all the elements in the terrain brush UI and add the ones we want to hide to the ui_config
	for thing in terrain_tool_panel.Align.get_children():
		if thing is Label || thing is Button:
			if thing.text.to_upper() in ["BIOME","SETTLEMENT","WARNING: UNLOCKING MORE SLOTS CAN DRASTICALLY REDUCE PERFORMANCE", "TERRAIN_EXPAND_WARNING"]:
				ui_config[category_type][tool_name]["hide_ui"].append(thing)
	

# Making a general function for creating the elements of UI for search
func make_search_ui(tool_panel, category_type: String, tool_name: String):

	var label = Label.new()
	var type_label = Label.new()
	var clear_button = Button.new()
	var used_button = Button.new()
	var terrain_used_button
	
	var icon_texture
	var icon_path = Global.Root + "ui/trash_icon.png"
	var icon_image = Image.new()
	var err = icon_image.load(icon_path)
	var ui_index
	var vbox

	if err != OK:
		# Failed
		outputlog("Failed to load trash icon")
	
	outputlog("make_search_ui: " + str(category_type) + " location: " + str(tool_name))

	# Load the clear icon from file path
	icon_texture = ImageTexture.new()
	icon_texture.create_from_image(icon_image, 0)

	icon_texture = load_image_texture("ui/trash_icon.png")

	# Create dictionary entries for the UI
	if not ui_config.has(category_type):
		ui_config[category_type] = {}
	
	if not ui_config[category_type].has(tool_name):
		ui_config[category_type][tool_name] = {}
	
	# Find grid menu reference
	# If we are looking to construct the main panel search
	if tool_name == "Main":
		# vbox is the main tool panel align vbox
		vbox = tool_panel.Align
		# Look for the grid menu in the tool panel
		if category_type != "Terrain":
			for thing in vbox.get_children():
				# If the node is a grid menu then it should be the right thing
				if thing is ItemList:
					ui_config[category_type][tool_name]["grid_menu"] = thing
					break
		# If this is a terrain tool then we need to make a few more things in particular a grid menu
		else:
			# Make an option button to activate search UI
			ui_config[category_type][tool_name]["active_button"] = make_check_button(tool_panel.Align, "Enable Terrain Search", false, -1, "on_terrain_active_button_pressed")
			
			# Begin a section that will get hidden if the option button is not selected
			ui_config[category_type][tool_name]["section"] = tool_panel.BeginSection(true)
			# Make a button to set the terrain slot
			ui_config[category_type][tool_name]["set_button"] = tool_panel.CreateButton("Set Terrain Slot", "res://ui/icons/tools/terrain_brush.png")
			ui_config[category_type][tool_name]["set_button"].connect("pressed",self,"on_set_terrain_slot_button_pressed")
			# Make a grid menu
			ui_config[category_type][tool_name]["grid_menu"] = tool_panel.CreateTextureGridMenu("TerrainTextureGridID",category_type,true)
			ui_config[category_type][tool_name]["grid_menu"].ShowsPreview = false
			tool_panel.EndSection()
			# Make an option button to activate search UI
			ui_config[category_type][tool_name]["rh_panel_button"] = make_check_button(ui_config[category_type][tool_name]["section"], "Move Search To RH Panel", false, 0, "on_terrain_rh_panel_button_pressed")
			
			ui_config[category_type][tool_name]["section"].visible = false
			vbox = ui_config[category_type][tool_name]["section"]

			# Find the UI elements in the terrain tool that we don't really need if search is enabled
			find_terrain_ui_to_be_suppressed()

	# Or if we are looking at the Select tool
	elif tool_name == "Select":
		# find the select grid menu, noting that category_type in the labels is the singular version of the category_type
		ui_config[category_type][tool_name]["grid_menu"] = find_select_grid_menu(category_type)
		# Apparent get_parent is bad practice in general but we are probably safe in this context. Find the parent node in the select ui which should be the section made visible when that category of asset is found.
		vbox = ui_config[category_type][tool_name]["grid_menu"].get_parent()
	# Set the index to start adding things
	ui_index = ui_config[category_type][tool_name]["grid_menu"].get_index()

	# Make a line for the search entry
	ui_config[category_type][tool_name]["hbox"] = HBoxContainer.new()

	# If we are setting up Patterns then we need to set ui to select the different types of patterns, ie Patterns, Simple Tiles and Colurable Patterns
	if category_type == "Patterns":

		# Define a dropdown button to choose the right type of pattern
		# Make a dropdown button with options for each pattern type
		var hbox = HBoxContainer.new()
		var dd_label = Label.new()
		var option_button = OptionButton.new()

		dd_label.text = "Search Type"
		for value in pattern_types:
			option_button.add_item(value)
		option_button.size_flags_horizontal = 3
		option_button.align = 1
		hbox.add_child(dd_label)
		hbox.add_child(option_button)

		# Link the option_button the main UI config and connect the signal
		ui_config[category_type][tool_name]["dropdown"] = option_button
		ui_config[category_type][tool_name]["dropdown"].connect("item_selected",self,"on_Patterns_dropdown_selected",[tool_name])
		# Move the hbox to the right place in the UI
		vbox.add_child(hbox)
		vbox.move_child(hbox,ui_index)
		ui_index += 1

		# Finally set the default values as "No Search"
		ui_config[category_type][tool_name]["dropdown"].selected = 0
		ui_config[category_type][tool_name]["hbox"].visible = false
	
	# Create search entry reference
	ui_config[category_type][tool_name]["search_entry"] = LineEdit.new()

	# Add the hbox of the search entry to the tool panel and move it to the right place
	vbox.add_child(ui_config[category_type][tool_name]["hbox"])
	vbox.move_child(ui_config[category_type][tool_name]["hbox"],ui_index)

	# Create a button for loading into patterns list
	if category_type == "Patterns":
		terrain_used_button =  Button.new()
		terrain_used_button.icon = ResourceLoader.load("res://ui/icons/tools/scatter_tool.png")
		terrain_used_button.hint_tooltip = "Load (where possible) the set of pattern textures matching the terrain textures already used on this map."
		terrain_used_button.connect("pressed",self,"on_used_assets_button_pressed",[category_type,tool_name,"Terrain"])

	# Make the hbox search entry with a label, the lineedit and a clear button
	
	# If search type is terrain then use patterns as the source
	if category_type == "Terrain":
		used_button.icon = ResourceLoader.load("res://ui/icons/tools/scatter_tool.png")
		used_button.hint_tooltip = "Load (where possible) the set of terrain textures matching the pattern textures already used on this map."
		used_button.connect("pressed",self,"on_used_assets_button_pressed",[category_type,tool_name,"Patterns"])
	# Otherwise use the current category (which is the usual one)
	else:
		used_button.icon = ResourceLoader.load("res://ui/icons/tools/map_settings.png")
		used_button.hint_tooltip = "Load the set of " + str(category_type.rstrip("s").to_lower()) + " textures already used on this map."
		used_button.connect("pressed",self,"on_used_assets_button_pressed",[category_type,tool_name,category_type])

	# Configure the clear button with its icon & tooltip
	clear_button.icon = icon_texture
	clear_button.hint_tooltip = "Clear Search"
	# Listen for the pressed signal
	clear_button.connect("pressed",self,"on_clear_button_pressed",[category_type,tool_name])
	# Add the elements into the hbox
	label.text = "Search"
	ui_config[category_type][tool_name]["hbox"].add_child(label)
	ui_config[category_type][tool_name]["hbox"].add_child(ui_config[category_type][tool_name]["search_entry"])
	ui_config[category_type][tool_name]["hbox"].add_child(used_button)
	# For Patterns or Walls, add a button that lists any items already used in the menu
	if category_type == "Patterns":
		ui_config[category_type][tool_name]["hbox"].add_child(terrain_used_button)

	ui_config[category_type][tool_name]["hbox"].add_child(clear_button)
	ui_config[category_type][tool_name]["search_entry"].size_flags_horizontal = 3
	# Listen for the text being entered and do the search
	ui_config[category_type][tool_name]["search_entry"].connect("text_entered",self,"on_new_search_text",[category_type,tool_name,"text_entered"])
	ui_config[category_type][tool_name]["search_entry"].connect("text_changed",self,"on_new_search_text",[category_type,tool_name,"text_changed"])
	ui_config[category_type][tool_name]["search_entry"].connect("focus_exited",self,"on_search_entry_changed_focus", [false])
	ui_config[category_type][tool_name]["search_entry"].connect("focus_entered",self,"on_search_entry_changed_focus", [true])


# Make a search ui for used objects tab taking over the current version
func make_search_ui_used_paths():

	var category_type = "Paths"
	var tool_name = "Main"
	var hbox = Global.Editor.PathLibraryPanel.find_node("Search")

	# Set up the base parameters
	ui_config[category_type] = {}
	ui_config[category_type][tool_name] = {}
	ui_config[category_type][tool_name]["grid_menu"] = Global.Editor.PathLibraryPanel.PathMenu

	# Configure the clear button with its icon & tooltip
	var list_used_button = Button.new()
	list_used_button.icon = load_image_texture("res://ui/icons/tools/map_settings.png")
	list_used_button.hint_tooltip = "Search for paths already used on this map."
	# Listen for the pressed signal
	#func on_used_assets_button_pressed(category_type: String, tool_name: String, source_category: String):
	list_used_button.connect("pressed",self,"on_used_assets_button_pressed",[category_type,tool_name,category_type])
	
	hbox.add_child(list_used_button)
	hbox.move_child(list_used_button,2)

# Make a search ui for used objects tab taking over the current version
func make_search_ui_used_objects():

	var category_type = "Objects"
	var tool_name = "Main"
	var vbox = Global.Editor.ObjectLibraryPanel.find_node("VAlign")
	var icon_texture = load_image_texture("ui/trash_icon.png")
	var label = Label.new()
	var sort_type_buttons = []

	# Set up the base parameters
	ui_config[category_type] = {}
	ui_config[category_type][tool_name] = {}
	ui_config[category_type][tool_name]["hbox"] = HBoxContainer.new()
	ui_config[category_type][tool_name]["grid_menu"] = Global.Editor.ObjectLibraryPanel.objectMenu
	ui_config[category_type][tool_name]["sort_type"] = 0

	vbox.add_child(ui_config[category_type][tool_name]["hbox"])
	vbox.move_child(ui_config[category_type][tool_name]["hbox"],3)

	# Create search entry reference
	ui_config[category_type][tool_name]["search_entry"] = LineEdit.new()
	ui_config[category_type][tool_name]["search_entry_last_value"] = ""
	
	# Configure the clear button with its icon & tooltip
	var clear_button = Button.new()
	clear_button.icon = icon_texture
	clear_button.hint_tooltip = "Clear Search"
	# Listen for the pressed signal
	clear_button.connect("pressed",self,"on_clear_button_pressed",[category_type,tool_name])

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

	ui_config[category_type][tool_name]["sort_type_buttons"] = sort_type_buttons

	# Add the elements into the hbox
	label.text = "Search"
	ui_config[category_type][tool_name]["hbox"].add_child(label)
	ui_config[category_type][tool_name]["hbox"].add_child(ui_config[category_type][tool_name]["search_entry"])
	for _i in 4:
		ui_config[category_type][tool_name]["hbox"].add_child(ui_config[category_type][tool_name]["sort_type_buttons"][_i])
	
	ui_config[category_type][tool_name]["hbox"].add_child(clear_button)
	ui_config[category_type][tool_name]["search_entry"].size_flags_horizontal = 3
	# Listen for the text being entered and do the search
	ui_config[category_type][tool_name]["search_entry"].connect("text_entered",self,"on_new_search_text",[category_type,tool_name,"text_entered"])
	ui_config[category_type][tool_name]["search_entry"].connect("text_changed",self,"on_new_search_text",[category_type,tool_name,"text_changed"])
	ui_config[category_type][tool_name]["search_entry"].connect("focus_exited",self,"on_search_entry_changed_focus", [false])
	ui_config[category_type][tool_name]["search_entry"].connect("focus_entered",self,"on_search_entry_changed_focus", [true])

	# Listen to the toggles on all, used and tags buttons in order to show the search bar or not
	Global.Editor.ObjectLibraryPanel.allButton.connect("toggled", self, "on_object_filter_button_toggled")
	Global.Editor.ObjectLibraryPanel.usedButton.connect("toggled", self, "on_object_filter_button_toggled")
	Global.Editor.ObjectLibraryPanel.tagsButton.connect("toggled", self, "on_object_filter_button_toggled")
	on_object_filter_button_toggled(true)


#########################################################################################################
##
## SEARCH HISTORY FUNCTIONS
##
#########################################################################################################

# Function to make a search history capability for Object Library Panel
func make_search_history_for_tool_ui(category_type: String, tool_name: String):

	outputlog("make_search_history_for_tool_ui: category_type" + str(category_type) + " tool_name: " + str(tool_name))

	var search_hbox = null
	var search_lineedit = null

	# Finf the search hbox containers
	match category_type:
		"Objects":
			search_hbox = Global.Editor.ObjectLibraryPanel.filters.find_node("Search")
		"Paths":
			search_hbox = Global.Editor.PathLibraryPanel.filters.find_node("Search")
		_:
			return

	# Find the nodes for the in built search box and line edit
	if search_hbox == null:
		return
	# Look for the search line edit
	search_lineedit = search_hbox.find_node("SearchLineEdit")
	ui_config[category_type][tool_name]["dd_search_entry"] = search_lineedit

	if search_hbox != null && search_lineedit != null:
		make_search_history_ui(category_type, tool_name, search_hbox, search_lineedit)

# Function to make a search history capability for Object Library Panel
func make_search_history_ui(category_type: String, tool_name: String, search_hbox: HBoxContainer, search_lineedit: LineEdit):

	outputlog("make_search_history_ui")

	# Make a new menu button and add it to the search hbox
	var menubutton = MenuButton.new()
	search_hbox.add_child(menubutton)
	search_hbox.move_child(menubutton,1)

	menubutton.icon = load_image_texture("ui/history-icon.png")
	menubutton.hint_tooltip = "Select from a list of previous searche."

	# Connect to the signal when a text has been entered
	search_lineedit.connect("text_entered", self, "on_store_new_search_history_item",[menubutton])

	# Connect to the id pressed signal to respond when the search history item has been selected.
	menubutton.get_popup().connect("id_pressed", self, "on_search_history_item_selected", [category_type, tool_name, menubutton, search_lineedit])

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
	if history_popup.get_item_count() > MAX_HISTORY_SEARCH_TERMS + 1:
		history_popup.remove_item(history_popup.get_item_count()-1)


# Function to respond when a search history is selected
func on_search_history_item_selected(id: int, category_type: String, tool_name: String, search_button: MenuButton, search_lineedit: LineEdit):

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
## REGISTER ACTIONS FUNCTION
##
#########################################################################################################

# Function to register an action for left mouse click
func register_right_mouse_click_action():

	var event = InputEventMouseButton.new()

	event.pressed = true
	event.button_index = BUTTON_RIGHT #Right mouse button

	if not InputMap.has_action("right_mouse_click"):
		InputMap.add_action("right_mouse_click",0.5)
		InputMap.action_add_event("right_mouse_click", event)

#########################################################################################################
##
## INPUT CAPTURE FUNCTIONS
##
#########################################################################################################

# Function to respond to unhandled mouse events
func on_unhandled_mouse_event(event):

	outputlog("on_unhandled_mouse_event",4)


# Function to respond to unhandled key events
func on_unhandled_key_event(event):

	outputlog("on_unhandled_key_event",4)

# Function to set up the 
func set_up_input_capture():
	var unhandledeventemitter = UnhandledEventEmitter.new()
	unhandledeventemitter.global = Global
	Global.World.add_child(unhandledeventemitter)
	unhandledeventemitter.connect("key_input", self, "on_unhandled_key_event")
	unhandledeventemitter.connect("mouse_input", self, "on_unhandled_mouse_event")

# Class to emit unhandled events
class UnhandledEventEmitter extends Node:

	var global = null

	signal key_input
	signal mouse_input

	func _unhandled_input(event):

		if not global.Editor.SearchHasFocus:
			var focus = global.Editor.GetFocus()
			if focus == null || (not focus is LineEdit && not focus is Tree):
				if event is InputEventKey:
					self.emit_signal("key_input", event)
	
	func _input(event):

		if not global.Editor.SearchHasFocus:
			var focus = global.Editor.GetFocus()
			if focus == null || (not focus is LineEdit && not focus is Tree):
				if event is InputEventMouse:
					self.emit_signal("mouse_input", event)



#########################################################################################################
##
## UPDATE FUNCTION
##
#########################################################################################################


# On selection changed
func selection_changed():

	outputlog("selection_changed",2)

	if Global.Editor.Tools["SelectTool"].Selected.size() > 0:
		if get_node_type(Global.Editor.Tools["SelectTool"].Selected[0]) == "portals":
			outputlog("texture: " + str(Global.Editor.Tools["SelectTool"].Selected[0].Texture.resource_path),2)



# Function to check if the selection has changed
func has_selection_changed() -> bool:

	outputlog("has_selection_changed: " + str(Global.Editor.Tools["SelectTool"].Selected),4)

	# Check if it has changed from the stored version and update it if it has changed
	if not is_the_same(store_last_valid_selection, Global.Editor.Tools["SelectTool"].Selected):
		store_last_valid_selection = Global.Editor.Tools["SelectTool"].Selected
		return true
	else:
		return false

func update(_delta):

	# A new node has been added since we last checked
	if Global.Editor.ActiveToolName == "SelectTool":
		# If the selection has changed then call the selection changed function
		if has_selection_changed():
			selection_changed()


#########################################################################################################
##
## START FUNCTION
##
#########################################################################################################


# Main Script
func start() -> void:

	outputlog("AdditionalSearchOptions Mod Has been loaded.")

	# Ridiculous work around to stop button signals throwing errors
	var category = "Effects"
	var id = "AdditionalSearchOptions"
	var name = "Search Tool"
	var icon = "res://ui/icons/tools/material_brush.png"
	invisible_tool_panel = Global.Editor.Toolset.CreateModTool(self, category, id, name, icon)
	invisible_tool_panel.CreateNote("This menu does not do anything but is required for search to work in other tools.")
	hide_mod_tool(category, name)

	# If _Lib is installed then register with it
	if Engine.has_signal("_lib_register_mod"):
		
		# Register this mod with _lib
		Engine.emit_signal("_lib_register_mod", self)

		# Create a config builder to ensure we can store the keys if changed in preferences
		var _lib_config_builder = Global.API.ModConfigApi.create_config()
		_lib_config_builder\
			.check_button("search_on_text_changed", true, "Enable search on any text changed without requiring carriage return.")\
			.check_button("refresh_grid_colours", false, "Refresh the wall and pattern colours in the grid when searching.")
		_lib_mod_config = _lib_config_builder.build()
	
	# Set references to the Select Tool for later use
	select_tool_panel = Global.Editor.Toolset.GetToolPanel("SelectTool")

	# Get the reference to pattern tool panel
	pattern_tool_panel = Global.Editor.Toolset.GetToolPanel("PatternShapeTool")

	# Get the reference to wall tool panel
	wall_tool_panel = Global.Editor.Toolset.GetToolPanel("WallTool")

	# Get the reference to terrain tool panel
	terrain_tool_panel = Global.Editor.Toolset.GetToolPanel("TerrainBrush")

	# Get the reference to light tool panel
	light_tool_panel = Global.Editor.Toolset.GetToolPanel("LightTool")

	# Get the reference to roof tool panel
	roof_tool_panel = Global.Editor.Toolset.GetToolPanel("RoofTool")

	# Get the reference to portal tool panel
	portal_tool_panel = Global.Editor.Toolset.GetToolPanel("PortalTool")

	# Make the UI elements for the search capability
	make_search_ui(pattern_tool_panel, "Patterns", "Main")
	make_search_ui(select_tool_panel, "Patterns", "Select")
	make_search_ui(wall_tool_panel, "Walls", "Main")
	make_search_ui(select_tool_panel, "Walls", "Select")
	make_search_ui(terrain_tool_panel, "Terrain", "Main")
	make_search_ui(light_tool_panel, "Lights", "Main")
	make_search_ui(select_tool_panel, "Lights", "Select")
	make_search_ui(roof_tool_panel, "Roofs", "Main")
	make_search_ui(portal_tool_panel, "Portals", "Main")

	make_search_ui_used_objects()
	make_search_ui_used_paths()

	# Check for the launch of the Object or Scatter Tool and refresh the Used
	for tool_type in ["ObjectTool","ScatterTool"]:
		Global.Editor.Toolset.ToolPanels[tool_type].connect("visibility_changed",self, "on_toolpanel_visibility_changed",[tool_type])

	make_search_history_for_tool_ui("Objects", "Main")
	make_search_history_for_tool_ui("Paths", "Main")

	












	