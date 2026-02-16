/**
 * HL2DM Grenade Firework 1.2.0
 * 
 * Commands:
 *   /firework - Your next grenade will be a firework. (30s timeout)
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.2.0"

// Firework configuration
#define FIREWORK_LAUNCH_SPEED 1000.0
#define FIREWORK_FLIGHT_TIME_MIN 1.0
#define FIREWORK_FLIGHT_TIME_MAX 1.5
#define FIREWORK_BURST_RAYS 32
#define FIREWORK_BURST_RADIUS_MIN 400.0
#define FIREWORK_BURST_RADIUS_MAX 10000.0

// Sprite/Material indices
int g_iBeamSprite;
int g_iHaloSprite;
int g_iGlowSprite;
int g_iSmokeSprite;
int g_iFlareSprite;

// Player firework state
bool g_bFireworkActive[MAXPLAYERS + 1];
Handle g_hFireworkTimer[MAXPLAYERS + 1];

// Grenade tracking
StringMap g_hFireworkGrenades;

// Colors for firework bursts (RGB)
int g_FireworkColors[][] = {
    {255, 50, 50},      // Red
    {50, 255, 50},      // Green
    {50, 50, 255},      // Blue
    {255, 255, 50},     // Yellow
    {255, 50, 255},     // Magenta
    {50, 255, 255},     // Cyan
    {255, 150, 50},     // Orange
    {255, 255, 255},    // White
    {255, 100, 150},    // Pink
    {150, 255, 100},    // Lime
    {100, 150, 255},    // Sky Blue
    {255, 200, 100}     // Gold
};

public Plugin myinfo = {
    name = "HL2DM Firework Grenades",
    author = "Moxx",
    description = "Turn your next grenade into firework.",
    version = PLUGIN_VERSION,
    url = "https://moxx.me"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_firework", Command_Firework, "Activate firework mode for your next grenade");
    RegConsoleCmd("firework", Command_Firework, "Activate firework mode for your next grenade");
    
    g_hFireworkGrenades = new StringMap();
    
    HookEvent("player_spawn", Event_PlayerSpawn);
    
    PrintToServer("[Firework] Plugin loaded successfully!");
}

public void OnMapStart()
{
    g_iBeamSprite = PrecacheModel("sprites/laser.vmt");
    g_iHaloSprite = PrecacheModel("sprites/halo01.vmt");
    g_iGlowSprite = PrecacheModel("sprites/glow01.vmt");
    g_iSmokeSprite = PrecacheModel("sprites/steam1.vmt");
    g_iFlareSprite = PrecacheModel("sprites/light_glow02.vmt");
    
    PrecacheModel("sprites/blueflare1.vmt");
    PrecacheModel("sprites/redglow1.vmt");
    PrecacheModel("sprites/orangeflare1.vmt");
    PrecacheModel("sprites/plasmabeam.vmt");
    
    PrecacheSound("weapons/flaregun/fire.wav");
    PrecacheSound("ambient/explosions/explode_8.wav");
    PrecacheSound("ambient/explosions/explode_4.wav");
    PrecacheSound("ambient/explosions/explode_3.wav");
    PrecacheSound("weapons/mortar/mortar_explode1.wav");
    PrecacheSound("weapons/stunstick/spark1.wav");
    PrecacheSound("weapons/stunstick/spark2.wav");
    
    g_hFireworkGrenades.Clear();
    
    // Clear all player states and timers on map change
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bFireworkActive[i] = false;
        g_hFireworkTimer[i] = null;
    }
}

public void OnClientDisconnect(int client)
{
    g_bFireworkActive[client] = false;
    ClearFireworkTimer(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        g_bFireworkActive[client] = false;
        ClearFireworkTimer(client);
    }
}

public Action Command_Firework(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;
    
    if (!IsPlayerAlive(client))
    {
        PrintToChat(client, "\x04[Firework]\x01 You must be alive to use this command!");
        return Plugin_Handled;
    }
    
    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(activeWeapon))
    {
        PrintToChat(client, "\x04[Firework]\x01 You must have a grenade in hand!");
        return Plugin_Handled;
    }
    
    char weaponClass[64];
    GetEntityClassname(activeWeapon, weaponClass, sizeof(weaponClass));
    
    if (!StrEqual(weaponClass, "weapon_frag"))
    {
        PrintToChat(client, "\x04[Firework]\x01 You must have a grenade in hand!");
        return Plugin_Handled;
    }
    
    int ammoType = GetEntProp(activeWeapon, Prop_Send, "m_iPrimaryAmmoType");
    if (ammoType < 0)
    {
        PrintToChat(client, "\x04[Firework]\x01 Error reading ammo type!");
        return Plugin_Handled;
    }
    
    int ammoCount = GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);
    
    if (ammoCount < 1)
    {
        PrintToChat(client, "\x04[Firework]\x01 You need at least 1 grenade!");
        return Plugin_Handled;
    }
    
    if (g_bFireworkActive[client])
    {
        g_bFireworkActive[client] = false;
        ClearFireworkTimer(client);
        PrintToChat(client, "\x04[Firework]\x01 Firework mode \x07DEACTIVATED\x01.");
    }
    else
    {
        g_bFireworkActive[client] = true;
        ClearFireworkTimer(client);
        g_hFireworkTimer[client] = CreateTimer(30.0, Timer_FireworkExpire, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
        PrintToChat(client, "\x04[Firework]\x01 Firework mode \x04ON\x01! Your next grenade will be a firework!");
        CreatePlayerGlow(client);
    }
    
    return Plugin_Handled;
}

void CreatePlayerGlow(int client)
{
    float pos[3];
    GetClientAbsOrigin(client, pos);
    pos[2] += 40.0;
    
    TE_SetupGlowSprite(pos, g_iGlowSprite, 0.5, 1.0, 200);
    TE_SendToClient(client);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "npc_grenade_frag"))
    {
        SDKHook(entity, SDKHook_SpawnPost, OnGrenadeSpawned);
    }
}

public void OnGrenadeSpawned(int entity)
{
    if (!IsValidEntity(entity))
        return;
    
    int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    
    if (!IsValidClient(owner))
        return;
    
    if (!g_bFireworkActive[owner])
        return;
    
    g_bFireworkActive[owner] = false;
    ClearFireworkTimer(owner);
    
    char key[16];
    int ref = EntIndexToEntRef(entity);
    IntToString(ref, key, sizeof(key));
    g_hFireworkGrenades.SetValue(key, true);
    
    // Add trail effect to the grenade
    CreateGrenadeTrail(entity);
    
    PrintToChat(owner, "\x04[Firework]\x01 Firework grenade thrown!");
}

void CreateGrenadeTrail(int entity)
{
    int color[4] = {255, 200, 100, 255};
    TE_SetupBeamFollow(entity, g_iBeamSprite, g_iHaloSprite, 1.5, 10.0, 4.0, 1, color);
    TE_SendToAll();
}

public void OnEntityDestroyed(int entity)
{
    if (!IsValidEntity(entity))
        return;
    
    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));
    
    if (!StrEqual(classname, "npc_grenade_frag"))
        return;
    
    char key[16];
    int ref = EntIndexToEntRef(entity);
    IntToString(ref, key, sizeof(key));
    
    bool isFirework;
    if (!g_hFireworkGrenades.GetValue(key, isFirework))
        return;
    
    if (!isFirework)
        return;
    
    g_hFireworkGrenades.Remove(key);
    
    float grenadePos[3];
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", grenadePos);
    
    LaunchFireworkFromExplosion(grenadePos);
}

void LaunchFireworkFromExplosion(float explosionPos[3])
{
    CreateLaunchSparks(explosionPos);
    
    EmitSoundToAll("weapons/flaregun/fire.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_HIGH, _, explosionPos);
    
    float launchDir[3];
    launchDir[0] = GetRandomFloat(-0.25, 0.25);
    launchDir[1] = GetRandomFloat(-0.25, 0.25);
    launchDir[2] = 1.0;
    NormalizeVector(launchDir, launchDir);
    
    LaunchFirework(explosionPos, launchDir);
}

void CreateLaunchSparks(float pos[3])
{
    // Big spark shower
    TE_SetupSparks(pos, view_as<float>({0.0, 0.0, 150.0}), 50, 15);
    TE_SendToAll();
    
    // More sparks in random directions
    for (int i = 0; i < 4; i++)
    {
        float dir[3];
        dir[0] = GetRandomFloat(-100.0, 100.0);
        dir[1] = GetRandomFloat(-100.0, 100.0);
        dir[2] = GetRandomFloat(50.0, 150.0);
        TE_SetupSparks(pos, dir, 20, 8);
        TE_SendToAll();
    }
    
    // Multiple smoke puffs
    for (int i = 0; i < 3; i++)
    {
        float smokePos[3];
        smokePos[0] = pos[0] + GetRandomFloat(-20.0, 20.0);
        smokePos[1] = pos[1] + GetRandomFloat(-20.0, 20.0);
        smokePos[2] = pos[2] + GetRandomFloat(-10.0, 10.0);
        TE_SetupSmoke(smokePos, g_iSmokeSprite, GetRandomFloat(25.0, 40.0), 8);
        TE_SendToAll();
    }
    
    // Bright flash
    TE_SetupDynamicLight(pos, 255, 220, 150, 8, 200.0, 0.4, 100.0);
    TE_SendToAll();
    
    // Ground glow
    TE_SetupGlowSprite(pos, g_iGlowSprite, 0.3, 2.0, 255);
    TE_SendToAll();
}

void LaunchFirework(float startPos[3], float direction[3])
{
    int firework = CreateEntityByName("env_sprite");
    
    float flightTime = GetRandomFloat(FIREWORK_FLIGHT_TIME_MIN, FIREWORK_FLIGHT_TIME_MAX);
    
    if (!IsValidEntity(firework))
    {
        DataPack fallbackPack = new DataPack();
        fallbackPack.WriteFloat(startPos[0]);
        fallbackPack.WriteFloat(startPos[1]);
        fallbackPack.WriteFloat(startPos[2] + FIREWORK_LAUNCH_SPEED * flightTime);
        CreateTimer(flightTime, Timer_FallbackExplode, fallbackPack, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    
    DispatchKeyValue(firework, "model", "sprites/glow01.vmt");
    DispatchKeyValue(firework, "rendermode", "5");
    DispatchKeyValue(firework, "renderamt", "255");
    DispatchKeyValue(firework, "rendercolor", "255 220 100");
    DispatchKeyValue(firework, "scale", "0.8");
    DispatchKeyValue(firework, "spawnflags", "1");
    
    TeleportEntity(firework, startPos, NULL_VECTOR, NULL_VECTOR);
    DispatchSpawn(firework);
    AcceptEntityInput(firework, "ShowSprite");
    
    float velocity[3];
    velocity[0] = direction[0] * FIREWORK_LAUNCH_SPEED;
    velocity[1] = direction[1] * FIREWORK_LAUNCH_SPEED;
    velocity[2] = direction[2] * FIREWORK_LAUNCH_SPEED;
    
    DataPack pack = new DataPack();
    pack.WriteCell(EntIndexToEntRef(firework));
    pack.WriteFloat(startPos[0]);
    pack.WriteFloat(startPos[1]);
    pack.WriteFloat(startPos[2]);
    pack.WriteFloat(velocity[0]);
    pack.WriteFloat(velocity[1]);
    pack.WriteFloat(velocity[2]);
    pack.WriteFloat(0.0);
    pack.WriteFloat(flightTime);
    
    CreateTimer(0.04, Timer_FireworkFlight, pack, TIMER_REPEAT | TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
    
    // Firework rising trail
    int color[4] = {255, 200, 50, 255};
    TE_SetupBeamFollow(firework, g_iBeamSprite, g_iHaloSprite, 2.5, 12.0, 3.0, 1, color);
    TE_SendToAll();
}

public Action Timer_FireworkFlight(Handle timer, DataPack pack)
{
    pack.Reset();
    
    int ref = pack.ReadCell();
    int firework = EntRefToEntIndex(ref);
    
    float startPos[3], velocity[3];
    startPos[0] = pack.ReadFloat();
    startPos[1] = pack.ReadFloat();
    startPos[2] = pack.ReadFloat();
    velocity[0] = pack.ReadFloat();
    velocity[1] = pack.ReadFloat();
    velocity[2] = pack.ReadFloat();
    float elapsed = pack.ReadFloat();
    float flightTime = pack.ReadFloat();
    
    elapsed += 0.04;
    
    float newPos[3];
    newPos[0] = startPos[0] + velocity[0] * elapsed;
    newPos[1] = startPos[1] + velocity[1] * elapsed;
    newPos[2] = startPos[2] + velocity[2] * elapsed - (300.0 * elapsed * elapsed * 0.5);
    
    if (IsValidEntity(firework))
    {
        TeleportEntity(firework, newPos, NULL_VECTOR, NULL_VECTOR);
        
        // Frequent sparkles during flight
        if (GetRandomFloat(0.0, 1.0) > 0.3)
        {
            TE_SetupGlowSprite(newPos, g_iGlowSprite, 0.15, GetRandomFloat(0.3, 0.6), GetRandomInt(180, 255));
            TE_SendToAll();
        }
        
        // Side sparkles
        if (GetRandomFloat(0.0, 1.0) > 0.6)
        {
            float sidePos[3];
            sidePos[0] = newPos[0] + GetRandomFloat(-15.0, 15.0);
            sidePos[1] = newPos[1] + GetRandomFloat(-15.0, 15.0);
            sidePos[2] = newPos[2] + GetRandomFloat(-10.0, 10.0);
            TE_SetupGlowSprite(sidePos, g_iFlareSprite, 0.1, 0.2, GetRandomInt(150, 220));
            TE_SendToAll();
        }
        
        // Occasional sparks
        if (GetRandomFloat(0.0, 1.0) > 0.7)
        {
            float sparkDir[3];
            sparkDir[0] = GetRandomFloat(-50.0, 50.0);
            sparkDir[1] = GetRandomFloat(-50.0, 50.0);
            sparkDir[2] = GetRandomFloat(-30.0, 30.0);
            TE_SetupSparks(newPos, sparkDir, 3, 2);
            TE_SendToAll();
        }
    }
    
    if (elapsed >= flightTime)
    {
        if (IsValidEntity(firework))
        {
            float finalPos[3];
            GetEntPropVector(firework, Prop_Send, "m_vecOrigin", finalPos);
            AcceptEntityInput(firework, "Kill");
            CreateFireworkExplosion(finalPos);
        }
        return Plugin_Stop;
    }
    
    pack.Reset();
    pack.WriteCell(ref);
    pack.WriteFloat(startPos[0]);
    pack.WriteFloat(startPos[1]);
    pack.WriteFloat(startPos[2]);
    pack.WriteFloat(velocity[0]);
    pack.WriteFloat(velocity[1]);
    pack.WriteFloat(velocity[2]);
    pack.WriteFloat(elapsed);
    pack.WriteFloat(flightTime);
    
    return Plugin_Continue;
}

public Action Timer_FallbackExplode(Handle timer, DataPack pack)
{
    pack.Reset();
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    
    CreateFireworkExplosion(pos);
    return Plugin_Stop;
}

void CreateFireworkExplosion(float pos[3])
{
    int colorIndex = GetRandomInt(0, sizeof(g_FireworkColors) - 1);
    int primaryColor[3];
    primaryColor[0] = g_FireworkColors[colorIndex][0];
    primaryColor[1] = g_FireworkColors[colorIndex][1];
    primaryColor[2] = g_FireworkColors[colorIndex][2];
    
    int secondaryIndex = (colorIndex + GetRandomInt(1, 5)) % sizeof(g_FireworkColors);
    int secondaryColor[3];
    secondaryColor[0] = g_FireworkColors[secondaryIndex][0];
    secondaryColor[1] = g_FireworkColors[secondaryIndex][1];
    secondaryColor[2] = g_FireworkColors[secondaryIndex][2];
    
    int tertiaryIndex = (colorIndex + GetRandomInt(3, 7)) % sizeof(g_FireworkColors);
    int tertiaryColor[3];
    tertiaryColor[0] = g_FireworkColors[tertiaryIndex][0];
    tertiaryColor[1] = g_FireworkColors[tertiaryIndex][1];
    tertiaryColor[2] = g_FireworkColors[tertiaryIndex][2];
    
    // Main explosion sound
    EmitSoundToAll("ambient/explosions/explode_8.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, _, pos);
    
    // Create all the effects
    CreateCentralFlash(pos, primaryColor);
    CreateBurstRays(pos, primaryColor, secondaryColor, tertiaryColor);
    CreateSparkles(pos);
    CreateRingEffect(pos, primaryColor);
    
    // Staggered secondary bursts
    for (int i = 0; i < 4; i++)
    {
        DataPack pack = new DataPack();
        pack.WriteFloat(pos[0]);
        pack.WriteFloat(pos[1]);
        pack.WriteFloat(pos[2]);
        pack.WriteCell(secondaryColor[0]);
        pack.WriteCell(secondaryColor[1]);
        pack.WriteCell(secondaryColor[2]);
        pack.WriteCell(i);
        
        CreateTimer(GetRandomFloat(0.08, 0.25), Timer_SecondaryBurst, pack, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
    }
    
    // Falling embers with random timing
    for (int i = 0; i < 3; i++)
    {
        DataPack emberPack = new DataPack();
        emberPack.WriteFloat(pos[0]);
        emberPack.WriteFloat(pos[1]);
        emberPack.WriteFloat(pos[2]);
        CreateTimer(GetRandomFloat(0.2, 0.5), Timer_CreateEmbers, emberPack, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
    }
    
    // Extra crackle effects
    DataPack cracklePack = new DataPack();
    cracklePack.WriteFloat(pos[0]);
    cracklePack.WriteFloat(pos[1]);
    cracklePack.WriteFloat(pos[2]);
    cracklePack.WriteCell(primaryColor[0]);
    cracklePack.WriteCell(primaryColor[1]);
    cracklePack.WriteCell(primaryColor[2]);
    CreateTimer(GetRandomFloat(0.3, 0.6), Timer_CrackleEffect, cracklePack, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
}

void CreateCentralFlash(float pos[3], int color[3])
{
    // Multiple layered glows
    TE_SetupGlowSprite(pos, g_iGlowSprite, 0.6, 4.0, 255);
    TE_SendToAll();
    
    TE_SetupGlowSprite(pos, g_iFlareSprite, 0.4, 3.0, 255);
    TE_SendToAll();
    
    TE_SetupGlowSprite(pos, g_iHaloSprite, 0.3, 5.0, 200);
    TE_SendToAll();
    
    // Strong dynamic light
    TE_SetupDynamicLight(pos, color[0], color[1], color[2], 10, 500.0, 0.6, 300.0);
    TE_SendToAll();
    
    // Explosion effect
    TE_SetupExplosion(pos, g_iHaloSprite, 8.0, 1, TE_EXPLFLAG_NONE, 300, 200);
    TE_SendToAll();
    
    // Secondary white flash
    TE_SetupDynamicLight(pos, 255, 255, 255, 8, 350.0, 0.2, 500.0);
    TE_SendToAll();
}

void CreateBurstRays(float pos[3], int primaryColor[3], int secondaryColor[3], int tertiaryColor[3])
{
    float endPos[3];
    
    for (int i = 0; i < FIREWORK_BURST_RAYS; i++)
    {
        float angle = float(i) * (360.0 / float(FIREWORK_BURST_RAYS)) + GetRandomFloat(-15.0, 15.0);
        float pitch = GetRandomFloat(-40.0, 70.0);
        
        float radAngle = DegToRad(angle);
        float radPitch = DegToRad(pitch);
        
        // Randomized ray length
        float rayLength = GetRandomFloat(FIREWORK_BURST_RADIUS_MIN, FIREWORK_BURST_RADIUS_MAX);
        
        endPos[0] = pos[0] + Cosine(radAngle) * Cosine(radPitch) * rayLength;
        endPos[1] = pos[1] + Sine(radAngle) * Cosine(radPitch) * rayLength;
        endPos[2] = pos[2] + Sine(radPitch) * rayLength;
        
        // Cycle through three colors
        int beamColor[4];
        if (i % 3 == 0)
        {
            beamColor[0] = primaryColor[0];
            beamColor[1] = primaryColor[1];
            beamColor[2] = primaryColor[2];
        }
        else if (i % 3 == 1)
        {
            beamColor[0] = secondaryColor[0];
            beamColor[1] = secondaryColor[1];
            beamColor[2] = secondaryColor[2];
        }
        else
        {
            beamColor[0] = tertiaryColor[0];
            beamColor[1] = tertiaryColor[1];
            beamColor[2] = tertiaryColor[2];
        }
        beamColor[3] = 255;
        
        // Main beam with randomized width
        float beamWidth = GetRandomFloat(6.0, 12.0);
        TE_SetupBeamPoints(pos, endPos, g_iBeamSprite, g_iHaloSprite, 0, 30, GetRandomFloat(0.6, 1.0), beamWidth, beamWidth * 0.1, 0, 0.0, beamColor, 25);
        TE_SendToAll();
        
        // Glow at end of ray
        TE_SetupGlowSprite(endPos, g_iGlowSprite, GetRandomFloat(0.3, 0.6), GetRandomFloat(0.6, 1.2), GetRandomInt(180, 255));
        TE_SendToAll();
        
        // Extra flare
        TE_SetupGlowSprite(endPos, g_iFlareSprite, GetRandomFloat(0.2, 0.4), GetRandomFloat(0.4, 0.8), GetRandomInt(150, 220));
        TE_SendToAll();
        
        // Sparks at end with varied intensity
        float sparkDir[3];
        sparkDir[0] = (endPos[0] - pos[0]) * 0.3;
        sparkDir[1] = (endPos[1] - pos[1]) * 0.3;
        sparkDir[2] = (endPos[2] - pos[2]) * 0.3;
        
        TE_SetupSparks(endPos, sparkDir, GetRandomInt(5, 12), GetRandomInt(3, 6));
        TE_SendToAll();
    }
    
    // Extra shorter rays for density
    for (int i = 0; i < 16; i++)
    {
        float angle = GetRandomFloat(0.0, 360.0);
        float pitch = GetRandomFloat(-20.0, 50.0);
        
        float radAngle = DegToRad(angle);
        float radPitch = DegToRad(pitch);
        
        float rayLength = GetRandomFloat(100.0, 200.0);
        
        endPos[0] = pos[0] + Cosine(radAngle) * Cosine(radPitch) * rayLength;
        endPos[1] = pos[1] + Sine(radAngle) * Cosine(radPitch) * rayLength;
        endPos[2] = pos[2] + Sine(radPitch) * rayLength;
        
        int beamColor[4];
        beamColor[0] = 255;
        beamColor[1] = 255;
        beamColor[2] = 200;
        beamColor[3] = 200;
        
        TE_SetupBeamPoints(pos, endPos, g_iBeamSprite, g_iHaloSprite, 0, 30, GetRandomFloat(0.3, 0.5), 3.0, 0.5, 0, 0.0, beamColor, 15);
        TE_SendToAll();
    }
}

void CreateSparkles(float pos[3])
{
    float burstRadius = GetRandomFloat(FIREWORK_BURST_RADIUS_MIN, FIREWORK_BURST_RADIUS_MAX);
    
    // Main sparkle cloud
    for (int i = 0; i < 40; i++)
    {
        float sparklePos[3];
        sparklePos[0] = pos[0] + GetRandomFloat(-burstRadius * 0.6, burstRadius * 0.6);
        sparklePos[1] = pos[1] + GetRandomFloat(-burstRadius * 0.6, burstRadius * 0.6);
        sparklePos[2] = pos[2] + GetRandomFloat(-burstRadius * 0.4, burstRadius * 0.6);
        
        TE_SetupGlowSprite(sparklePos, g_iFlareSprite, GetRandomFloat(0.2, 0.6), GetRandomFloat(0.3, 0.8), GetRandomInt(150, 255));
        TE_SendToAll();
    }
    
    // Side sparkles - spread out more
    for (int i = 0; i < 25; i++)
    {
        float sparklePos[3];
        float angle = GetRandomFloat(0.0, 360.0);
        float dist = GetRandomFloat(burstRadius * 0.3, burstRadius * 0.8);
        float radAngle = DegToRad(angle);
        
        sparklePos[0] = pos[0] + Cosine(radAngle) * dist;
        sparklePos[1] = pos[1] + Sine(radAngle) * dist;
        sparklePos[2] = pos[2] + GetRandomFloat(-50.0, 100.0);
        
        TE_SetupGlowSprite(sparklePos, g_iGlowSprite, GetRandomFloat(0.15, 0.4), GetRandomFloat(0.2, 0.5), GetRandomInt(180, 255));
        TE_SendToAll();
    }
    
    // Intense core sparkles
    for (int i = 0; i < 15; i++)
    {
        float sparklePos[3];
        sparklePos[0] = pos[0] + GetRandomFloat(-50.0, 50.0);
        sparklePos[1] = pos[1] + GetRandomFloat(-50.0, 50.0);
        sparklePos[2] = pos[2] + GetRandomFloat(-30.0, 50.0);
        
        TE_SetupGlowSprite(sparklePos, g_iGlowSprite, GetRandomFloat(0.1, 0.3), GetRandomFloat(0.8, 1.5), 255);
        TE_SendToAll();
    }
}

void CreateRingEffect(float pos[3], int color[3])
{
    // Horizontal ring of beams
    float ringRadius = GetRandomFloat(150.0, 250.0);
    int ringSegments = 12;
    
    for (int i = 0; i < ringSegments; i++)
    {
        float angle1 = float(i) * (360.0 / float(ringSegments));
        float angle2 = float(i + 1) * (360.0 / float(ringSegments));
        
        float radAngle1 = DegToRad(angle1);
        float radAngle2 = DegToRad(angle2);
        
        float startPos[3], endPos[3];
        startPos[0] = pos[0] + Cosine(radAngle1) * ringRadius;
        startPos[1] = pos[1] + Sine(radAngle1) * ringRadius;
        startPos[2] = pos[2];
        
        endPos[0] = pos[0] + Cosine(radAngle2) * ringRadius;
        endPos[1] = pos[1] + Sine(radAngle2) * ringRadius;
        endPos[2] = pos[2];
        
        int beamColor[4];
        beamColor[0] = color[0];
        beamColor[1] = color[1];
        beamColor[2] = color[2];
        beamColor[3] = 255;
        
        TE_SetupBeamPoints(startPos, endPos, g_iBeamSprite, g_iHaloSprite, 0, 30, 0.5, 6.0, 1.0, 0, 0.0, beamColor, 20);
        TE_SendToAll();
        
        // Glow at each vertex
        TE_SetupGlowSprite(startPos, g_iFlareSprite, 0.3, 0.5, 200);
        TE_SendToAll();
    }
}

public Action Timer_SecondaryBurst(Handle timer, DataPack pack)
{
    pack.Reset();
    
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    
    int color[3];
    color[0] = pack.ReadCell();
    color[1] = pack.ReadCell();
    color[2] = pack.ReadCell();
    int burstIndex = pack.ReadCell();
    
    float burstRadius = GetRandomFloat(FIREWORK_BURST_RADIUS_MIN, FIREWORK_BURST_RADIUS_MAX);
    
    // Position the burst in different areas
    float burstPos[3];
    float angle = float(burstIndex) * 90.0 + GetRandomFloat(-30.0, 30.0);
    float radAngle = DegToRad(angle);
    float dist = burstRadius * GetRandomFloat(0.4, 0.7);
    
    burstPos[0] = pos[0] + Cosine(radAngle) * dist;
    burstPos[1] = pos[1] + Sine(radAngle) * dist;
    burstPos[2] = pos[2] + GetRandomFloat(-50.0, 80.0);
    
    // Mini explosion glow
    TE_SetupGlowSprite(burstPos, g_iGlowSprite, 0.4, 1.5, 255);
    TE_SendToAll();
    
    TE_SetupGlowSprite(burstPos, g_iFlareSprite, 0.3, 1.0, 220);
    TE_SendToAll();
    
    // Dynamic light
    TE_SetupDynamicLight(burstPos, color[0], color[1], color[2], 6, 200.0, 0.3, 150.0);
    TE_SendToAll();
    
    // Sparks burst
    for (int i = 0; i < 3; i++)
    {
        float sparkDir[3];
        sparkDir[0] = GetRandomFloat(-80.0, 80.0);
        sparkDir[1] = GetRandomFloat(-80.0, 80.0);
        sparkDir[2] = GetRandomFloat(-40.0, 80.0);
        TE_SetupSparks(burstPos, sparkDir, GetRandomInt(8, 15), GetRandomInt(4, 8));
        TE_SendToAll();
    }
    
    // Small beams outward with random lengths
    float endPos[3];
    int numBeams = GetRandomInt(5, 8);
    for (int j = 0; j < numBeams; j++)
    {
        float subAngle = GetRandomFloat(0.0, 360.0);
        float subPitch = GetRandomFloat(-30.0, 60.0);
        float radSubAngle = DegToRad(subAngle);
        float radSubPitch = DegToRad(subPitch);
        float beamLength = GetRandomFloat(60.0, 140.0);
        
        endPos[0] = burstPos[0] + Cosine(radSubAngle) * Cosine(radSubPitch) * beamLength;
        endPos[1] = burstPos[1] + Sine(radSubAngle) * Cosine(radSubPitch) * beamLength;
        endPos[2] = burstPos[2] + Sine(radSubPitch) * beamLength;
        
        int beamColor[4];
        beamColor[0] = color[0];
        beamColor[1] = color[1];
        beamColor[2] = color[2];
        beamColor[3] = 255;
        
        TE_SetupBeamPoints(burstPos, endPos, g_iBeamSprite, g_iHaloSprite, 0, 30, GetRandomFloat(0.3, 0.6), GetRandomFloat(3.0, 6.0), 0.5, 0, 0.0, beamColor, 18);
        TE_SendToAll();
        
        // End glow
        TE_SetupGlowSprite(endPos, g_iFlareSprite, 0.2, 0.4, GetRandomInt(150, 220));
        TE_SendToAll();
    }
    
    // Pop sound
    if (GetRandomFloat(0.0, 1.0) > 0.3)
    {
        EmitSoundToAll("ambient/explosions/explode_4.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, GetRandomFloat(0.5, 0.8), GetRandomInt(90, 130), _, burstPos);
    }
    
    return Plugin_Stop;
}

public Action Timer_CrackleEffect(Handle timer, DataPack pack)
{
    pack.Reset();
    
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    
    int color[3];
    color[0] = pack.ReadCell();
    color[1] = pack.ReadCell();
    color[2] = pack.ReadCell();
    
    float burstRadius = GetRandomFloat(FIREWORK_BURST_RADIUS_MIN, FIREWORK_BURST_RADIUS_MAX);
    
    // Random crackle points
    for (int i = 0; i < 10; i++)
    {
        float cracklePos[3];
        cracklePos[0] = pos[0] + GetRandomFloat(-burstRadius * 0.7, burstRadius * 0.7);
        cracklePos[1] = pos[1] + GetRandomFloat(-burstRadius * 0.7, burstRadius * 0.7);
        cracklePos[2] = pos[2] + GetRandomFloat(-burstRadius * 0.3, burstRadius * 0.5);
        
        // Small flash
        TE_SetupGlowSprite(cracklePos, g_iFlareSprite, 0.15, 0.3, GetRandomInt(200, 255));
        TE_SendToAll();
        
        // Tiny sparks
        float sparkDir[3];
        sparkDir[0] = GetRandomFloat(-40.0, 40.0);
        sparkDir[1] = GetRandomFloat(-40.0, 40.0);
        sparkDir[2] = GetRandomFloat(-20.0, 40.0);
        TE_SetupSparks(cracklePos, sparkDir, 4, 2);
        TE_SendToAll();
    }
    
    // Crackle sounds
    char sounds[][] = {"weapons/stunstick/spark1.wav", "weapons/stunstick/spark2.wav"};
    EmitSoundToAll(sounds[GetRandomInt(0, 1)], SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, GetRandomFloat(0.3, 0.6), GetRandomInt(80, 120), _, pos);
    
    return Plugin_Stop;
}

public Action Timer_CreateEmbers(Handle timer, DataPack pack)
{
    pack.Reset();
    
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    
    float burstRadius = GetRandomFloat(FIREWORK_BURST_RADIUS_MIN, FIREWORK_BURST_RADIUS_MAX);
    
    // Falling embers
    for (int i = 0; i < 20; i++)
    {
        float emberPos[3];
        emberPos[0] = pos[0] + GetRandomFloat(-burstRadius, burstRadius);
        emberPos[1] = pos[1] + GetRandomFloat(-burstRadius, burstRadius);
        emberPos[2] = pos[2] + GetRandomFloat(-80.0, 80.0);
        
        float fallDir[3];
        fallDir[0] = GetRandomFloat(-40.0, 40.0);
        fallDir[1] = GetRandomFloat(-40.0, 40.0);
        fallDir[2] = GetRandomFloat(-150.0, -80.0);
        
        TE_SetupSparks(emberPos, fallDir, GetRandomInt(2, 5), GetRandomInt(1, 3));
        TE_SendToAll();
        
        // Fading glow
        TE_SetupGlowSprite(emberPos, g_iFlareSprite, GetRandomFloat(0.4, 0.8), GetRandomFloat(0.2, 0.4), GetRandomInt(120, 180));
        TE_SendToAll();
    }
    
    // Smoke wisps
    for (int i = 0; i < 6; i++)
    {
        float smokePos[3];
        smokePos[0] = pos[0] + GetRandomFloat(-150.0, 150.0);
        smokePos[1] = pos[1] + GetRandomFloat(-150.0, 150.0);
        smokePos[2] = pos[2] + GetRandomFloat(-100.0, 100.0);
        
        TE_SetupSmoke(smokePos, g_iSmokeSprite, GetRandomFloat(15.0, 30.0), GetRandomInt(2, 5));
        TE_SendToAll();
    }
    
    return Plugin_Stop;
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

void ClearFireworkTimer(int client)
{
    if (g_hFireworkTimer[client] != null)
    {
        KillTimer(g_hFireworkTimer[client]);
        g_hFireworkTimer[client] = null;
    }
}

public Action Timer_FireworkExpire(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    
    if (client > 0 && IsClientInGame(client))
    {
        g_hFireworkTimer[client] = null;
        
        if (g_bFireworkActive[client])
        {
            g_bFireworkActive[client] = false;
            PrintToChat(client, "\x04[Firework]\x01 Firework mode \x07EXPIRED\x01!");
        }
    }
    
    return Plugin_Stop;
}

void TE_SetupDynamicLight(float pos[3], int r, int g, int b, int exponent, float radius, float time, float decay)
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
