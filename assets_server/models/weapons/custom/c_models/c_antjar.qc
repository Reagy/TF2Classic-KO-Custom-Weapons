$modelname "player/items/sniper/0x00c373a8/c_antjar/c_antjar.mdl"
$model "antjar" "jar_final.smd"
$cdmaterials "models/player/items/sniper/0x00c373a8/c_antjar/"
$cdmaterials ""
$hboxset "default"
$hbox 0 "weapon_bone" -0.308  -2.622  -2.722  9.350  2.821  2.722
// Model uses material "models/player/items/sniper/0x00c373a8/c_antjar/c_antjar.vmt"
// Model uses material "models/player/items/sniper/0x00c373a8/c_antjar/c_antjar_glass.vmt"
// Model uses material "models/player/items/sniper/0x00c373a8/c_antjar/c_antjar_ants.vmt"

$surfaceprop "default"
$illumposition -0.028 0.000 1.604
$sequence idle "idle" fps 30.00
$collisionmodel "jar_final.smd" {

	$mass 5.0
	$inertia 1.00
	$damping 0.00
	$rotdamping 0.00
}

$lod 6
{
	replacemodel "jar_final.smd" "jar_final_lod1.smd"
}
 
$lod 12
{
	replacemodel "jar_final.smd" "jar_final_lod2.smd"
}
 
$lod 18
{
	replacemodel "jar_final.smd" "jar_final_lod3.smd"
}