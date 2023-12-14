import os

import vdf
from vdf import VDFDict

import shutil

import io
import subprocess

import re

import bsp_tool
from bsp_tool.branches.valve.source import PakFile

from zipfile import ZipFile

from srctools.filesys import get_filesystem

from srctools.mdl import Model
from srctools.particles import Particle

from itertools import chain

from pathlib import PurePosixPath

from typing import Dict

def populate_from_folder( folder : str, output : set ):
	for root, dirs, files in os.walk(folder, topdown=True): 
		for name in files:
			if name.endswith(".pcf"):
				parse_pcf( os.path.join( root, name ).replace( "/", "\\" ) )

			#todo: do soundscript parsing here?

			output.add( virtualize( os.path.join( root, name ), folder ).lower() )


def virtualize( path : str, root : str ) -> str:
	return path.replace( root + "\\", "" )

def path_fix( path : str, suffix : str, prefix : str ):
	new_path = path
	if not new_path.startswith( prefix ):
		new_path = prefix + new_path
	if not new_path.endswith( suffix ):
		new_path = new_path + suffix

	new_path = new_path.replace( "/", "\\" ).lower()

	return new_path
	

def check_present( input : set ):
	temp : set = set()
	for i in input:
		if i in chain( classic_files, pakfile_files ):
			#print("in zip:", i )
			temp.add(i)
		elif i in live_files:
			#print("in live:", i )
			temp.add(i)
			retrieve.add(i)
		else:
			print("not found in sets:", i)

	input -= temp


def model_get_textures( model_name : str ):
	#print("get from model", model_name)
	model_name = model_name.strip().lower()

	if model_name in pakfile_files:
		fsys = get_filesystem( ".\\unzip" )
	elif model_name in classic_files:
		fsys = get_filesystem( ".\\classic" )
	elif model_name in live_files:
		fsys = get_filesystem( ".\\live" )
	else:
		print( "vmt from model not found in sets?", model_name )
		return

	try:
		model_file = fsys._get_file( model_name )
		model = Model( fsys, model_file )

		paths = {
		tex
		for texgroup in model.skins
		for tex in texgroup
		}

		for tex in paths:
			for folder in model.cdmaterials:
				full = str(PurePosixPath('materials', folder, tex).with_suffix('.vmt')).replace( "/", "\\" )
				if full.lower() in chain(pakfile_files,classic_files,live_files):
					tex_vmt_dependencies.add(full.lower())
	except FileNotFoundError:
		print( "file not found:", model_name )
		return

#keys that point to textures
texturekeys : set = { "$basetexture", "$basetexture2",
		      "$detail", "$detail1", "$detail2",
		      "$bumpmap", "$bumpmap2", "$bumpmask",
		      "$phongexponenttexture", "$phongwarptexture", 
		      "$envmapmask", "$selfillummask", "$selfillumtexture",
		      "$lightwarptexture", "$ambientoccltexture", "$blendmodulatetexture" }

def parse_vmt( vmt_path : str ):
	if vmt_path.startswith("*"):
		return

	new_path = vmt_path.replace( "/", "\\" )
	#print( "getting vtfs from:", new_path )

	if new_path in pakfile_files:
		new_path = ".\\unzip\\" + new_path
	elif new_path in classic_files:
		new_path = ".\\classic\\" + new_path
	elif new_path in live_files:
		new_path = ".\\live\\" + new_path
	else:
		print( "vmt for vtf not found?", new_path )
		print("---------------------------")
		return

	qcfile : dict
	with open( new_path, "r" ) as vmt:
		qcfile = vdf.parse( vmt, dict, True, False )
	
	for tex in qcfile:
		for k, v in qcfile[tex].items():
			if k.lower() in texturekeys:
				tex_vtf_dependencies.add( path_fix( v, ".vtf", "materials\\" ) )

propentities : set = { "prop_static", "prop_dynamic", "prop_physics", "prop_detail",
		       "prop_ragdoll", "prop_dynamic_override", "prop_physics_override",
		       "prop_physics_override" }

#are these needed?
soundscape_entities : set = { "env_soundscape", "env_soundscape_triggerable" }

#entity inputs that play specific sounds
sound_inputs : set = { "PlayVO", "PlayVORed", "PlayVOBlue" }

def parse_entity( entity : dict ):
	classname = entity["classname"]
	for k, v in entity.items():
		if type(v) is list:
			parse_outputs( v )

	if classname == "ambient_generic":
		message = entity.get( "message", "" )
		if message != "":
			parse_sound( message )
	elif classname in propentities:
		model_name = entity.get( "model", "" )
		if model_name != "" and not model_name.startswith("*"):
			model_name = model_name.replace("/", "\\")
			models_dependencies.add( path_fix( model_name, ".mdl", "models\\" ) )
	elif classname == "info_particle_system":
		effect = entity.get( "effect_name", "" )
		if effect != "":
			particle_dependencies.add(effect)



	#print("---------------------------")

def parse_outputs( output_list : list ):
	for i in output_list:
		new_output : list = i.replace( "\x1b", "," ).split(",")
		if len( new_output ) != 5:
			print( "invalid output size", len( new_output ), new_output )
			continue

		if new_output[1] in sound_inputs:
			parse_sound( new_output[2] )


def parse_sound( sound : str ):
	if sound.endswith( ".wav" ) or sound.endswith( ".mp3" ):
		#print( "sound\\" + sound.replace( "/", "\\" ) )
		sound_dependencies.add( "sound\\" + sound.replace( "/", "\\" ) )
	else:
		soundscript_dependencies.add( sound )

def populate_soundscripts( input : set, output : Dict, folder : str ):
	scriptfiles : set = set()
	for i in input:
		new_path = os.path.basename(i)
		if "phonemes" not in new_path:
			if new_path.endswith("_level_sounds.txt"):
				scriptfiles.add(i)
			elif new_path.startswith("game_sounds"):
				scriptfiles.add(i)

	for i in scriptfiles:
		kvfile : VDFDict
		with open( folder + i, "r" ) as script:
			kvfile = vdf.parse( script, VDFDict, False, False )

			for j in kvfile:
				pushset = set()
				if "wave" in kvfile[j]:
					newstr = re.sub('[*#$)]', '', kvfile[j]["wave"])
					pushset.add( newstr.replace( "\\\\", "\\" ) )

					output[j] = [ folder + i, pushset ]
				elif "rndwave" in kvfile[j]:
					for k, v in kvfile[j]["rndwave"].items():
						newstr = re.sub('[*#$)]', '', v)
						pushset.add( newstr.replace( "\\\\", "\\" ) )

					output[j] = [ folder + i, pushset ]

def check_present_soundscript( scripts : dict ):
	for key, value in scripts.items():
		if key in soundscript_dependencies:
			for sound in value[1]:
				if sound.endswith(".mp3") or sound.endswith(".wav"):
					sound_dependencies.add( path_fix( sound, "", "sound\\" ).lower() )
				else:
					pathstr : str = path_fix( sound, ".wav", "sound\\" ).lower()
					if pathstr in chain( pakfile_files, classic_files, live_files ):
						sound_dependencies.add( pathstr )
					else:
						pathstr = path_fix( sound, ".mp3", "sound\\" ).lower()
						if pathstr in chain( pakfile_files, classic_files, live_files ):
							sound_dependencies.add( pathstr )
						else:
							print("unable to resolve sound dependency:", sound )

			if key in soundscript_keys_unpack.keys():
				#print("in zip:", key )
				soundscript_dependencies.discard(key)
			elif key in soundscript_keys_classic.keys():
				#print("in classic:", key )
				soundscript_dependencies.discard(key)
			elif key in soundscript_keys_live.keys():
				#print("in live:", key )
				soundscript_dependencies.discard(key)
				soundscript_retrieve[key] = value[0]
			else:
				print("not found in soundscript sets:", key)

def handle_level_sounds( mapstr : str ):
	kvfile : VDFDict
	try:
		with open( ".\\unzip\\maps\\" + mapstr + "_level_sounds.txt", "r" ) as levelsounds_existing:
			kvfile = vdf.parse( levelsounds_existing, VDFDict, False, False )

			for key, value in soundscript_retrieve.items():
				#todo: sanity checks for sounds with no extension
				add_key_to_script( kvfile, key, value )

		with open( ".\\unzip\\maps\\" + mapstr + "_level_sounds.txt", "w" ) as levelsounds_existing:
			vdf.dump( kvfile, levelsounds_existing, True, False )

	except FileNotFoundError:
		print("no level sounds exists")
		with open( ".\\unzip\\maps\\" + mapstr + "_level_sounds.txt", "w" ) as levelsounds_existing:
			kvfile = VDFDict()
			for key, value in soundscript_retrieve.items():
				#todo: sanity checks for sounds with no extension
				add_key_to_script( kvfile, key, value )

			vdf.dump( kvfile, levelsounds_existing, True, False )

def add_key_to_script( inputscript : VDFDict, soundscript_name : str, filepath : str ):
	kvfile : VDFDict
	with open( filepath, "r" ) as script:
		kvfile = vdf.parse( script, VDFDict, False, False )
		inputscript.update( { soundscript_name:kvfile[soundscript_name] } )


def parse_pcf( path : str ):
	pushset : set = set()
	with open( path, "rb" ) as file:
		particle = Particle.parse( file, 2 )
		for i in particle:
			pushset.add(i)

		if path.startswith( ".\\unzip" ):
			particle_keys_unpack[os.path.basename(path)] = pushset
		elif path.startswith( ".\\classic" ):
			particle_keys_classic[os.path.basename(path)] = pushset
		elif path.startswith( ".\\live" ):
			particle_keys_live[os.path.basename(path)] = pushset


def check_present_particles( particles : Dict, should_retrieve : bool, dependency : set ):
	removelist : set = set()
	for k, v in particles.items():
		for effect in v:
			if effect in dependency:
				if should_retrieve == True:
					newname = "particles\\" + k
					retrieve.add( newname )
					particle_retrieve.add( newname )

				removelist.add( effect )

	dependency -= removelist

def handle_level_particles( mapstr : str ):
	kvfile : VDFDict
	with open( ".\\unzip\\maps\\" + mapstr + "_particles.txt", "r" ) as script:
		kvfile = vdf.parse( script, VDFDict, False, False )
		try:
			for i in particle_retrieve:
				kvfile["particles_manifest"].update( { "file":i.replace("\\", "/") } )
		except:
			print("bad")

	with open( ".\\unzip\\maps\\" + mapstr + "_particles.txt", "w" ) as script:
		vdf.dump( kvfile, script, True, False )

def parse_map( filepath : str ):
	map_filepath : str = filepath
	map_filename : str = os.path.basename( filepath )
	map_name : str = map_filename.removesuffix( ".bsp" )
	map_newname : str = map_name + "_tf2c"


	subprocess.run( [ bspzip_path, "-repack", map_filepath ] )

	map = bsp_tool.load_bsp( map_filename )

	if os.path.isdir( ".\\unzip" ):
		shutil.rmtree( ".\\unzip" )

	print("Extracting pakfile")
	pakfile = map.PAKFILE
	pakfile.extractall( ".\\unzip" )

	print( "Scanning content" )
	populate_from_folder( ".\\unzip", pakfile_files )

	print("Gathering dependencies")
	for retrieve_item in map.ENTITIES:
		if "classname" in retrieve_item:
			parse_entity( retrieve_item )
		else:
			print("entity with no classname?", retrieve_item)

	for texture in map.TEXTURE_DATA_STRING_DATA:
		tex_vmt_dependencies.add( path_fix( texture, ".vmt", "materials/" ) )

	#clear lists of present files
	for model in models_dependencies:
		model_get_textures( model )

	for vmt in tex_vmt_dependencies:
		parse_vmt( vmt )

	check_present( models_dependencies )

	check_present_particles( particle_keys_unpack, False, particle_dependencies )
	check_present_particles( particle_keys_classic, False, particle_dependencies )
	check_present_particles( particle_keys_live, True, particle_dependencies )

	check_present( tex_vmt_dependencies )

	check_present( tex_vtf_dependencies )

	populate_soundscripts( pakfile_files, soundscript_keys_unpack, ".\\unzip\\" )

	check_present_soundscript( soundscript_keys_unpack )
	check_present_soundscript( soundscript_keys_classic )
	check_present_soundscript( soundscript_keys_live )

	check_present( sound_dependencies )

	handle_level_sounds( map_name )
	handle_level_particles( map_name )

	filelist : str = os.path.abspath( ".\\addlist.txt" )
	mappath_output : str = os.path.abspath( ".\\" + map_newname + ".bsp" )

	copylist : set = set()

	try:
		for folder_name, sub_folders, file_names in os.walk( ".\\unzip\\maps" ):
			for file in file_names:
				if map_name in file and file.endswith(".txt"):
					copylist.add( os.path.join( folder_name, file ) )
					#os.rename( os.path.join( folder_name, file ), os.path.join( folder_name, file.replace( mapstr, newmapstr ) ) )

		for folder_name, sub_folders, file_names in os.walk( ".\\unzip\\materials\\maps" ):
			if folder_name == ".\\unzip\\materials\\maps\\" + map_name:
				for retrieve_item in file_names:
					if retrieve_item.endswith(".vtf"):
						copylist.add( os.path.join( folder_name, retrieve_item ) )

		for folder_name, sub_folders, file_names in os.walk( ".\\unzip\\scripts" ):
			for retrieve_item in file_names:
				if retrieve_item.startswith("soundscapes") and retrieve_item.endswith(".txt"):
					copylist.add( os.path.join( folder_name, retrieve_item ) )
	except FileNotFoundError:
		print("file not found")

	extlist : set = set( { "vvd", "dx90.vtx", "phy" } )

	retrieve_extend : set = set()

	#grab other model files (vtx, phy, etc)
	for retrieve_item in retrieve:
		if retrieve_item.endswith( ".mdl" ):
			foldername = os.path.abspath( ".\\live\\" + os.path.dirname( retrieve_item ) )
			modellist = [ f for f in os.listdir(foldername) if os.path.isfile( os.path.join( foldername, f ) ) ]
			split = os.path.splitext( os.path.basename(retrieve_item) )
			for j in modellist:
				split2 = j.split( ".", 1 )
				if split2[0] == split[0] and split2[1] in extlist:
					retrieve_extend.add( os.path.join( os.path.dirname( retrieve_item ) + "\\" + j ) )

	retrieve.update( retrieve_extend )

	sortlist : list = list()

	print("files to retrieve --------------------")
	for retrieve_item in retrieve:
		sortlist.append(retrieve_item)

	sortlist.sort()
	for retrieve_item in sortlist:
		print(retrieve_item)

	with open( "addlist.txt", "w" ) as addlist:
		for file in retrieve:
			addlist.write( file + "\n" )
			addlist.write( os.path.abspath( ".\\live\\" + file + "\n" ) )
			
		for file2 in copylist:
			addlist.write( file2.replace( map_name, map_newname ).removeprefix(".\\unzip\\") + "\n" )
			addlist.write( os.path.abspath( file2 ) + "\n" )

	subprocess.run( [ bspzip_path, "-addorupdatelist", map_filepath, filelist, mappath_output ] )

classic_files : set = set()
live_files : set = set()
pakfile_files : set = set()

models_dependencies :		set = set()	#models
tex_vmt_dependencies :		set = set()	#vmt files
tex_vtf_dependencies :		set = set()	#vtf files
sound_dependencies : 		set = set()	#raw wav/mp3 files
soundscript_dependencies :	set = set()	#soundscript entries
particle_dependencies :		set = set()	#particles

soundscript_keys_classic : Dict = {}
soundscript_keys_live : Dict = {}
soundscript_keys_unpack : Dict = {}

particle_keys_live : Dict = {}
particle_keys_classic : Dict = {}
particle_keys_unpack : Dict = {}

retrieve : set = set()
particle_retrieve : set = set()
soundscript_retrieve : dict = dict()

bsplist : list = list()
for file in os.listdir( ".\\bsp" ):
	filepath : str = os.path.join( ".\\bsp", file )
	if os.path.isfile( filepath ):
		bsplist.append( filepath )

populate_from_folder( ".\\classic", classic_files )
populate_from_folder( ".\\live", live_files )

populate_soundscripts( classic_files, soundscript_keys_classic, ".\\classic\\" )
populate_soundscripts( live_files, soundscript_keys_live, ".\\live\\" )

fsys = get_filesystem(".")

#G:\SteamLibrary\steamapps\common\Team Fortress 2\bin\bspzip.exe
bspzip_path : str = input( "Enter the full path of BSPZIP.exe: " )

for i in bsplist:
	for j in [ pakfile_files, models_dependencies, tex_vmt_dependencies, tex_vtf_dependencies, sound_dependencies, particle_dependencies, retrieve, particle_retrieve ]:
		j.clear()

	for j in [ soundscript_keys_unpack, particle_keys_unpack, soundscript_retrieve ]:
		j.clear()

	parse_map( i )

"""
print("moving files to temp --------------------")
#currently unused because bsp_tool seems to be unable to export static props correctly
for file in retrieve:
	print( "copying:", file )
	try:
		os.makedirs( os.path.dirname( os.path.abspath( ".\\unzip\\" + file ) ), exist_ok=True )
		shutil.copy2( os.path.abspath( ".\\live\\" + file ), os.path.abspath( ".\\unzip\\" + file ) )
	except FileNotFoundError as f:
		print("fail", file, f)


for folder_name, sub_folders, file_names in os.walk( ".\\unzip" ):
	if folder_name.endswith( mapstr ):
		os.rename( folder_name, folder_name.replace( mapstr, newmapstr ) )
		print("renamed", folder_name)

for folder_name, sub_folders, file_names in os.walk( ".\\unzip" ):
	for file in file_names:
		if file.endswith(".vmt"):
			print(file)
			newstr : str = ""
			with open( os.path.join( folder_name, file ), "r+" ) as material:
				newstr = material.read(-1).replace( mapstr, newmapstr )
				material.seek(0)
				material.truncate()
				material.write( newstr )


print("zipping temp folder --------------------")
with ZipFile( "testzip.zip", 'w' ) as zip_object:
	for folder_name, sub_folders, file_names in os.walk( ".\\unzip" ):
		for filename in file_names:
			zip_object.write( os.path.join( folder_name, filename ), os.path.join( folder_name.removeprefix(".\\unzip\\"), filename ) )

print("packing zipfile --------------------")
with open( "testzip.zip", "rb" ) as zip_object:
	map.PAKFILE = PakFile( io.BytesIO( zip_object.read() ) )
	
print("exporting bsp --------------------")
map.save_as( mapstr + ".bsp" )
"""

"""TODO:
	check particles for missing materials
	check for vmts that include other vmts

	pip install --upgrade https://github.com/snake-biscuits/bsp_tool/tarball/master
"""