/**
 * =============================================================================
 * SourceMod PsychoStats Plugin
 * Implements support for PsychoStats and enhances game logging to provide more
 * statistics.
 *
 * This plugin will 'fix' the game logging so the first map to run on
 * server restart will log properly (HLDS doesn't log the first map). This
 * will prevent any 'unknown' maps from appearing in your player stats.
 *
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Version: $Id: ps_mapfix.sp 411 2008-04-23 18:07:12Z lifo $
 * Author:  Stormtrooper
 */

#pragma semicolon 1

#include <sourcemod>
#include <logging>
#include <sdktools>

new bool:fixed = false;

public Plugin:myinfo =
{
        name = "PsychoStats - First Map Fix",
        author = "Stormtrooper",
        description = "PsychoStats first map logging fix",
        version = "1.01"
};

public OnPluginStart()
{
        AddGameLogHook(LogMapEvent);
}

// write a "Started map" event in order to fix a problem with the HLDS logging.
// This will prevent an "unknown" map from appearing in your player stats.
public Action:LogMapEvent(const String:message[]) {
        // The "Log file started" message is not captured by sourcemod (I assume it's an engine event; not a mod event)
        // So I have to simply trigger on the very first message received,
        // which will be the first event AFTER "Log file started" (and is usually a player event; like 'player connected')

        // Note: we cannot remove this LogMapEvent hook because it causes server to crash.
        if(!fixed)
        {
                decl String:map[128];
                GetCurrentMap(map, sizeof(map));
                LogToGame("Started map \"%s\" (CRC \"-1\") (psychostats)", map);

                // Only record the first map, after that we're all good
                fixed = true;
        }
        return Plugin_Continue;
}
