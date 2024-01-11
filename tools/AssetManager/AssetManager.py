import os
from pathlib import PurePosixPath

from srctools.filesys import get_filesystem
from srctools.mdl import Model, SeqEvent, AnimEvents

import shutil

import re

import vdf
from vdf import VDFDict

def populate_from_folder( folder : str, output : set ):
	for root, dirs, files in os.walk(folder, topdown=True): 
		for name in files:
			output.add( os.path.join( root, name ).replace( "\\", "/" ) )

	with open( ".\\file_cache.txt", "w" ) as new_file:
		for file in output:
			new_file.write(f"{file}\n")

def check_asset( asset : str ):
	asset_combine : str = asset_directory + "/" + asset.replace("\\", "/")
	if asset_combine in asset_set:
		if ".mdl" in asset_combine:
			model_get_textures( asset_combine )
			model_get_dependencies( asset_combine )
		elif ".vmt" in asset_combine:
			parse_vmt( asset_combine )
		assets_used.add( asset_combine )

def check_asset_icon( asset : str ):
	if asset.endswith(".vtf"):
		asset_combine = asset_directory + "/materials/" + asset
		if asset_combine in asset_set:
			assets_used.add( asset_combine )

		asset_combine = asset_combine.replace( ".vtf", ".vmt" )
		if asset_combine in asset_set:
			assets_used.add( asset_combine )
			parse_vmt( asset_combine )

	else:
		asset_combine = asset_directory + "/materials/" + asset + "_large.vmt"
		if asset_combine in asset_set:
			assets_used.add( asset_combine )
			parse_vmt( asset_combine )

model_attribs : set = { "custom_lunchbox_throwable_model", "custom_hand_viewmodel",
			"custom_magazine_model", "custom_projectile_model" }

static_model_attribs : set = { "custom lunchbox throwable model", "custom hand viewmodel",
	"custom magazine model", "custom projectile model" }

def parse_item( item : VDFDict ):
	show_armory : str = item.get( "show_in_armory", "1" )
	if show_armory == "0":
		return
	
	for key, value in item.items():
		key = key.lower()
		if key == "attributes":
			parse_attributes( value )
		elif key == "visuals":
			parse_visuals( value )
		elif key == "static_attrs":
			parse_static_attrs( value )
		elif type(value) is str:
			if key in [ "model_world", "model_player", "extra_wearable" ]:
				check_asset( value )
			elif key in [ "mouse_pressed_sound", "drop_sound" ]:
				check_asset( "sound/" + value.removeprefix("#") )
			elif key in [ "image_inventory" ]:
				check_asset_icon( value )
			
def parse_attributes( attributes : VDFDict ):
	for key, value in attributes.items():
		if type(value) is str:
			continue
		if value.get("attribute_class", "").lower() in model_attribs:
			check_asset( value["value"] )

def parse_static_attrs( attributes : VDFDict ):
	for key, value in attributes.items():
		if key.lower() in static_model_attribs:
			check_asset( value )

def parse_visuals( visuals : VDFDict ):
	for key, value in visuals.items():
		if type(value) is str:
			soundscripts_used.add( value )

def model_get_dependencies( model_name : str ):
	for ext in [ ".phy", ".vvd", ".dx90.vtx", ".ani" ]:
		new_model_name = model_name.removesuffix(".mdl") + ext
		if new_model_name in asset_set:
			assets_used.add( new_model_name )

def model_get_textures( model_name : str ):
	local_model_name = model_name

	if model_name in asset_set:
		fsys = get_filesystem( asset_directory )
	else:
		print( "vmt from model not found in sets?", model_name )
		return

	try:
		model_file = fsys._get_file( local_model_name )
		model : Model = Model( fsys, model_file )

		for included in model.included_models:
			included_path : str = asset_directory + "/" + included.filename
			check_asset( included_path )

		for seq in model.sequences:
			for ev in seq.events:
				parse_sequence_events( ev )

		paths = {
		tex
		for texgroup in model.skins
		for tex in texgroup
		}

		for tex in paths:
			for folder in model.cdmaterials:
				full =  asset_directory + "/" + str(PurePosixPath('materials', folder, tex).with_suffix('.vmt'))
				if full in asset_set:
					assets_used.add( full )
					parse_vmt( full )
	except FileNotFoundError:
		print( "file not found:", model_name )
		return

sound_events : set = {	AnimEvents.CL_EVENT_SOUND, AnimEvents.AE_CL_PLAYSOUND, AnimEvents.EVENT_WEAPON_RELOAD_SOUND,
			AnimEvents.AE_SV_PLAYSOUND, AnimEvents.AE_WPN_PLAYWPNSOUND, AnimEvents.SCRIPT_EVENT_SOUND, 
			AnimEvents.SCRIPT_EVENT_SOUND_VOICE }

def parse_sequence_events( event : SeqEvent ):
	if event.type in sound_events:
		soundscripts_used.add( event.options )



#keys that point to textures
texturekeys : set = { "$basetexture", "$basetexture2",
		      "$detail", "$detail1", "$detail2",
		      "$bumpmap", "$bumpmap2", "$bumpmask",
		      "$phongexponenttexture", "$phongwarptexture", 
		      "$envmapmask", "$selfillummask", "$selfillumtexture",
		      "$lightwarptexture", "$ambientoccltexture", "$blendmodulatetexture" }

def parse_vmt( vmt_path : str ):
	qcfile : dict

	try:
		with open( vmt_path.removesuffix("\n"), "r" ) as vmt:
			qcfile = vdf.parse( vmt, dict, True, False )
		
		for tex in qcfile:
			for k, v in qcfile[tex].items():
				if k.lower() in texturekeys:
					newstr : str = asset_directory + "/materials/" + v.replace("\\", "/")
					if not newstr.endswith(".vtf"):
						newstr += ".vtf"
					if newstr in asset_set:
						assets_used.add(newstr.removesuffix("\n"))
	except FileNotFoundError:
		print(f"vmt {vmt_path} does not exist")

asset_directory : str = r"E:/TF2C Projects/Github/assets_server"
asset_set : set = set()
assets_used : set = set()

soundscripts_used : set = set()

#file cache contains a list of the contents of the asset directory to avoid reading it again
try:
	with open( ".\\file_cache.txt", "r" ) as new_file:
		asset_list : list = new_file.readlines()
		for i in asset_list:
			asset_set.add( i.removesuffix("\n") )
except FileNotFoundError:
	populate_from_folder( asset_directory, asset_set )


#extra files contains a list of assets that are used but won't be picked up by the tool (sourcemod plugins)
try:
	with open( ".\\extra_files.txt", "r" ) as new_file:
		contents : list = new_file.readlines()
		for item in contents:
			if item.startswith("//") or item == "\n":
				continue
			check_asset( item.removesuffix("\n") )
except FileNotFoundError:
	print("no extra files file")

item_schema_path : str = r"E:/TF2C Projects/Github/custom_items_game.txt"
#item_schema_path : str = r"E:/TF2C Projects/Github/tools/AssetManager/testschema.txt"
soundscripts_path : str = r"E:/TF2C Projects/Github/custom_level_sounds.txt"

item_schema : VDFDict
with open( item_schema_path, "r", encoding="utf8" ) as schema_read:
	item_schema = vdf.parse( schema_read, VDFDict, False, False )

for key, value in item_schema["custom_items_game"]["items"].items():
	parse_item( value )

soundscript_dict : VDFDict
try:
	with open( soundscripts_path, "r", encoding="utf8" ) as soundscript_read:
		soundscript_dict = vdf.parse( soundscript_read, VDFDict, False, False )
except FileNotFoundError:
	print("no soundscript file")

for script in soundscripts_used:
	sounddefs = soundscript_dict.get( script, 0 )
	if sounddefs:
		key = sounddefs.get( "wave", 0 )
		if key:
			newstr : str = re.sub('[*#$)]', '', key)
			newstr = asset_directory + "/sound/" + newstr.replace("\\", "/")
			if newstr in asset_set:
				assets_used.add( newstr )
			continue
		key = sounddefs.get( "rndwave", 0 )
		if key and type(key) is vdf.vdict.VDFDict:
			for k, v in key.items():
				newstr : str = re.sub('[*#$)]', '', v)
				newstr = asset_directory + "/sound/" + newstr.replace("\\", "/")
				if newstr in asset_set:
					assets_used.add( newstr )

try:
	with open( ".\\classic_files.txt", "r" ) as new_file:
		classic_items : list = new_file.readlines()
		for item in classic_items:
			item = asset_directory + "/" + item.removesuffix("\n")
			if item in assets_used:
				assets_used.remove( item )
except FileNotFoundError:
	print("no classic file")

print(  f"total: {len(asset_set)}, in use: {len(assets_used)}, unused: {len(asset_set - assets_used)}, goal: {len(asset_set) - len(assets_used)}"  )

for fck in assets_used:
	if fck not in asset_set:
		print("fck", fck)

outputlist : list = list()
for line in asset_set:
	if line not in assets_used:
		outputlist.append(f"{line}\n")
outputlist.sort()
with open( ".\\output.txt", "w" ) as new_file:
	for line2 in outputlist:
		new_file.write( line2 )

copy = False
if copy:
	for copy in asset_set:
		if copy in assets_used:
			dest : str =os.getcwd().replace("\\", "/") + f"/output{copy.removeprefix( asset_directory )}"
			try:
				shutil.copy2( copy, dest )
			except FileNotFoundError:
				os.makedirs( os.path.dirname( dest ) )
				shutil.copy2( copy, dest )