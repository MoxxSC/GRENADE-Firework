/**
 * HL2DM Grenade Firework 1.5.0
 * 
 * Commands:
 *   /firework - Your next grenade will be a firework. (120s timeout)
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.5.0"


#define FIREWORK_TIMEOUT        120.0    // Seconds before activation expires
#define ROMAN_CANDLE_MIN        30.0    // Min candle duration
#define ROMAN_CANDLE_MAX        60.0    // Max candle duration
#define ROMAN_CANDLE_DEFAULT    45.0    // Default candle duration
#define ROMAN_CANDLE_HEIGHT     128.0   // Spark fountain height
#define ROMAN_CANDLE_TICK       0.08    // Update interval
#define CLASSIC_RAYS            24      // Number of burst rays
#define CLASSIC_RADIUS_MIN      200.0   // Min explosion radius
#define CLASSIC_RADIUS_MAX      400.0   // Max explosion radius
#define FOUNTAIN_PARTICLES      20      // Number of fountain particles
#define FOUNTAIN_SPEED          600.0   // Initial upward velocity
#define FOUNTAIN_GRAVITY        400.0   // Gravity strength
#define FOUNTAIN_DURATION       5.0     // How long particles last
#define TWOX_SPREAD             300.0   // Secondary explosion spread
#define TWOX_TERTIARY_SPREAD    220.0   // Tertiary explosion spread
#define LAUNCH_SPEED            900.0   // Firework launch velocity
#define FLIGHT_TIME_MIN         1.2     // Min flight time
#define FLIGHT_TIME_MAX         1.8     // Max flight time

enum FireworkType
{
    FW_CLASSIC = 0,
    FW_ROMAN_CANDLE,
    FW_FOUNTAIN,
    FW_TWOX,
    FW_COUNT
}

enum FireworkColor
{
    FWC_RANDOM = 0,
    FWC_RED,
    FWC_GREEN,
    FWC_BLUE,
    FWC_YELLOW,
    FWC_MAGENTA,
    FWC_CYAN,
    FWC_ORANGE,
    FWC_WHITE,
    FWC_PINK,
    FWC_LIME,
    FWC_GOLD,
    FWC_COUNT
}

// Color RGB values
int g_Colors[][] = {
    {255, 255, 255},  // Random (placeholder)
    {255, 50, 50},    // Red
    {50, 255, 50},    // Green
    {50, 50, 255},    // Blue
    {255, 255, 50},   // Yellow
    {255, 50, 255},   // Magenta
    {50, 255, 255},   // Cyan
    {255, 150, 50},   // Orange
    {255, 255, 255},  // White
    {255, 100, 150},  // Pink
    {150, 255, 100},  // Lime
    {255, 200, 100}   // Gold
};

char g_ColorNames[][] = {
    "Random", "Red", "Green", "Blue", "Yellow", "Magenta",
    "Cyan", "Orange", "White", "Pink", "Lime", "Gold"
};

char g_TypeNames[][] = {
    "Classic", "Roman Candle", "Fountain", "TwoX"
};

// Sprite indices
int g_iBeam, g_iHalo, g_iGlow, g_iSmoke, g_iFlare;

// Per-player state
bool g_bActive[MAXPLAYERS + 1];
Handle g_hTimer[MAXPLAYERS + 1];
FireworkType g_eType[MAXPLAYERS + 1];
FireworkColor g_eColor[MAXPLAYERS + 1];
float g_fCandle[MAXPLAYERS + 1];

// Trace result storage
float g_vTraceHitPos[3];

// Data structures
StringMap g_hGrenades;
ArrayList g_hEntities;

// ============================================================================
// PLUGIN INFO
// ============================================================================

public Plugin myinfo = {
    name = "HL2DM Firework Grenades",
    author = "Moxx",
    description = "Turn grenades into fireworks, now with menu customization and collision detection.",
    version = PLUGIN_VERSION,
    url = "moxx.me"
};

// ============================================================================
// PLUGIN LIFECYCLE
// ============================================================================

public void OnPluginStart()
{
    // Register commands
    RegConsoleCmd("sm_firework", Cmd_Firework);
    RegConsoleCmd("firework", Cmd_Firework);
    RegConsoleCmd("sm_fw", Cmd_Firework);
    RegConsoleCmd("fw", Cmd_Firework);
    
    // Initialize data structures
    g_hGrenades = new StringMap();
    g_hEntities = new ArrayList();
    
    // Hook spawn event
    HookEvent("player_spawn", OnSpawn);
    
    // Initialize all players
    for (int i = 1; i <= MaxClients; i++)
    {
        ResetClient(i);
    }
}

public void OnPluginEnd()
{
    CleanupEntities();
}

public void OnMapStart()
{
    // Precache sprites
    g_iBeam = PrecacheModel("sprites/laser.vmt");
    g_iHalo = PrecacheModel("sprites/halo01.vmt");
    g_iGlow = PrecacheModel("sprites/glow01.vmt");
    g_iSmoke = PrecacheModel("sprites/steam1.vmt");
    g_iFlare = PrecacheModel("sprites/light_glow02.vmt");
    
    // Precache sounds
    PrecacheSound("weapons/flaregun/fire.wav");
    PrecacheSound("ambient/explosions/explode_8.wav");
    PrecacheSound("ambient/explosions/explode_4.wav");
    PrecacheSound("weapons/stunstick/spark1.wav");
    PrecacheSound("weapons/stunstick/spark2.wav");
    
    // Clear data
    g_hGrenades.Clear();
    CleanupEntities();
    
    // Reset player states
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bActive[i] = false;
        g_hTimer[i] = null;
    }
}

public void OnMapEnd()
{
    CleanupEntities();
}

public void OnClientConnected(int client)
{
    ResetClient(client);
}

public void OnClientDisconnect(int client)
{
    g_bActive[client] = false;
    KillTimerSafe(client);
}

public void OnSpawn(Event e, const char[] n, bool d)
{
    int client = GetClientOfUserId(e.GetInt("userid"));
    if (client > 0)
    {
        g_bActive[client] = false;
        KillTimerSafe(client);
    }
}

void ResetClient(int client)
{
    g_bActive[client] = false;
    g_hTimer[client] = null;
    g_eType[client] = FW_CLASSIC;
    g_eColor[client] = FWC_RANDOM;
    g_fCandle[client] = ROMAN_CANDLE_DEFAULT;
}

void KillTimerSafe(int client)
{
    if (g_hTimer[client] != null)
    {
        KillTimer(g_hTimer[client]);
        g_hTimer[client] = null;
    }
}

public Action Cmd_Firework(int client, int args)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client))
    {
        PrintToChat(client, "\x04[FW]\x01 You must be alive!");
        return Plugin_Handled;
    }
    
    ShowMainMenu(client);
    return Plugin_Handled;
}

void ShowMainMenu(int client)
{
    Menu menu = new Menu(MainMenuHandler);
    menu.SetTitle("=== Firework Menu ===\nType: %s\nColor: %s",
        g_TypeNames[g_eType[client]],
        g_ColorNames[g_eColor[client]]);
    
    // Toggle button changes text based on state
    menu.AddItem("toggle", g_bActive[client] ? ">>> DEACTIVATE <<<" : ">>> ACTIVATE <<<");
    menu.AddItem("type", "Select Type");
    menu.AddItem("color", "Select Color");
    
    // Show candle duration option only for Roman Candle
    if (g_eType[client] == FW_ROMAN_CANDLE)
    {
        char buf[64];
        Format(buf, sizeof(buf), "Candle Duration: %.0fs", g_fCandle[client]);
        menu.AddItem("candle", buf);
    }
    
    menu.ExitButton = true;
    menu.Display(client, 30);
}

public int MainMenuHandler(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param, info, sizeof(info));
        
        if (StrEqual(info, "toggle"))
        {
            ToggleFirework(client);
            ShowMainMenu(client);
        }
        else if (StrEqual(info, "type"))
        {
            ShowTypeMenu(client);
        }
        else if (StrEqual(info, "color"))
        {
            ShowColorMenu(client);
        }
        else if (StrEqual(info, "candle"))
        {
            ShowCandleMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    
    return 0;
}

void ShowTypeMenu(int client)
{
    Menu menu = new Menu(TypeMenuHandler);
    menu.SetTitle("Select Firework Type");
    
    for (int i = 0; i < view_as<int>(FW_COUNT); i++)
    {
        char idx[4], name[32];
        IntToString(i, idx, sizeof(idx));
        
        // Mark current selection with [*]
        Format(name, sizeof(name), "%s%s",
            g_TypeNames[i],
            (g_eType[client] == view_as<FireworkType>(i)) ? " [*]" : "");
        
        menu.AddItem(idx, name);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, 30);
}

public int TypeMenuHandler(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char info[4];
        menu.GetItem(param, info, sizeof(info));
        g_eType[client] = view_as<FireworkType>(StringToInt(info));
        PrintToChat(client, "\x04[FW]\x01 Type: \x05%s", g_TypeNames[g_eType[client]]);
        ShowMainMenu(client);
    }
    else if (action == MenuAction_Cancel && param == MenuCancel_ExitBack)
    {
        ShowMainMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    
    return 0;
}

void ShowColorMenu(int client)
{
    Menu menu = new Menu(ColorMenuHandler);
    menu.SetTitle("Select Color");
    
    for (int i = 0; i < view_as<int>(FWC_COUNT); i++)
    {
        char idx[4], name[32];
        IntToString(i, idx, sizeof(idx));
        
        Format(name, sizeof(name), "%s%s",
            g_ColorNames[i],
            (g_eColor[client] == view_as<FireworkColor>(i)) ? " [*]" : "");
        
        menu.AddItem(idx, name);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, 30);
}

public int ColorMenuHandler(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char info[4];
        menu.GetItem(param, info, sizeof(info));
        g_eColor[client] = view_as<FireworkColor>(StringToInt(info));
        PrintToChat(client, "\x04[FW]\x01 Color: \x05%s", g_ColorNames[g_eColor[client]]);
        ShowMainMenu(client);
    }
    else if (action == MenuAction_Cancel && param == MenuCancel_ExitBack)
    {
        ShowMainMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    
    return 0;
}

void ShowCandleMenu(int client)
{
    Menu menu = new Menu(CandleMenuHandler);
    menu.SetTitle("Roman Candle Duration\nCurrent: %.0fs", g_fCandle[client]);
    
    menu.AddItem("30", "30 seconds");
    menu.AddItem("35", "35 seconds");
    menu.AddItem("40", "40 seconds");
    menu.AddItem("45", "45 seconds");
    menu.AddItem("50", "50 seconds");
    menu.AddItem("55", "55 seconds");
    menu.AddItem("60", "60 seconds");
    
    menu.ExitBackButton = true;
    menu.Display(client, 30);
}

public int CandleMenuHandler(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char info[4];
        menu.GetItem(param, info, sizeof(info));
        g_fCandle[client] = StringToFloat(info);
        PrintToChat(client, "\x04[FW]\x01 Candle: \x05%.0fs", g_fCandle[client]);
        ShowMainMenu(client);
    }
    else if (action == MenuAction_Cancel && param == MenuCancel_ExitBack)
    {
        ShowMainMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    
    return 0;
}

void ToggleFirework(int client)
{
    // Validate weapon
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(weapon))
    {
        PrintToChat(client, "\x04[FW]\x01 Hold a grenade!");
        return;
    }
    
    char cls[32];
    GetEntityClassname(weapon, cls, sizeof(cls));
    if (!StrEqual(cls, "weapon_frag"))
    {
        PrintToChat(client, "\x04[FW]\x01 Hold a grenade!");
        return;
    }
    
    // Check ammo
    int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
    if (ammoType < 0 || GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType) < 1)
    {
        PrintToChat(client, "\x04[FW]\x01 Need 1+ grenade!");
        return;
    }
    
    // Toggle state
    if (g_bActive[client])
    {
        g_bActive[client] = false;
        KillTimerSafe(client);
        PrintToChat(client, "\x04[FW]\x01 \x07DEACTIVATED");
    }
    else
    {
        g_bActive[client] = true;
        KillTimerSafe(client);
        g_hTimer[client] = CreateTimer(FIREWORK_TIMEOUT, Timer_Expire, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
        PrintToChat(client, "\x04[FW]\x01 \x04ACTIVE\x01 - %s (%s)",
            g_TypeNames[g_eType[client]],
            g_ColorNames[g_eColor[client]]);
        
        // Visual feedback
        float pos[3];
        GetClientAbsOrigin(client, pos);
        pos[2] += 40.0;
        TE_SetupGlowSprite(pos, g_iGlow, 0.5, 1.0, 200);
        TE_SendToClient(client);
    }
}

public Action Timer_Expire(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client))
    {
        g_hTimer[client] = null;
        if (g_bActive[client])
        {
            g_bActive[client] = false;
            PrintToChat(client, "\x04[FW]\x01 \x07EXPIRED");
        }
    }
    return Plugin_Stop;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "npc_grenade_frag"))
    {
        SDKHook(entity, SDKHook_SpawnPost, OnGrenadeSpawn);
    }
}

public void OnGrenadeSpawn(int entity)
{
    if (!IsValidEntity(entity))
        return;
    
    int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (!IsValidClient(owner) || !g_bActive[owner])
        return;
    
    // Consume activation
    g_bActive[owner] = false;
    KillTimerSafe(owner);
    
    // Store grenade data (type, color, candle duration packed into int)
    char key[16];
    IntToString(EntIndexToEntRef(entity), key, sizeof(key));
    int data = (view_as<int>(g_eType[owner]) << 16) |
               (view_as<int>(g_eColor[owner]) << 8) |
               RoundToFloor(g_fCandle[owner]);
    g_hGrenades.SetValue(key, data);
    
    // Add trail effect
    int color[4] = {255, 200, 100, 255};
    TE_SetupBeamFollow(entity, g_iBeam, g_iHalo, 1.5, 10.0, 4.0, 1, color);
    TE_SendToAll();
    
    PrintToChat(owner, "\x04[FW]\x01 %s thrown!", g_TypeNames[g_eType[owner]]);
}

public void OnEntityDestroyed(int entity)
{
    if (!IsValidEntity(entity))
        return;
    
    char classname[32];
    GetEntityClassname(entity, classname, sizeof(classname));
    if (!StrEqual(classname, "npc_grenade_frag"))
        return;
    
    // Check if this was a firework grenade
    char key[16];
    IntToString(EntIndexToEntRef(entity), key, sizeof(key));
    
    int data;
    if (!g_hGrenades.GetValue(key, data))
        return;
    
    g_hGrenades.Remove(key);
    
    // Unpack settings
    FireworkType type = view_as<FireworkType>((data >> 16) & 0xFF);
    FireworkColor color = view_as<FireworkColor>((data >> 8) & 0xFF);
    float candle = float(data & 0xFF);
    
    // Get explosion position and launch firework
    float pos[3];
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
    LaunchFirework(pos, type, color, candle);
}

void LaunchFirework(float pos[3], FireworkType type, FireworkColor color, float candle)
{
    // Initial sparks and sound
    CreateLaunchSparks(pos);
    EmitSoundToAll("weapons/flaregun/fire.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO,
        SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_HIGH, _, pos);
    
    // Roman Candle starts immediately at ground level
    if (type == FW_ROMAN_CANDLE)
    {
        ExecuteFirework(pos, type, color, candle);
        return;
    }
    
    // Calculate launch direction (mostly up with slight random spread)
    float dir[3];
    dir[0] = GetRandomFloat(-0.2, 0.2);
    dir[1] = GetRandomFloat(-0.2, 0.2);
    dir[2] = 1.0;
    NormalizeVector(dir, dir);
    
    // Find max safe height (ceiling/skybox detection)
    float maxHeight = GetMaxFlightHeight(pos, dir);
    
    // Create visible firework projectile
    int fw = CreateEntityByName("env_sprite");
    if (!IsValidEntity(fw))
    {
        ExecuteFirework(pos, type, color, candle);
        return;
    }
    
    // Configure sprite
    DispatchKeyValue(fw, "model", "sprites/glow01.vmt");
    DispatchKeyValue(fw, "rendermode", "5");
    DispatchKeyValue(fw, "renderamt", "255");
    DispatchKeyValue(fw, "rendercolor", "255 220 100");
    DispatchKeyValue(fw, "scale", "0.8");
    DispatchKeyValue(fw, "spawnflags", "1");
    TeleportEntity(fw, pos, NULL_VECTOR, NULL_VECTOR);
    DispatchSpawn(fw);
    AcceptEntityInput(fw, "ShowSprite");
    TrackEntity(fw);
    
    // Calculate velocity
    float vel[3];
    vel[0] = dir[0] * LAUNCH_SPEED;
    vel[1] = dir[1] * LAUNCH_SPEED;
    vel[2] = dir[2] * LAUNCH_SPEED;
    
    // Pack all flight data
    DataPack pack = new DataPack();
    pack.WriteCell(EntIndexToEntRef(fw));
    pack.WriteFloat(pos[0]);
    pack.WriteFloat(pos[1]);
    pack.WriteFloat(pos[2]);
    pack.WriteFloat(vel[0]);
    pack.WriteFloat(vel[1]);
    pack.WriteFloat(vel[2]);
    pack.WriteFloat(0.0);  // elapsed time
    pack.WriteFloat(GetRandomFloat(FLIGHT_TIME_MIN, FLIGHT_TIME_MAX));
    pack.WriteCell(view_as<int>(type));
    pack.WriteCell(view_as<int>(color));
    pack.WriteFloat(candle);
    pack.WriteFloat(maxHeight);
    
    CreateTimer(0.04, Timer_Flight, pack, TIMER_REPEAT | TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
    
    // Add trail to projectile
    int trailColor[4] = {255, 200, 50, 255};
    TE_SetupBeamFollow(fw, g_iBeam, g_iHalo, 2.5, 12.0, 3.0, 1, trailColor);
    TE_SendToAll();
}

float GetMaxFlightHeight(float pos[3], float dir[3])
{
    // Trace upward to find ceiling/skybox
    float endPos[3];
    endPos[0] = pos[0] + dir[0] * 2000.0;
    endPos[1] = pos[1] + dir[1] * 2000.0;
    endPos[2] = pos[2] + dir[2] * 2000.0;
    
    Handle trace = TR_TraceRayEx(pos, endPos, MASK_SOLID|MASK_WATER, RayType_EndPoint);
    
    if (TR_DidHit(trace))
    {
        float hitPos[3];
        TR_GetEndPosition(hitPos, trace);
        float dist = GetVectorDistance(pos, hitPos);
        CloseHandle(trace);
        
        // Check if outside world (skybox)
        int contents = TR_PointOutsideWorld(hitPos) ? 1 : 0;
        
        // Return height with buffer for explosion
        if (contents || dist > 1500.0)
            return hitPos[2] - 100.0;
        
        return hitPos[2] - 50.0;
    }
    
    CloseHandle(trace);
    return pos[2] + 1500.0;  // Default if no hit
}

bool CheckCeilingCollision(float pos[3], float lastPos[3])
{
    // Check if outside world
    if (TR_PointOutsideWorld(pos))
        return true;
    
    // Trace from last position to current
    Handle trace = TR_TraceRayEx(lastPos, pos, MASK_SOLID, RayType_EndPoint);
    bool hit = TR_DidHit(trace);
    
    if (hit)
    {
        // Store hit position for use by caller
        TR_GetEndPosition(g_vTraceHitPos, trace);
    }
    
    CloseHandle(trace);
    return hit;
}

bool IsPositionValid(float pos[3])
{
    // Check if position is inside solid geometry
    Handle trace = TR_TraceRayEx(pos, pos, MASK_SOLID, RayType_EndPoint);
    bool startSolid = TR_StartSolid(trace);
    CloseHandle(trace);
    return !startSolid;
}


public Action Timer_Flight(Handle timer, DataPack pack)
{
    pack.Reset();
    
    // Read packed data
    int ref = pack.ReadCell();
    int fw = EntRefToEntIndex(ref);
    
    float startPos[3], vel[3];
    startPos[0] = pack.ReadFloat();
    startPos[1] = pack.ReadFloat();
    startPos[2] = pack.ReadFloat();
    vel[0] = pack.ReadFloat();
    vel[1] = pack.ReadFloat();
    vel[2] = pack.ReadFloat();
    
    float elapsed = pack.ReadFloat();
    float flightTime = pack.ReadFloat();
    FireworkType type = view_as<FireworkType>(pack.ReadCell());
    FireworkColor color = view_as<FireworkColor>(pack.ReadCell());
    float candle = pack.ReadFloat();
    float maxHeight = pack.ReadFloat();
    
    // Get last position for collision detection
    float lastPos[3];
    if (IsValidEntity(fw))
        GetEntPropVector(fw, Prop_Send, "m_vecOrigin", lastPos);
    else
    {
        lastPos[0] = startPos[0];
        lastPos[1] = startPos[1];
        lastPos[2] = startPos[2];
    }
    
    // Update elapsed time
    elapsed += 0.04;
    
    // Calculate new position with gravity
    float pos[3];
    pos[0] = startPos[0] + vel[0] * elapsed;
    pos[1] = startPos[1] + vel[1] * elapsed;
    pos[2] = startPos[2] + vel[2] * elapsed - (300.0 * elapsed * elapsed * 0.5);
    
    // Check for early explosion conditions
    bool shouldExplode = false;
    float explodePos[3];
    explodePos[0] = pos[0];
    explodePos[1] = pos[1];
    explodePos[2] = pos[2];
    
    // Hit max height?
    if (pos[2] >= maxHeight)
    {
        shouldExplode = true;
        explodePos[2] = maxHeight;
    }
    // Hit ceiling/skybox?
    else if (CheckCeilingCollision(pos, lastPos))
    {
        shouldExplode = true;
        explodePos[0] = g_vTraceHitPos[0];
        explodePos[1] = g_vTraceHitPos[1];
        explodePos[2] = g_vTraceHitPos[2] - 30.0;
    }
    
    // Update sprite position and add sparkle effects
    if (IsValidEntity(fw) && !shouldExplode)
    {
        TeleportEntity(fw, pos, NULL_VECTOR, NULL_VECTOR);
        
        if (GetRandomFloat(0.0, 1.0) > 0.4)
        {
            TE_SetupGlowSprite(pos, g_iGlow, 0.15, GetRandomFloat(0.3, 0.6), GetRandomInt(180, 255));
            TE_SendToAll();
        }
    }
    
    // Time to explode?
    if (shouldExplode || elapsed >= flightTime)
    {
        if (IsValidEntity(fw))
        {
            UntrackEntity(fw);
            AcceptEntityInput(fw, "Kill");
        }
        ExecuteFirework(explodePos, type, color, candle);
        return Plugin_Stop;
    }
    
    // Repack data for next tick
    pack.Reset();
    pack.WriteCell(ref);
    pack.WriteFloat(startPos[0]);
    pack.WriteFloat(startPos[1]);
    pack.WriteFloat(startPos[2]);
    pack.WriteFloat(vel[0]);
    pack.WriteFloat(vel[1]);
    pack.WriteFloat(vel[2]);
    pack.WriteFloat(elapsed);
    pack.WriteFloat(flightTime);
    pack.WriteCell(view_as<int>(type));
    pack.WriteCell(view_as<int>(color));
    pack.WriteFloat(candle);
    pack.WriteFloat(maxHeight);
    
    return Plugin_Continue;
}

void ExecuteFirework(float pos[3], FireworkType type, FireworkColor color, float candle)
{
    switch (type)
    {
        case FW_CLASSIC:      FW_Classic(pos, color);
        case FW_ROMAN_CANDLE: FW_RomanCandle(pos, color, candle);
        case FW_FOUNTAIN:     FW_Fountain(pos, color);
        case FW_TWOX:         FW_TwoX(pos, color);
    }
}

// ============================================================================
// CLASSIC FIREWORK - Spherical burst with rays
// ============================================================================

void FW_Classic(float pos[3], FireworkColor fwColor)
{
    int c1[3], c2[3], c3[3];
    GetColors(fwColor, c1, c2, c3);
    
    // Explosion sound
    EmitSoundToAll("ambient/explosions/explode_8.wav", SOUND_FROM_WORLD,
        SNDCHAN_AUTO, SNDLEVEL_GUNFIRE, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, _, pos);
    
    // Central flash
    TE_SetupGlowSprite(pos, g_iGlow, 0.6, 4.0, 255);
    TE_SendToAll();
    TE_SetupGlowSprite(pos, g_iFlare, 0.4, 3.0, 255);
    TE_SendToAll();
    
    // Dynamic light
    DynLight(pos, c1[0], c1[1], c1[2], 10, 500.0, 0.6, 300.0);
    TE_SendToAll();
    
    // Explosion effect
    TE_SetupExplosion(pos, g_iHalo, 8.0, 1, TE_EXPLFLAG_NONE, 300, 200);
    TE_SendToAll();
    
    // Burst rays in all directions
    float endPos[3];
    for (int i = 0; i < CLASSIC_RAYS; i++)
    {
        // Calculate ray direction
        float angle = float(i) * (360.0 / float(CLASSIC_RAYS)) + GetRandomFloat(-15.0, 15.0);
        float pitch = GetRandomFloat(-40.0, 70.0);
        float length = GetRandomFloat(CLASSIC_RADIUS_MIN, CLASSIC_RADIUS_MAX);
        
        float radAngle = DegToRad(angle);
        float radPitch = DegToRad(pitch);
        
        endPos[0] = pos[0] + Cosine(radAngle) * Cosine(radPitch) * length;
        endPos[1] = pos[1] + Sine(radAngle) * Cosine(radPitch) * length;
        endPos[2] = pos[2] + Sine(radPitch) * length;
        
        // Cycle through colors
        int beamColor[4];
        int colorIndex = i % 3;
        if (colorIndex == 0)
        {
            beamColor[0] = c1[0]; beamColor[1] = c1[1]; beamColor[2] = c1[2];
        }
        else if (colorIndex == 1)
        {
            beamColor[0] = c2[0]; beamColor[1] = c2[1]; beamColor[2] = c2[2];
        }
        else
        {
            beamColor[0] = c3[0]; beamColor[1] = c3[1]; beamColor[2] = c3[2];
        }
        beamColor[3] = 255;
        
        // Draw beam
        float width = GetRandomFloat(6.0, 12.0);
        TE_SetupBeamPoints(pos, endPos, g_iBeam, g_iHalo, 0, 30,
            GetRandomFloat(0.6, 1.0), width, width * 0.1, 0, 0.0, beamColor, 25);
        TE_SendToAll();
        
        // Glow at end
        TE_SetupGlowSprite(endPos, g_iGlow, GetRandomFloat(0.3, 0.6),
            GetRandomFloat(0.6, 1.2), GetRandomInt(180, 255));
        TE_SendToAll();
        
        // Sparks at end
        float sparkDir[3];
        sparkDir[0] = (endPos[0] - pos[0]) * 0.3;
        sparkDir[1] = (endPos[1] - pos[1]) * 0.3;
        sparkDir[2] = (endPos[2] - pos[2]) * 0.3;
        TE_SetupSparks(endPos, sparkDir, GetRandomInt(5, 12), GetRandomInt(3, 6));
        TE_SendToAll();
    }
    
    // Random sparkles throughout explosion
    for (int i = 0; i < 60; i++)
    {
        float sparklePos[3];
        float radius = GetRandomFloat(CLASSIC_RADIUS_MIN, CLASSIC_RADIUS_MAX);
        sparklePos[0] = pos[0] + GetRandomFloat(-radius * 0.6, radius * 0.6);
        sparklePos[1] = pos[1] + GetRandomFloat(-radius * 0.6, radius * 0.6);
        sparklePos[2] = pos[2] + GetRandomFloat(-radius * 0.4, radius * 0.6);
        TE_SetupGlowSprite(sparklePos, g_iFlare, GetRandomFloat(0.2, 0.6),
            GetRandomFloat(0.3, 0.8), GetRandomInt(150, 255));
        TE_SendToAll();
    }
    
    // Schedule falling embers
    DataPack pack = new DataPack();
    pack.WriteFloat(pos[0]);
    pack.WriteFloat(pos[1]);
    pack.WriteFloat(pos[2]);
    CreateTimer(0.3, Timer_Embers, pack, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Embers(Handle timer, DataPack pack)
{
    pack.Reset();
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    
    float radius = GetRandomFloat(CLASSIC_RADIUS_MIN, CLASSIC_RADIUS_MAX);
    
    // Falling embers
    for (int i = 0; i < 20; i++)
    {
        float emberPos[3];
        emberPos[0] = pos[0] + GetRandomFloat(-radius, radius);
        emberPos[1] = pos[1] + GetRandomFloat(-radius, radius);
        emberPos[2] = pos[2] + GetRandomFloat(-80.0, 80.0);
        
        float fallDir[3];
        fallDir[0] = GetRandomFloat(-40.0, 40.0);
        fallDir[1] = GetRandomFloat(-40.0, 40.0);
        fallDir[2] = GetRandomFloat(-150.0, -80.0);
        
        TE_SetupSparks(emberPos, fallDir, GetRandomInt(2, 5), GetRandomInt(1, 3));
        TE_SendToAll();
        
        TE_SetupGlowSprite(emberPos, g_iFlare, GetRandomFloat(0.4, 0.8),
            GetRandomFloat(0.2, 0.4), GetRandomInt(120, 180));
        TE_SendToAll();
    }
    
    // Smoke puffs
    for (int i = 0; i < 4; i++)
    {
        float smokePos[3];
        smokePos[0] = pos[0] + GetRandomFloat(-100.0, 100.0);
        smokePos[1] = pos[1] + GetRandomFloat(-100.0, 100.0);
        smokePos[2] = pos[2] + GetRandomFloat(-50.0, 50.0);
        TE_SetupSmoke(smokePos, g_iSmoke, GetRandomFloat(15.0, 30.0), GetRandomInt(2, 5));
        TE_SendToAll();
    }
    
    return Plugin_Stop;
}

// ============================================================================
// ROMAN CANDLE - Continuous fountain of sparks
// ============================================================================

void FW_RomanCandle(float pos[3], FireworkColor fwColor, float duration)
{
    DataPack pack = new DataPack();
    pack.WriteFloat(pos[0]);
    pack.WriteFloat(pos[1]);
    pack.WriteFloat(pos[2]);
    pack.WriteCell(view_as<int>(fwColor));
    pack.WriteFloat(0.0);  // elapsed
    pack.WriteFloat(duration);
    
    CreateTimer(ROMAN_CANDLE_TICK, Timer_RomanCandle, pack,
        TIMER_REPEAT | TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
    
    // Initial smoke puff
    TE_SetupSmoke(pos, g_iSmoke, 30.0, 5);
    TE_SendToAll();
    
    EmitSoundToAll("weapons/flaregun/fire.wav", SOUND_FROM_WORLD,
        SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8, SNDPITCH_LOW, _, pos);
}

public Action Timer_RomanCandle(Handle timer, DataPack pack)
{
    pack.Reset();
    
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    FireworkColor fwColor = view_as<FireworkColor>(pack.ReadCell());
    float elapsed = pack.ReadFloat();
    float duration = pack.ReadFloat();
    
    elapsed += ROMAN_CANDLE_TICK;
    
    // Finished?
    if (elapsed >= duration)
    {
        TE_SetupSmoke(pos, g_iSmoke, 50.0, 8);
        TE_SendToAll();
        return Plugin_Stop;
    }
    
    int c1[3], c2[3], c3[3];
    GetColors(fwColor, c1, c2, c3);
    
    // Spray sparks upward
    for (int i = 0; i < 8; i++)
    {
        float sparkPos[3], sparkDir[3];
        sparkPos[0] = pos[0] + GetRandomFloat(-10.0, 10.0);
        sparkPos[1] = pos[1] + GetRandomFloat(-10.0, 10.0);
        sparkPos[2] = pos[2] + GetRandomFloat(0.0, 20.0);
        
        sparkDir[0] = GetRandomFloat(-30.0, 30.0);
        sparkDir[1] = GetRandomFloat(-30.0, 30.0);
        sparkDir[2] = GetRandomFloat(ROMAN_CANDLE_HEIGHT * 0.6, ROMAN_CANDLE_HEIGHT);
        
        TE_SetupSparks(sparkPos, sparkDir, GetRandomInt(3, 6), GetRandomInt(2, 4));
        TE_SendToAll();
    }
    
    // Pick random color for this tick
    int useColor[3];
    int colorChoice = GetRandomInt(0, 2);
    if (colorChoice == 0)
    {
        useColor[0] = c1[0]; useColor[1] = c1[1]; useColor[2] = c1[2];
    }
    else if (colorChoice == 1)
    {
        useColor[0] = c2[0]; useColor[1] = c2[1]; useColor[2] = c2[2];
    }
    else
    {
        useColor[0] = c3[0]; useColor[1] = c3[1]; useColor[2] = c3[2];
    }
    
    // Base glow
    TE_SetupGlowSprite(pos, g_iGlow, ROMAN_CANDLE_TICK + 0.05, GetRandomFloat(0.8, 1.5), 255);
    TE_SendToAll();
    
    // Rising glows
    for (int i = 0; i < 3; i++)
    {
        float glowPos[3];
        glowPos[0] = pos[0] + GetRandomFloat(-15.0, 15.0);
        glowPos[1] = pos[1] + GetRandomFloat(-15.0, 15.0);
        glowPos[2] = pos[2] + GetRandomFloat(20.0, ROMAN_CANDLE_HEIGHT * 0.8);
        TE_SetupGlowSprite(glowPos, g_iFlare, GetRandomFloat(0.1, 0.2),
            GetRandomFloat(0.3, 0.6), GetRandomInt(180, 255));
        TE_SendToAll();
    }
    
    // Dynamic light at base
    DynLight(pos, useColor[0], useColor[1], useColor[2], 6, 150.0, ROMAN_CANDLE_TICK + 0.02, 100.0);
    TE_SendToAll();
    
    // Occasional crackle sound
    if (GetRandomFloat(0.0, 1.0) > 0.8)
    {
        char sounds[][] = {"weapons/stunstick/spark1.wav", "weapons/stunstick/spark2.wav"};
        EmitSoundToAll(sounds[GetRandomInt(0, 1)], SOUND_FROM_WORLD,
            SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS,
            GetRandomFloat(0.3, 0.5), GetRandomInt(90, 120), _, pos);
    }
    
    // Update elapsed time
    pack.Reset();
    pack.WriteFloat(pos[0]);
    pack.WriteFloat(pos[1]);
    pack.WriteFloat(pos[2]);
    pack.WriteCell(view_as<int>(fwColor));
    pack.WriteFloat(elapsed);
    pack.WriteFloat(duration);
    
    return Plugin_Continue;
}

// ============================================================================
// FOUNTAIN - Particles launch up and fall with gravity
// ============================================================================

void FW_Fountain(float pos[3], FireworkColor fwColor)
{
    int c1[3], c2[3], c3[3];
    GetColors(fwColor, c1, c2, c3);
    
    EmitSoundToAll("ambient/explosions/explode_8.wav", SOUND_FROM_WORLD,
        SNDCHAN_AUTO, SNDLEVEL_GUNFIRE, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, _, pos);
    
    TE_SetupGlowSprite(pos, g_iGlow, 0.5, 3.0, 255);
    TE_SendToAll();
    
    DynLight(pos, c1[0], c1[1], c1[2], 8, 400.0, 0.5, 200.0);
    TE_SendToAll();
    
    // Launch particles in random directions
    for (int i = 0; i < FOUNTAIN_PARTICLES; i++)
    {
        DataPack pack = new DataPack();
        pack.WriteFloat(pos[0]);
        pack.WriteFloat(pos[1]);
        pack.WriteFloat(pos[2]);
        
        // Random upward velocity
        pack.WriteFloat(GetRandomFloat(-100.0, 100.0));  // vx
        pack.WriteFloat(GetRandomFloat(-100.0, 100.0));  // vy
        pack.WriteFloat(GetRandomFloat(FOUNTAIN_SPEED * 0.7, FOUNTAIN_SPEED));  // vz
        pack.WriteFloat(0.0);  // elapsed
        
        // Random color
        int colorChoice = GetRandomInt(0, 2);
        if (colorChoice == 0)
        {
            pack.WriteCell(c1[0]); pack.WriteCell(c1[1]); pack.WriteCell(c1[2]);
        }
        else if (colorChoice == 1)
        {
            pack.WriteCell(c2[0]); pack.WriteCell(c2[1]); pack.WriteCell(c2[2]);
        }
        else
        {
            pack.WriteCell(c3[0]); pack.WriteCell(c3[1]); pack.WriteCell(c3[2]);
        }
        
        CreateTimer(0.05, Timer_FountainParticle, pack,
            TIMER_REPEAT | TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_FountainParticle(Handle timer, DataPack pack)
{
    pack.Reset();
    
    float startPos[3], vel[3];
    startPos[0] = pack.ReadFloat();
    startPos[1] = pack.ReadFloat();
    startPos[2] = pack.ReadFloat();
    vel[0] = pack.ReadFloat();
    vel[1] = pack.ReadFloat();
    vel[2] = pack.ReadFloat();
    float elapsed = pack.ReadFloat();
    
    int color[3];
    color[0] = pack.ReadCell();
    color[1] = pack.ReadCell();
    color[2] = pack.ReadCell();
    
    elapsed += 0.05;
    
    if (elapsed >= FOUNTAIN_DURATION)
        return Plugin_Stop;
    
    // Calculate position with gravity
    float pos[3];
    pos[0] = startPos[0] + vel[0] * elapsed;
    pos[1] = startPos[1] + vel[1] * elapsed;
    pos[2] = startPos[2] + vel[2] * elapsed - (FOUNTAIN_GRAVITY * elapsed * elapsed * 0.5);
    
    // Stop if fallen below start
    if (pos[2] < startPos[2] - 50.0)
        return Plugin_Stop;
    
    // Stop if outside world or in solid
    if (TR_PointOutsideWorld(pos) || !IsPositionValid(pos))
        return Plugin_Stop;
    
    // Glowing particle
    TE_SetupGlowSprite(pos, g_iFlare, 0.08, GetRandomFloat(0.4, 0.8), GetRandomInt(200, 255));
    TE_SendToAll();
    
    // Trailing sparks
    if (GetRandomFloat(0.0, 1.0) > 0.5)
    {
        float sparkDir[3];
        sparkDir[0] = GetRandomFloat(-20.0, 20.0);
        sparkDir[1] = GetRandomFloat(-20.0, 20.0);
        sparkDir[2] = GetRandomFloat(-50.0, -20.0);
        TE_SetupSparks(pos, sparkDir, 2, 1);
        TE_SendToAll();
    }
    
    // Repack data
    pack.Reset();
    pack.WriteFloat(startPos[0]);
    pack.WriteFloat(startPos[1]);
    pack.WriteFloat(startPos[2]);
    pack.WriteFloat(vel[0]);
    pack.WriteFloat(vel[1]);
    pack.WriteFloat(vel[2]);
    pack.WriteFloat(elapsed);
    pack.WriteCell(color[0]);
    pack.WriteCell(color[1]);
    pack.WriteCell(color[2]);
    
    return Plugin_Continue;
}

// ============================================================================
// TWOX - Multi-stage chain reaction
// ============================================================================

void FW_TwoX(float pos[3], FireworkColor fwColor)
{
    int c1[3], c2[3], c3[3];
    GetColors(fwColor, c1, c2, c3);
    
    // Initial burst
    EmitSoundToAll("ambient/explosions/explode_4.wav", SOUND_FROM_WORLD,
        SNDCHAN_AUTO, SNDLEVEL_GUNFIRE, SND_NOFLAGS, 0.8, SNDPITCH_HIGH, _, pos);
    
    TE_SetupGlowSprite(pos, g_iGlow, 0.4, 2.5, 255);
    TE_SendToAll();
    
    DynLight(pos, c1[0], c1[1], c1[2], 6, 250.0, 0.4, 150.0);
    TE_SendToAll();
    
    // Initial rays
    for (int i = 0; i < 12; i++)
    {
        float angle = float(i) * 30.0;
        float radAngle = DegToRad(angle);
        float pitch = GetRandomFloat(-20.0, 40.0);
        float radPitch = DegToRad(pitch);
        float length = GetRandomFloat(80.0, 150.0);
        
        float endPos[3];
        endPos[0] = pos[0] + Cosine(radAngle) * Cosine(radPitch) * length;
        endPos[1] = pos[1] + Sine(radAngle) * Cosine(radPitch) * length;
        endPos[2] = pos[2] + Sine(radPitch) * length;
        
        int beamColor[4];
        beamColor[0] = c1[0];
        beamColor[1] = c1[1];
        beamColor[2] = c1[2];
        beamColor[3] = 255;
        
        TE_SetupBeamPoints(pos, endPos, g_iBeam, g_iHalo, 0, 30, 0.5, 5.0, 1.0, 0, 0.0, beamColor, 20);
        TE_SendToAll();
    }
    
    // Schedule secondary explosions
    for (int i = 0; i < 2; i++)
    {
        DataPack pack = new DataPack();
        pack.WriteFloat(pos[0]);
        pack.WriteFloat(pos[1]);
        pack.WriteFloat(pos[2]);
        pack.WriteCell(view_as<int>(fwColor));
        pack.WriteCell(i);
        
        CreateTimer(0.3 + (float(i) * 0.25), Timer_TwoXSecondary, pack,
            TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_TwoXSecondary(Handle timer, DataPack pack)
{
    pack.Reset();
    
    float center[3];
    center[0] = pack.ReadFloat();
    center[1] = pack.ReadFloat();
    center[2] = pack.ReadFloat();
    FireworkColor fwColor = view_as<FireworkColor>(pack.ReadCell());
    int index = pack.ReadCell();
    
    int c1[3], c2[3], c3[3];
    GetColors(fwColor, c1, c2, c3);
    
    // Calculate position offset from center
    float angle = float(index) * 180.0 + GetRandomFloat(-30.0, 30.0);
    float radAngle = DegToRad(angle);
    
    float pos[3];
    pos[0] = center[0] + Cosine(radAngle) * TWOX_SPREAD;
    pos[1] = center[1] + Sine(radAngle) * TWOX_SPREAD;
    pos[2] = center[2] + GetRandomFloat(-30.0, 80.0);
    
    // Validate position
    if (TR_PointOutsideWorld(pos) || !IsPositionValid(pos))
    {
        pos[0] = center[0] + Cosine(radAngle) * (TWOX_SPREAD * 0.5);
        pos[1] = center[1] + Sine(radAngle) * (TWOX_SPREAD * 0.5);
        pos[2] = center[2];
    }
    
    // Secondary burst
    EmitSoundToAll("ambient/explosions/explode_8.wav", SOUND_FROM_WORLD,
        SNDCHAN_AUTO, SNDLEVEL_GUNFIRE, SND_NOFLAGS, 0.9, SNDPITCH_NORMAL, _, pos);
    
    TE_SetupGlowSprite(pos, g_iGlow, 0.5, 3.0, 255);
    TE_SendToAll();
    
    DynLight(pos, c2[0], c2[1], c2[2], 8, 350.0, 0.5, 200.0);
    TE_SendToAll();
    
    // Secondary rays
    for (int i = 0; i < 16; i++)
    {
        float rayAngle = float(i) * 22.5 + GetRandomFloat(-10.0, 10.0);
        float radRayAngle = DegToRad(rayAngle);
        float pitch = GetRandomFloat(-30.0, 60.0);
        float radPitch = DegToRad(pitch);
        float length = GetRandomFloat(180.0, 320.0);
        
        float endPos[3];
        endPos[0] = pos[0] + Cosine(radRayAngle) * Cosine(radPitch) * length;
        endPos[1] = pos[1] + Sine(radRayAngle) * Cosine(radPitch) * length;
        endPos[2] = pos[2] + Sine(radPitch) * length;
        
        int beamColor[4];
        if (i % 2 == 0)
        {
            beamColor[0] = c2[0]; beamColor[1] = c2[1]; beamColor[2] = c2[2];
        }
        else
        {
            beamColor[0] = c3[0]; beamColor[1] = c3[1]; beamColor[2] = c3[2];
        }
        beamColor[3] = 255;
        
        TE_SetupBeamPoints(pos, endPos, g_iBeam, g_iHalo, 0, 30, 0.7, 7.0, 1.0, 0, 0.0, beamColor, 22);
        TE_SendToAll();
        
        TE_SetupGlowSprite(endPos, g_iFlare, 0.3, 0.6, GetRandomInt(180, 255));
        TE_SendToAll();
    }
    
    // Schedule tertiary explosions
    for (int j = 0; j < 2; j++)
    {
        DataPack tertiaryPack = new DataPack();
        tertiaryPack.WriteFloat(pos[0]);
        tertiaryPack.WriteFloat(pos[1]);
        tertiaryPack.WriteFloat(pos[2]);
        tertiaryPack.WriteCell(view_as<int>(fwColor));
        tertiaryPack.WriteCell(j);
        
        CreateTimer(0.4 + (float(j) * 0.2), Timer_TwoXTertiary, tertiaryPack,
            TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
    }
    
    return Plugin_Stop;
}

public Action Timer_TwoXTertiary(Handle timer, DataPack pack)
{
    pack.Reset();
    
    float center[3];
    center[0] = pack.ReadFloat();
    center[1] = pack.ReadFloat();
    center[2] = pack.ReadFloat();
    FireworkColor fwColor = view_as<FireworkColor>(pack.ReadCell());
    int index = pack.ReadCell();
    
    int c1[3], c2[3], c3[3];
    GetColors(fwColor, c1, c2, c3);
    
    // Calculate position
    float angle = float(index) * 180.0 + 90.0 + GetRandomFloat(-20.0, 20.0);
    float radAngle = DegToRad(angle);
    
    float pos[3];
    pos[0] = center[0] + Cosine(radAngle) * TWOX_TERTIARY_SPREAD;
    pos[1] = center[1] + Sine(radAngle) * TWOX_TERTIARY_SPREAD;
    pos[2] = center[2] + GetRandomFloat(40.0, 100.0);
    
    // Validate position
    if (TR_PointOutsideWorld(pos) || !IsPositionValid(pos))
    {
        pos[0] = center[0] + Cosine(radAngle) * (TWOX_TERTIARY_SPREAD * 0.5);
        pos[1] = center[1] + Sine(radAngle) * (TWOX_TERTIARY_SPREAD * 0.5);
        pos[2] = center[2];
    }
    
    // Tertiary burst
    EmitSoundToAll("ambient/explosions/explode_4.wav", SOUND_FROM_WORLD,
        SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.7, GetRandomInt(100, 140), _, pos);
    
    TE_SetupGlowSprite(pos, g_iGlow, 0.4, 2.0, 255);
    TE_SendToAll();
    
    DynLight(pos, c3[0], c3[1], c3[2], 5, 200.0, 0.3, 150.0);
    TE_SendToAll();
    
    // Spark bursts
    for (int i = 0; i < 8; i++)
    {
        float sparkDir[3];
        sparkDir[0] = GetRandomFloat(-100.0, 100.0);
        sparkDir[1] = GetRandomFloat(-100.0, 100.0);
        sparkDir[2] = GetRandomFloat(-50.0, 100.0);
        TE_SetupSparks(pos, sparkDir, GetRandomInt(5, 10), GetRandomInt(3, 5));
        TE_SendToAll();
    }
    
    // Glows
    for (int i = 0; i < 10; i++)
    {
        float glowPos[3];
        glowPos[0] = pos[0] + GetRandomFloat(-60.0, 60.0);
        glowPos[1] = pos[1] + GetRandomFloat(-60.0, 60.0);
        glowPos[2] = pos[2] + GetRandomFloat(-40.0, 60.0);
        TE_SetupGlowSprite(glowPos, g_iFlare, GetRandomFloat(0.2, 0.4),
            GetRandomFloat(0.3, 0.6), GetRandomInt(180, 255));
        TE_SendToAll();
    }
    
    return Plugin_Stop;
}

void CreateLaunchSparks(float pos[3])
{
    // Upward sparks
    TE_SetupSparks(pos, view_as<float>({0.0, 0.0, 150.0}), 50, 15);
    TE_SendToAll();
    
    // Spread sparks
    for (int i = 0; i < 4; i++)
    {
        float dir[3];
        dir[0] = GetRandomFloat(-100.0, 100.0);
        dir[1] = GetRandomFloat(-100.0, 100.0);
        dir[2] = GetRandomFloat(50.0, 150.0);
        TE_SetupSparks(pos, dir, 20, 8);
        TE_SendToAll();
    }
    
    // Smoke puffs
    for (int i = 0; i < 3; i++)
    {
        float smokePos[3];
        smokePos[0] = pos[0] + GetRandomFloat(-20.0, 20.0);
        smokePos[1] = pos[1] + GetRandomFloat(-20.0, 20.0);
        smokePos[2] = pos[2] + GetRandomFloat(-10.0, 10.0);
        TE_SetupSmoke(smokePos, g_iSmoke, GetRandomFloat(25.0, 40.0), 8);
        TE_SendToAll();
    }
    
    // Flash
    DynLight(pos, 255, 220, 150, 8, 200.0, 0.4, 100.0);
    TE_SendToAll();
    
    TE_SetupGlowSprite(pos, g_iGlow, 0.3, 2.0, 255);
    TE_SendToAll();
}

void GetColors(FireworkColor fwColor, int c1[3], int c2[3], int c3[3])
{
    if (fwColor == FWC_RANDOM)
    {
        // Pick 3 different random colors
        int i1 = GetRandomInt(1, view_as<int>(FWC_COUNT) - 1);
        int i2 = (i1 + GetRandomInt(1, 4)) % (view_as<int>(FWC_COUNT) - 1) + 1;
        int i3 = (i2 + GetRandomInt(1, 4)) % (view_as<int>(FWC_COUNT) - 1) + 1;
        
        c1[0] = g_Colors[i1][0]; c1[1] = g_Colors[i1][1]; c1[2] = g_Colors[i1][2];
        c2[0] = g_Colors[i2][0]; c2[1] = g_Colors[i2][1]; c2[2] = g_Colors[i2][2];
        c3[0] = g_Colors[i3][0]; c3[1] = g_Colors[i3][1]; c3[2] = g_Colors[i3][2];
    }
    else
    {
        // Use selected color with brightness variations
        int idx = view_as<int>(fwColor);
        
        // Primary - exact color
        c1[0] = g_Colors[idx][0];
        c1[1] = g_Colors[idx][1];
        c1[2] = g_Colors[idx][2];
        
        // Secondary - brighter
        c2[0] = (g_Colors[idx][0] + 40 > 255) ? 255 : g_Colors[idx][0] + 40;
        c2[1] = (g_Colors[idx][1] + 40 > 255) ? 255 : g_Colors[idx][1] + 40;
        c2[2] = (g_Colors[idx][2] + 40 > 255) ? 255 : g_Colors[idx][2] + 40;
        
        // Tertiary - dimmer
        c3[0] = (g_Colors[idx][0] - 30 < 20) ? 20 : g_Colors[idx][0] - 30;
        c3[1] = (g_Colors[idx][1] - 30 < 20) ? 20 : g_Colors[idx][1] - 30;
        c3[2] = (g_Colors[idx][2] - 30 < 20) ? 20 : g_Colors[idx][2] - 30;
    }
}

void TrackEntity(int entity)
{
    int ref = EntIndexToEntRef(entity);
    if (g_hEntities.FindValue(ref) == -1)
        g_hEntities.Push(ref);
}

void UntrackEntity(int entity)
{
    int ref = EntIndexToEntRef(entity);
    int index = g_hEntities.FindValue(ref);
    if (index != -1)
        g_hEntities.Erase(index);
}

void CleanupEntities()
{
    for (int i = 0; i < g_hEntities.Length; i++)
    {
        int entity = EntRefToEntIndex(g_hEntities.Get(i));
        if (IsValidEntity(entity))
            AcceptEntityInput(entity, "Kill");
    }
    g_hEntities.Clear();
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

void DynLight(float pos[3], int r, int g, int b, int exponent, float radius, float time, float decay)
{
    TE_Start("Dynamic Light");
    TE_WriteVector("m_vecOrigin", pos);
    TE_WriteNum("r", r);
    TE_WriteNum("g", g);
    TE_WriteNum("b", b);
    TE_WriteNum("exponent", exponent);
    TE_WriteFloat("m_fRadius", radius);
    TE_WriteFloat("m_fTime", time);
    TE_WriteFloat("m_fDecay", decay);
}
