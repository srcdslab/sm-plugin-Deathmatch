#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <clientprefs>

#define PLUGIN_VERSION "1.0.0"
#define CHAT_PREFIX "\x04[DM]\x01 "

// Spawn points closer than this to an admin are the ones sm_dm_spawn_remove deletes
#define SPAWN_REMOVE_RADIUS 128.0
// Enemies further than this are ignored by the visibility check (cost and fog)
#define SPAWN_VISIBILITY_RANGE 3000.0

enum struct SpawnPoint
{
	float origin[3];
	float angles[3];
}

enum WeaponMenuChoice
{
	Choice_Menu = 0,	// show the menu on each spawn
	Choice_Always		// give the saved weapons on each spawn without asking
}

// CS:S weapons a player can pick, with the name shown in the menu
static const char g_sWeaponNames[][][] =
{
	{ "ak47", "AK-47" },
	{ "m4a1", "M4A1" },
	{ "awp", "AWP" },
	{ "famas", "FAMAS" },
	{ "galil", "Galil" },
	{ "aug", "AUG" },
	{ "sg552", "SG 552" },
	{ "scout", "Scout" },
	{ "sg550", "SG 550" },
	{ "g3sg1", "G3SG1" },
	{ "m3", "M3" },
	{ "xm1014", "XM1014" },
	{ "mp5navy", "MP5" },
	{ "p90", "P90" },
	{ "ump45", "UMP45" },
	{ "mac10", "MAC-10" },
	{ "tmp", "TMP" },
	{ "m249", "M249" },
	{ "deagle", "Desert Eagle" },
	{ "usp", "USP" },
	{ "glock", "Glock" },
	{ "p228", "P228" },
	{ "fiveseven", "Five-SeveN" },
	{ "elite", "Dual Elites" }
};

ConVar g_cvEnable;
ConVar g_cvRespawnTime;
ConVar g_cvSpawnProtection;
ConVar g_cvRandomSpawns;
ConVar g_cvSpawnMinDistance;
ConVar g_cvSpawnVisibility;
ConVar g_cvPrimaries;
ConVar g_cvSecondaries;
ConVar g_cvAwpLimit;
ConVar g_cvArmor;
ConVar g_cvHelmet;
ConVar g_cvHEGrenades;
ConVar g_cvFlashbangs;
ConVar g_cvSmokes;
ConVar g_cvMenuTime;
ConVar g_cvDroppedLifetime;
ConVar g_cvHpOnKill;
ConVar g_cvHpOnHeadshot;
ConVar g_cvMaxHp;
ConVar g_cvRemoveObjectives;
ConVar g_cvMapTimer;
ConVar g_cvChatTime;

ArrayList g_aSpawns;
ArrayList g_aPrimaries;
ArrayList g_aSecondaries;

Cookie g_ckPrimary;
Cookie g_ckSecondary;
Cookie g_ckMode;

char g_sMap[PLATFORM_MAX_PATH];
bool g_bMapEnding;
int g_iBeamSprite = -1;
int g_iHaloSprite = -1;

Handle g_hRespawnTimer[MAXPLAYERS + 1];
char g_sPrimary[MAXPLAYERS + 1][32];
char g_sSecondary[MAXPLAYERS + 1][32];
WeaponMenuChoice g_eMode[MAXPLAYERS + 1];
float g_fSpawnTime[MAXPLAYERS + 1];
float g_fProtectedUntil[MAXPLAYERS + 1];
bool g_bProtectionVisual[MAXPLAYERS + 1];
int g_iSavedAlpha[MAXPLAYERS + 1];
float g_fSpawnUsed[1024];

public Plugin myinfo =
{
	name = "Deathmatch",
	author = ".Rushaway",
	description = "Team deathmatch for CS:S: respawn, random spawns, weapon menu, spawn protection",
	version = PLUGIN_VERSION,
	url = "https://github.com/srcdslab/sm-plugin-Deathmatch"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_CSS)
	{
		strcopy(error, err_max, "This plugin only supports Counter-Strike: Source");
		return APLRes_Failure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("Deathmatch.phrases");

	CreateConVar("sm_deathmatch_version", PLUGIN_VERSION, "Deathmatch version", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	g_cvEnable = CreateConVar("sm_dm_enable", "1", "Enable deathmatch, 0 = off/1 = on", _, true, 0.0, true, 1.0);
	g_cvRespawnTime = CreateConVar("sm_dm_respawn_time", "1.5", "Seconds before a dead player respawns", _, true, 0.1, true, 30.0);
	g_cvSpawnProtection = CreateConVar("sm_dm_spawn_protection", "2.0", "Seconds of god mode after a spawn, ends when the player shoots, 0 = off", _, true, 0.0, true, 10.0);
	g_cvRandomSpawns = CreateConVar("sm_dm_random_spawns", "1", "Spawn players on the points of configs/deathmatch/spawns/<map>.cfg (map spawns when the file is missing), 0 = off/1 = on", _, true, 0.0, true, 1.0);
	g_cvSpawnMinDistance = CreateConVar("sm_dm_spawn_min_distance", "600", "Preferred minimum distance between a spawn point and the closest enemy", _, true, 0.0);
	g_cvSpawnVisibility = CreateConVar("sm_dm_spawn_visibility_check", "1", "Avoid spawn points an enemy can see, 0 = off/1 = on", _, true, 0.0, true, 1.0);
	g_cvPrimaries = CreateConVar("sm_dm_primary_weapons", "ak47,m4a1,awp,famas,galil,aug,sg552,scout,m3,xm1014,mp5navy,p90,ump45,mac10,tmp,m249", "Primary weapons offered, without the weapon_ prefix, comma separated");
	g_cvSecondaries = CreateConVar("sm_dm_secondary_weapons", "deagle,usp,glock,p228,fiveseven,elite", "Secondary weapons offered, without the weapon_ prefix, comma separated");
	g_cvAwpLimit = CreateConVar("sm_dm_awp_limit", "2", "Maximum AWPs per team, -1 = no limit", _, true, -1.0);
	g_cvArmor = CreateConVar("sm_dm_armor", "100", "Armor given on spawn", _, true, 0.0, true, 100.0);
	g_cvHelmet = CreateConVar("sm_dm_helmet", "1", "Give a helmet on spawn, 0 = no/1 = yes", _, true, 0.0, true, 1.0);
	g_cvHEGrenades = CreateConVar("sm_dm_hegrenades", "0", "HE grenades given on spawn", _, true, 0.0, true, 1.0);
	g_cvFlashbangs = CreateConVar("sm_dm_flashbangs", "0", "Flashbangs given on spawn", _, true, 0.0, true, 2.0);
	g_cvSmokes = CreateConVar("sm_dm_smokegrenades", "0", "Smoke grenades given on spawn", _, true, 0.0, true, 1.0);
	g_cvMenuTime = CreateConVar("sm_dm_menu_time", "10", "Seconds after a spawn during which weapons picked in the menu replace the current ones", _, true, 0.0);
	g_cvDroppedLifetime = CreateConVar("sm_dm_dropped_weapon_lifetime", "0.1", "Seconds before a dropped weapon is removed, -1 = never", _, true, -1.0);
	g_cvHpOnKill = CreateConVar("sm_dm_hp_on_kill", "0", "Health given to the killer for a kill", _, true, 0.0);
	g_cvHpOnHeadshot = CreateConVar("sm_dm_hp_on_headshot", "0", "Health given to the killer for a headshot kill (instead of sm_dm_hp_on_kill)", _, true, 0.0);
	g_cvMaxHp = CreateConVar("sm_dm_max_hp", "100", "Health cap for the kill rewards", _, true, 1.0);
	g_cvRemoveObjectives = CreateConVar("sm_dm_remove_objectives", "1", "Remove bomb sites, hostages and rescue zones, 0 = no/1 = yes", _, true, 0.0, true, 1.0);
	g_cvMapTimer = CreateConVar("sm_dm_round_timer_map_time", "1", "Show the map time left in the round timer (needs mp_timelimit), 0 = no/1 = yes", _, true, 0.0, true, 1.0);

	AutoExecConfig(true);

	g_cvChatTime = FindConVar("mp_chattime");
	g_cvPrimaries.AddChangeHook(OnWeaponListChanged);
	g_cvSecondaries.AddChangeHook(OnWeaponListChanged);

	g_aSpawns = new ArrayList(sizeof(SpawnPoint));
	g_aPrimaries = new ArrayList(ByteCountToCells(32));
	g_aSecondaries = new ArrayList(ByteCountToCells(32));
	ParseWeaponList(g_cvPrimaries, g_aPrimaries);
	ParseWeaponList(g_cvSecondaries, g_aSecondaries);

	g_ckPrimary = new Cookie("dm_primary", "Deathmatch primary weapon", CookieAccess_Private);
	g_ckSecondary = new Cookie("dm_secondary", "Deathmatch secondary weapon", CookieAccess_Private);
	g_ckMode = new Cookie("dm_mode", "Deathmatch weapon menu mode", CookieAccess_Private);

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("weapon_fire", Event_WeaponFire);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);

	AddCommandListener(Command_JoinClass, "joinclass");

	RegConsoleCmd("sm_guns", Command_Guns, "Choose your deathmatch weapons");
	RegConsoleCmd("sm_weapons", Command_Guns, "Choose your deathmatch weapons");

	RegAdminCmd("sm_dm_spawn_add", Command_SpawnAdd, ADMFLAG_CONFIG, "Add a spawn point at your position");
	RegAdminCmd("sm_dm_spawn_remove", Command_SpawnRemove, ADMFLAG_CONFIG, "Remove the spawn point closest to you");
	RegAdminCmd("sm_dm_spawn_save", Command_SpawnSave, ADMFLAG_CONFIG, "Save the spawn points of the current map");
	RegAdminCmd("sm_dm_spawn_reload", Command_SpawnReload, ADMFLAG_CONFIG, "Reload the spawn points of the current map");
	RegAdminCmd("sm_dm_spawn_show", Command_SpawnShow, ADMFLAG_CONFIG, "Show the spawn points for 10 seconds");

	// Late load
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;

		OnClientPutInServer(client);
		if (AreClientCookiesCached(client))
			OnClientCookiesCached(client);
	}
}

public void OnPluginEnd()
{
	// SM 1.13 x64 crashes when a plugin is unloaded while one of its menus is open
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && GetClientMenu(client) != MenuSource_None)
			CancelClientMenu(client, true);

		RemoveProtection(client);
	}
}

public void OnMapStart()
{
	g_bMapEnding = false;
	GetCurrentMap(g_sMap, sizeof(g_sMap));
	GetMapDisplayName(g_sMap, g_sMap, sizeof(g_sMap));

	g_iBeamSprite = PrecacheModel("sprites/laserbeam.vmt");
	g_iHaloSprite = PrecacheModel("sprites/glow01.vmt");

	for (int i = 0; i < sizeof(g_fSpawnUsed); i++)
		g_fSpawnUsed[i] = 0.0;

	LoadSpawns();
	CreateTimer(1.0, Timer_CheckTimeLimit, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
	// TIMER_FLAG_NO_MAPCHANGE timers are already gone: forget their handles
	for (int client = 1; client <= MaxClients; client++)
		g_hRespawnTimer[client] = null;
}

// Cookies can be cached before OnClientPutInServer: reset here, not there
public void OnClientConnected(int client)
{
	g_sPrimary[client][0] = '\0';
	g_sSecondary[client][0] = '\0';
	g_eMode[client] = Choice_Menu;
	g_fProtectedUntil[client] = 0.0;
	g_bProtectionVisual[client] = false;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDropPost);
}

public void OnClientDisconnect(int client)
{
	delete g_hRespawnTimer[client];
	g_fProtectedUntil[client] = 0.0;
	g_bProtectionVisual[client] = false;
}

public void OnClientCookiesCached(int client)
{
	if (IsFakeClient(client))
		return;

	char sValue[32];
	g_ckPrimary.Get(client, sValue, sizeof(sValue));
	if (IsWeaponAllowed(sValue, g_aPrimaries))
		strcopy(g_sPrimary[client], sizeof(g_sPrimary[]), sValue);

	g_ckSecondary.Get(client, sValue, sizeof(sValue));
	if (IsWeaponAllowed(sValue, g_aSecondaries))
		strcopy(g_sSecondary[client], sizeof(g_sSecondary[]), sValue);

	g_ckMode.Get(client, sValue, sizeof(sValue));
	g_eMode[client] = (StringToInt(sValue) == view_as<int>(Choice_Always) && g_sPrimary[client][0] && g_sSecondary[client][0]) ? Choice_Always : Choice_Menu;
}

/* ---------------------------------------------------------------------------------------------- */
/* Round flow                                                                                     */
/* ---------------------------------------------------------------------------------------------- */

// The round only ends when the map does: no team win when a team is wiped out between two
// respawns, no round time out. "Game commencing" (first players of both teams) still restarts.
public Action CS_OnTerminateRound(float &delay, CSRoundEndReason &reason)
{
	if (!g_cvEnable.BoolValue || g_bMapEnding || reason == CSRoundEnd_GameStart)
		return Plugin_Continue;

	return Plugin_Handled;
}

public Action CS_OnBuyCommand(int client, const char[] weapon)
{
	return g_cvEnable.BoolValue ? Plugin_Handled : Plugin_Continue;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue || !g_cvRemoveObjectives.BoolValue)
		return;

	RemoveEntitiesByClassname("func_bomb_target");
	RemoveEntitiesByClassname("func_hostage_rescue");
	RemoveEntitiesByClassname("hostage_entity");
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue || !g_cvMapTimer.BoolValue)
		return;

	int iTimeLimit, iTimeLeft;
	if (!GetMapTimeLimit(iTimeLimit) || iTimeLimit <= 0 || !GetMapTimeLeft(iTimeLeft) || iTimeLeft <= 0)
		return;

	// The round timer counts down to the end of the map, so the round never times out first
	GameRules_SetProp("m_iRoundTime", iTimeLeft);
	GameRules_SetPropFloat("m_fRoundStartTime", GetGameTime());
}

// mp_timelimit is only checked by the game when a round ends, which never happens here:
// end the round ourselves once the time is up, and change the map if the game still does not.
public Action Timer_CheckTimeLimit(Handle timer)
{
	if (!g_cvEnable.BoolValue || g_bMapEnding)
		return Plugin_Continue;

	// GetMapTimeLeft gives -1 without a time limit, and also once the limit is 1 s past
	int iTimeLimit;
	if (!GetMapTimeLimit(iTimeLimit) || iTimeLimit <= 0)
		return Plugin_Continue;

	int iTimeLeft;
	if (!GetMapTimeLeft(iTimeLeft) || iTimeLeft > 0)
		return Plugin_Continue;

	g_bMapEnding = true;
	CS_TerminateRound(5.0, CSRoundEnd_Draw, false);

	float fChatTime = g_cvChatTime != null ? g_cvChatTime.FloatValue : 10.0;
	CreateTimer(fChatTime + 15.0, Timer_ForceMapChange, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public Action Timer_ForceMapChange(Handle timer)
{
	char sMap[PLATFORM_MAX_PATH];
	if (!GetNextMap(sMap, sizeof(sMap)) || !IsMapValid(sMap))
		GetCurrentMap(sMap, sizeof(sMap));

	ForceChangeLevel(sMap, "Deathmatch time limit reached");
	return Plugin_Stop;
}

/* ---------------------------------------------------------------------------------------------- */
/* Respawn                                                                                        */
/* ---------------------------------------------------------------------------------------------- */

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
		return;

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (victim)
	{
		RemoveProtection(victim);
		ScheduleRespawn(victim, g_cvRespawnTime.FloatValue);
	}

	if (attacker && attacker != victim && IsClientInGame(attacker) && IsPlayerAlive(attacker))
	{
		int iBonus = event.GetBool("headshot") && g_cvHpOnHeadshot.IntValue > 0 ? g_cvHpOnHeadshot.IntValue : g_cvHpOnKill.IntValue;
		if (iBonus > 0)
		{
			int iHealth = GetClientHealth(attacker) + iBonus;
			if (iHealth > g_cvMaxHp.IntValue)
				iHealth = g_cvMaxHp.IntValue;

			if (iHealth > GetClientHealth(attacker))
				SetEntityHealth(attacker, iHealth);
		}
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue || event.GetBool("disconnect"))
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && event.GetInt("team") >= CS_TEAM_T)
		ScheduleRespawn(client, g_cvRespawnTime.FloatValue);
}

// A human picks a team then a model: spawn him once the model is chosen
public Action Command_JoinClass(int client, const char[] command, int argc)
{
	if (g_cvEnable.BoolValue && client && IsClientInGame(client))
		ScheduleRespawn(client, 0.5);

	return Plugin_Continue;
}

void ScheduleRespawn(int client, float fDelay)
{
	delete g_hRespawnTimer[client];
	g_hRespawnTimer[client] = CreateTimer(fDelay, Timer_Respawn, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Respawn(Handle timer, int client)
{
	g_hRespawnTimer[client] = null;

	if (!g_cvEnable.BoolValue || g_bMapEnding || !IsClientInGame(client) || IsPlayerAlive(client))
		return Plugin_Stop;

	if (GetClientTeam(client) < CS_TEAM_T)
		return Plugin_Stop;

	// A human who has not picked a model yet would spawn with the class menu still open
	if (!IsFakeClient(client) && HasEntProp(client, Prop_Send, "m_iClass") && GetEntProp(client, Prop_Send, "m_iClass") == 0)
		return Plugin_Stop;

	CS_RespawnPlayer(client);
	return Plugin_Stop;
}

/* ---------------------------------------------------------------------------------------------- */
/* Spawn                                                                                          */
/* ---------------------------------------------------------------------------------------------- */

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (g_cvEnable.BoolValue)
		RequestFrame(Frame_PlayerSpawned, event.GetInt("userid"));
}

// Next frame: the game is done with its own spawn (position, default pistol, C4)
void Frame_PlayerSpawned(int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) < CS_TEAM_T)
		return;

	delete g_hRespawnTimer[client];
	g_fSpawnTime[client] = GetGameTime();

	if (g_cvRandomSpawns.BoolValue)
		MoveToRandomSpawn(client);

	SetEntProp(client, Prop_Send, "m_ArmorValue", g_cvArmor.IntValue);
	SetEntProp(client, Prop_Send, "m_bHasHelmet", g_cvHelmet.BoolValue ? 1 : 0);

	if (IsFakeClient(client))
		GiveRandomWeapons(client);
	else if (g_sPrimary[client][0] && g_sSecondary[client][0])
	{
		GiveWeapons(client, g_sPrimary[client], g_sSecondary[client]);
		if (g_eMode[client] == Choice_Menu)
			ShowMainMenu(client);
	}
	else
	{
		// First spawn: keep the team pistol until the player picks his weapons
		StripWeapons(client, false);
		GiveGrenades(client);
		ShowMainMenu(client);
	}

	StartProtection(client);
}

void MoveToRandomSpawn(int client)
{
	int iCount = g_aSpawns.Length;
	if (!iCount)
		return;

	int iTeam = GetClientTeam(client);
	float fNow = GetGameTime();
	float fMinDistance = g_cvSpawnMinDistance.FloatValue;
	bool bCheckVisibility = g_cvSpawnVisibility.BoolValue;

	int iBest = -1;
	float fBestScore = -1.0;
	int iStart = GetRandomInt(0, iCount - 1);

	SpawnPoint spawn;
	for (int n = 0; n < iCount; n++)
	{
		int i = (iStart + n) % iCount;

		// Another player just used it and may still stand there
		if (i < sizeof(g_fSpawnUsed) && fNow - g_fSpawnUsed[i] < 2.0)
			continue;

		g_aSpawns.GetArray(i, spawn);
		if (IsSpawnBlocked(spawn.origin, client))
			continue;

		float fClosest = ClosestEnemyDistance(spawn.origin, iTeam);
		bool bSeen = bCheckVisibility && IsSeenByEnemy(spawn.origin, iTeam);

		if (!bSeen && fClosest >= fMinDistance)
		{
			iBest = i;
			break;
		}

		// Fallback: an unseen point first, then the one furthest from the enemies
		float fScore = (bSeen ? 0.0 : 100000.0) + fClosest;
		if (fScore > fBestScore)
		{
			fBestScore = fScore;
			iBest = i;
		}
	}

	if (iBest == -1)
		return;

	g_aSpawns.GetArray(iBest, spawn);
	if (iBest < sizeof(g_fSpawnUsed))
		g_fSpawnUsed[iBest] = fNow;

	float fNoVelocity[3];
	TeleportEntity(client, spawn.origin, spawn.angles, fNoVelocity);
}

bool IsSpawnBlocked(const float fOrigin[3], int client)
{
	float fMins[3] = { -16.0, -16.0, 0.0 };
	float fMaxs[3] = { 16.0, 16.0, 72.0 };

	TR_TraceHullFilter(fOrigin, fOrigin, fMins, fMaxs, MASK_PLAYERSOLID, TraceFilter_NotSelf, client);
	return TR_DidHit();
}

public bool TraceFilter_NotSelf(int entity, int contentsMask, int client)
{
	return entity != client;
}

public bool TraceFilter_WorldOnly(int entity, int contentsMask)
{
	return entity == 0;
}

float ClosestEnemyDistance(const float fOrigin[3], int iTeam)
{
	float fClosest = 999999.0;
	float fPos[3];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) == iTeam || GetClientTeam(i) < CS_TEAM_T)
			continue;

		GetClientAbsOrigin(i, fPos);
		float fDistance = GetVectorDistance(fOrigin, fPos);
		if (fDistance < fClosest)
			fClosest = fDistance;
	}

	return fClosest;
}

bool IsSeenByEnemy(const float fOrigin[3], int iTeam)
{
	float fHead[3];
	fHead = fOrigin;
	fHead[2] += 64.0;

	float fEye[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) == iTeam || GetClientTeam(i) < CS_TEAM_T)
			continue;

		GetClientEyePosition(i, fEye);
		if (GetVectorDistance(fEye, fHead) > SPAWN_VISIBILITY_RANGE)
			continue;

		TR_TraceRayFilter(fEye, fHead, MASK_VISIBLE, RayType_EndPoint, TraceFilter_WorldOnly);
		if (!TR_DidHit())
			return true;
	}

	return false;
}

/* ---------------------------------------------------------------------------------------------- */
/* Spawn protection                                                                               */
/* ---------------------------------------------------------------------------------------------- */

void StartProtection(int client)
{
	float fTime = g_cvSpawnProtection.FloatValue;
	if (fTime <= 0.0)
		return;

	g_fProtectedUntil[client] = GetGameTime() + fTime;

	// Alpha is ignored under RENDER_NORMAL
	int r, g, b, a;
	GetEntityRenderColor(client, r, g, b, a);
	g_iSavedAlpha[client] = a;
	g_bProtectionVisual[client] = true;
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, r, g, b, 120);

	CreateTimer(fTime, Timer_EndProtection, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_EndProtection(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client && GetGameTime() + 0.05 >= g_fProtectedUntil[client])
		RemoveProtection(client);

	return Plugin_Stop;
}

void RemoveProtection(int client)
{
	g_fProtectedUntil[client] = 0.0;

	if (!g_bProtectionVisual[client])
		return;

	g_bProtectionVisual[client] = false;
	if (!IsClientInGame(client))
		return;

	int r, g, b, a;
	GetEntityRenderColor(client, r, g, b, a);
	SetEntityRenderColor(client, r, g, b, g_iSavedAlpha[client]);
	if (g_iSavedAlpha[client] >= 255)
		SetEntityRenderMode(client, RENDER_NORMAL);
}

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && g_fProtectedUntil[client] > 0.0)
		RemoveProtection(client);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (g_fProtectedUntil[victim] > GetGameTime())
		return Plugin_Handled;

	return Plugin_Continue;
}

/* ---------------------------------------------------------------------------------------------- */
/* Weapons                                                                                        */
/* ---------------------------------------------------------------------------------------------- */

public void OnWeaponListChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	ParseWeaponList(g_cvPrimaries, g_aPrimaries);
	ParseWeaponList(g_cvSecondaries, g_aSecondaries);
}

void ParseWeaponList(ConVar cvar, ArrayList list)
{
	list.Clear();

	char sValue[512];
	cvar.GetString(sValue, sizeof(sValue));

	char sParts[32][32];
	int iCount = ExplodeString(sValue, ",", sParts, sizeof(sParts), sizeof(sParts[]));
	for (int i = 0; i < iCount; i++)
	{
		TrimString(sParts[i]);
		ReplaceString(sParts[i], sizeof(sParts[]), "weapon_", "", false);
		if (sParts[i][0] && GetWeaponIndex(sParts[i]) != -1)
			list.PushString(sParts[i]);
	}
}

int GetWeaponIndex(const char[] sWeapon)
{
	for (int i = 0; i < sizeof(g_sWeaponNames); i++)
	{
		if (StrEqual(g_sWeaponNames[i][0], sWeapon, false))
			return i;
	}

	return -1;
}

void GetWeaponDisplayName(const char[] sWeapon, char[] sName, int iMaxLen)
{
	int i = GetWeaponIndex(sWeapon);
	strcopy(sName, iMaxLen, i == -1 ? sWeapon : g_sWeaponNames[i][1]);
}

bool IsWeaponAllowed(const char[] sWeapon, ArrayList list)
{
	return sWeapon[0] && list.FindString(sWeapon) != -1;
}

int CountTeamAwps(int iTeam, int iExclude)
{
	int iCount = 0;
	char sClass[32];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == iExclude || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != iTeam)
			continue;

		int weapon = GetPlayerWeaponSlot(i, CS_SLOT_PRIMARY);
		if (weapon != -1 && GetEntityClassname(weapon, sClass, sizeof(sClass)) && StrEqual(sClass, "weapon_awp"))
			iCount++;
	}

	return iCount;
}

bool IsAwpFull(int client)
{
	int iLimit = g_cvAwpLimit.IntValue;
	return iLimit >= 0 && CountTeamAwps(GetClientTeam(client), client) >= iLimit;
}

// Removes the primary, the secondary (unless bKeepSecondary), grenades and C4; keeps the knife
void StripWeapons(int client, bool bStripSecondary = true)
{
	int iSlots[] = { CS_SLOT_PRIMARY, CS_SLOT_SECONDARY, CS_SLOT_GRENADE, CS_SLOT_C4 };
	for (int s = 0; s < sizeof(iSlots); s++)
	{
		if (iSlots[s] == CS_SLOT_SECONDARY && !bStripSecondary)
			continue;

		int weapon;
		// Several grenades share the grenade slot
		while ((weapon = GetPlayerWeaponSlot(client, iSlots[s])) != -1)
		{
			RemovePlayerItem(client, weapon);
			RemoveEntity(weapon);
		}
	}

	if (GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == -1)
		GivePlayerItem(client, "weapon_knife");
}

void GiveGrenades(int client)
{
	for (int i = 0; i < g_cvHEGrenades.IntValue; i++)
		GivePlayerItem(client, "weapon_hegrenade");
	for (int i = 0; i < g_cvFlashbangs.IntValue; i++)
		GivePlayerItem(client, "weapon_flashbang");
	for (int i = 0; i < g_cvSmokes.IntValue; i++)
		GivePlayerItem(client, "weapon_smokegrenade");
}

void GiveWeapons(int client, const char[] sPrimary, const char[] sSecondary)
{
	StripWeapons(client);

	char sItem[48];
	char sPrimaryToGive[32];
	strcopy(sPrimaryToGive, sizeof(sPrimaryToGive), sPrimary);

	if (StrEqual(sPrimaryToGive, "awp") && IsAwpFull(client))
	{
		PickRandomWeapon(g_aPrimaries, sPrimaryToGive, sizeof(sPrimaryToGive), true);
		if (!IsFakeClient(client))
		{
			char sName[32];
			GetWeaponDisplayName(sPrimaryToGive, sName, sizeof(sName));
			PrintToChat(client, "%s%t", CHAT_PREFIX, "AWP Limit", g_cvAwpLimit.IntValue, sName);
		}
	}

	if (sSecondary[0])
	{
		FormatEx(sItem, sizeof(sItem), "weapon_%s", sSecondary);
		GivePlayerItem(client, sItem);
	}

	GiveGrenades(client);

	if (sPrimaryToGive[0])
	{
		FormatEx(sItem, sizeof(sItem), "weapon_%s", sPrimaryToGive);
		// The game switches to it: a primary outweighs the pistol
		GivePlayerItem(client, sItem);
	}
}

void PickRandomWeapon(ArrayList list, char[] sWeapon, int iMaxLen, bool bNoAwp)
{
	sWeapon[0] = '\0';

	int iCount = list.Length;
	if (!iCount)
		return;

	int iStart = GetRandomInt(0, iCount - 1);
	for (int n = 0; n < iCount; n++)
	{
		list.GetString((iStart + n) % iCount, sWeapon, iMaxLen);
		if (!bNoAwp || !StrEqual(sWeapon, "awp"))
			return;
	}

	sWeapon[0] = '\0';
}

void GiveRandomWeapons(int client)
{
	char sPrimary[32], sSecondary[32];
	PickRandomWeapon(g_aPrimaries, sPrimary, sizeof(sPrimary), IsAwpFull(client));
	PickRandomWeapon(g_aSecondaries, sSecondary, sizeof(sSecondary), false);
	GiveWeapons(client, sPrimary, sSecondary);
}

public void OnWeaponDropPost(int client, int weapon)
{
	if (!g_cvEnable.BoolValue || weapon <= MaxClients || !IsValidEntity(weapon))
		return;

	float fLifetime = g_cvDroppedLifetime.FloatValue;
	if (fLifetime < 0.0)
		return;

	CreateTimer(fLifetime, Timer_RemoveDroppedWeapon, EntIndexToEntRef(weapon), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RemoveDroppedWeapon(Handle timer, int ref)
{
	int weapon = EntRefToEntIndex(ref);
	if (weapon != INVALID_ENT_REFERENCE && GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity") == -1)
		RemoveEntity(weapon);

	return Plugin_Stop;
}

/* ---------------------------------------------------------------------------------------------- */
/* Weapon menu                                                                                    */
/* ---------------------------------------------------------------------------------------------- */

public Action Command_Guns(int client, int args)
{
	if (!client || !g_cvEnable.BoolValue)
		return Plugin_Handled;

	g_eMode[client] = Choice_Menu;
	g_ckMode.Set(client, "0");
	ShowMainMenu(client);
	return Plugin_Handled;
}

void ShowMainMenu(int client)
{
	bool bHasWeapons = g_sPrimary[client][0] && g_sSecondary[client][0];

	Menu menu = new Menu(MenuHandler_Main);
	menu.SetTitle("%T", "Menu Title", client);

	char sItem[64];
	FormatEx(sItem, sizeof(sItem), "%T", "New Weapons", client);
	menu.AddItem("new", sItem);
	FormatEx(sItem, sizeof(sItem), "%T", "Same Weapons", client);
	menu.AddItem("same", sItem, bHasWeapons ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(sItem, sizeof(sItem), "%T", "Same Weapons Always", client);
	menu.AddItem("always", sItem, bHasWeapons ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(sItem, sizeof(sItem), "%T", "Random Weapons", client);
	menu.AddItem("random", sItem);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Main(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	if (action != MenuAction_Select)
		return 0;

	char sInfo[16];
	menu.GetItem(item, sInfo, sizeof(sInfo));

	if (StrEqual(sInfo, "new"))
		ShowWeaponMenu(client, true);
	else if (StrEqual(sInfo, "always"))
	{
		g_eMode[client] = Choice_Always;
		g_ckMode.Set(client, "1");
		PrintToChat(client, "%s%t", CHAT_PREFIX, "Guns Command");
	}
	else if (StrEqual(sInfo, "random") && CanReplaceWeapons(client))
		GiveRandomWeapons(client);

	return 0;
}

void ShowWeaponMenu(int client, bool bPrimary)
{
	ArrayList list = bPrimary ? g_aPrimaries : g_aSecondaries;

	Menu menu = new Menu(bPrimary ? MenuHandler_Primary : MenuHandler_Secondary);
	menu.SetTitle("%T", bPrimary ? "Primary Title" : "Secondary Title", client);

	bool bAwpFull = bPrimary && IsClientInGame(client) && GetClientTeam(client) >= CS_TEAM_T && IsAwpFull(client);
	char sWeapon[32], sName[48];
	for (int i = 0; i < list.Length; i++)
	{
		list.GetString(i, sWeapon, sizeof(sWeapon));
		GetWeaponDisplayName(sWeapon, sName, sizeof(sName));

		if (bAwpFull && StrEqual(sWeapon, "awp"))
		{
			Format(sName, sizeof(sName), "%T", "Limit Reached", client, sName);
			menu.AddItem(sWeapon, sName, ITEMDRAW_DISABLED);
		}
		else
			menu.AddItem(sWeapon, sName);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Primary(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	if (action != MenuAction_Select)
		return 0;

	menu.GetItem(item, g_sPrimary[client], sizeof(g_sPrimary[]));
	g_ckPrimary.Set(client, g_sPrimary[client]);
	ShowWeaponMenu(client, false);
	return 0;
}

public int MenuHandler_Secondary(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	if (action != MenuAction_Select)
		return 0;

	menu.GetItem(item, g_sSecondary[client], sizeof(g_sSecondary[]));
	g_ckSecondary.Set(client, g_sSecondary[client]);

	if (CanReplaceWeapons(client))
		GiveWeapons(client, g_sPrimary[client], g_sSecondary[client]);
	else
		PrintToChat(client, "%s%t", CHAT_PREFIX, "Weapons Next Spawn");

	return 0;
}

bool CanReplaceWeapons(int client)
{
	return IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) >= CS_TEAM_T
		&& GetGameTime() - g_fSpawnTime[client] <= g_cvMenuTime.FloatValue;
}

/* ---------------------------------------------------------------------------------------------- */
/* Spawn points                                                                                   */
/* ---------------------------------------------------------------------------------------------- */

void GetSpawnFile(char[] sPath, int iMaxLen)
{
	BuildPath(Path_SM, sPath, iMaxLen, "configs/deathmatch/spawns/%s.cfg", g_sMap);
}

void LoadSpawns()
{
	g_aSpawns.Clear();

	char sPath[PLATFORM_MAX_PATH];
	GetSpawnFile(sPath, sizeof(sPath));
	if (!FileExists(sPath))
		return;

	KeyValues kv = new KeyValues("Spawns");
	if (!kv.ImportFromFile(sPath))
	{
		LogError("Could not parse %s", sPath);
		delete kv;
		return;
	}

	SpawnPoint spawn;
	if (kv.GotoFirstSubKey())
	{
		do
		{
			kv.GetVector("origin", spawn.origin);
			kv.GetVector("angles", spawn.angles);
			g_aSpawns.PushArray(spawn);
		}
		while (kv.GotoNextKey());
	}

	delete kv;
}

bool SaveSpawns(char[] sPath, int iMaxLen)
{
	GetSpawnFile(sPath, iMaxLen);

	char sDir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sDir, sizeof(sDir), "configs/deathmatch");
	if (!DirExists(sDir))
		CreateDirectory(sDir, 511);
	BuildPath(Path_SM, sDir, sizeof(sDir), "configs/deathmatch/spawns");
	if (!DirExists(sDir))
		CreateDirectory(sDir, 511);

	KeyValues kv = new KeyValues("Spawns");
	SpawnPoint spawn;
	char sKey[8];

	for (int i = 0; i < g_aSpawns.Length; i++)
	{
		g_aSpawns.GetArray(i, spawn);
		IntToString(i, sKey, sizeof(sKey));
		kv.JumpToKey(sKey, true);
		kv.SetVector("origin", spawn.origin);
		kv.SetVector("angles", spawn.angles);
		kv.GoBack();
	}

	bool bResult = kv.ExportToFile(sPath);
	delete kv;
	return bResult;
}

public Action Command_SpawnAdd(int client, int args)
{
	if (!client || !IsPlayerAlive(client))
		return Plugin_Handled;

	SpawnPoint spawn;
	GetClientAbsOrigin(client, spawn.origin);
	GetClientEyeAngles(client, spawn.angles);
	spawn.angles[0] = 0.0;
	spawn.angles[2] = 0.0;

	int i = g_aSpawns.PushArray(spawn);
	ReplyToCommand(client, "%s%t", CHAT_PREFIX, "Spawn Added", i, g_aSpawns.Length);
	return Plugin_Handled;
}

public Action Command_SpawnRemove(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	float fPos[3];
	GetClientAbsOrigin(client, fPos);

	int iClosest = -1;
	float fClosest = SPAWN_REMOVE_RADIUS;
	SpawnPoint spawn;

	for (int i = 0; i < g_aSpawns.Length; i++)
	{
		g_aSpawns.GetArray(i, spawn);
		float fDistance = GetVectorDistance(fPos, spawn.origin);
		if (fDistance <= fClosest)
		{
			fClosest = fDistance;
			iClosest = i;
		}
	}

	if (iClosest == -1)
	{
		ReplyToCommand(client, "%s%t", CHAT_PREFIX, "No Spawn Nearby", RoundToFloor(SPAWN_REMOVE_RADIUS));
		return Plugin_Handled;
	}

	g_aSpawns.Erase(iClosest);
	ReplyToCommand(client, "%s%t", CHAT_PREFIX, "Spawn Removed", iClosest, g_aSpawns.Length);
	return Plugin_Handled;
}

public Action Command_SpawnSave(int client, int args)
{
	char sPath[PLATFORM_MAX_PATH];
	if (SaveSpawns(sPath, sizeof(sPath)))
		ReplyToCommand(client, "%s%t", CHAT_PREFIX, "Spawns Saved", g_aSpawns.Length, sPath);
	else
		ReplyToCommand(client, "%s%t", CHAT_PREFIX, "Spawns Save Failed", sPath);

	return Plugin_Handled;
}

public Action Command_SpawnReload(int client, int args)
{
	LoadSpawns();
	ReplyToCommand(client, "%s%t", CHAT_PREFIX, "Spawns Loaded", g_aSpawns.Length, g_sMap);
	return Plugin_Handled;
}

public Action Command_SpawnShow(int client, int args)
{
	if (!client || g_iBeamSprite == -1)
		return Plugin_Handled;

	SpawnPoint spawn;
	for (int i = 0; i < g_aSpawns.Length; i++)
	{
		g_aSpawns.GetArray(i, spawn);
		spawn.origin[2] += 8.0;
		TE_SetupBeamRingPoint(spawn.origin, 40.0, 41.0, g_iBeamSprite, g_iHaloSprite, 0, 10, 10.0, 4.0, 0.0, { 0, 255, 0, 255 }, 0, 0);
		TE_SendToClient(client);
	}

	ReplyToCommand(client, "%s%t", CHAT_PREFIX, "Spawns Shown", g_aSpawns.Length);
	return Plugin_Handled;
}

/* ---------------------------------------------------------------------------------------------- */
/* Helpers                                                                                        */
/* ---------------------------------------------------------------------------------------------- */

void RemoveEntitiesByClassname(const char[] sClassname)
{
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, sClassname)) != -1)
		RemoveEntity(entity);
}
