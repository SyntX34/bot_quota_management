#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

// Declare ConVar handles
Handle bot_quota_cvar;
Handle bot_quota_mode_cvar;
Handle min_bots;
Handle max_bots;

public Plugin myinfo =
{
    name        = "[Bot Quota] Dynamic Management",
    author      = "+SyntX",
    description = "Keeps total players (humans + bots) based on user-defined limits.",
    version     = "1.8",
    url         = "http://steamcommunity.com/id/SyntX34 && https://github.com/SyntX34"
};

public void OnPluginStart()
{
    bot_quota_cvar = FindConVar("bot_quota");
    bot_quota_mode_cvar = FindConVar("bot_quota_mode");

    // Create dynamic ConVars for minimum and maximum bots
    min_bots = CreateConVar("sm_min_bots", "4", "Minimum bot quota when players are online.", FCVAR_NOTIFY);
    max_bots = CreateConVar("sm_max_bots", "10", "Maximum bot quota when no players are online.", FCVAR_NOTIFY);

    // Set bot_quota_mode to "normal" to respect manual adjustments
    if (bot_quota_mode_cvar != null)
    {
        SetConVarString(bot_quota_mode_cvar, "normal");
    }

    // Periodically adjust bots and hook into events
    CreateTimer(3.0, AdjustBots, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    AutoExecConfig(true, "bot_quota_manager");
    HookEvent("round_end", RoundEnd);
    HookEvent("player_connect", OnPlayerConnect);
    HookEvent("player_disconnect", OnPlayerDisConnect);
}

public void OnMapStart()
{
    // Reinitialize bot quota settings when the map changes
    if (bot_quota_mode_cvar != null)
    {
        SetConVarString(bot_quota_mode_cvar, "normal");
    }

    if (bot_quota_cvar != null)
    {
        SetConVarInt(bot_quota_cvar, GetConVarInt(max_bots)); // Start with max_bots
    }

    // Trigger immediate bot adjustment
    AdjustBots(null, 0);
}

public Action AdjustBots(Handle timer, any:data)
{
    int humanCount = GetHumanPlayerCount();

    // Fetch user-defined min and max bot values
    int g_MinBots = GetConVarInt(min_bots);
    int g_MaxBots = GetConVarInt(max_bots);

    // Calculate the desired bot count dynamically
    int desiredBots = g_MaxBots - humanCount;

    if (humanCount >= (g_MaxBots - g_MinBots)) 
    {
        desiredBots = g_MinBots;
    }
    else
    {
        desiredBots = Max(g_MinBots, g_MaxBots - humanCount);
    }

    // Ensure the desired bot count respects server limits
    int maxAllowedBots = MaxClients - humanCount;
    desiredBots = Min(desiredBots, maxAllowedBots);

    // Set the calculated bot quota
    if (bot_quota_cvar != null)
    {
        SetConVarInt(bot_quota_cvar, desiredBots);
    }

    PrintToServer("[DEBUG] AdjustBots: humanCount=%d, desiredBots=%d, g_MinBots=%d, g_MaxBots=%d", humanCount, desiredBots, g_MinBots, g_MaxBots);

    return Plugin_Continue;
}

public void RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    BalanceBotTeams();
}

public void BalanceBotTeams()
{
    int team1Bots = 0;
    int team2Bots = 0;

    // Fetch minimum bot value
    int g_MinBots = GetConVarInt(min_bots);

    // Count the current bots on each team
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientConnected(client) && IsClientInGame(client) && IsFakeClient(client))
        {
            int team = GetClientTeam(client);
            if (team == CS_TEAM_T)
            {
                team1Bots++;
            }
            else if (team == CS_TEAM_CT)
            {
                team2Bots++;
            }
        }
    }

    PrintToServer("[DEBUG] BalanceBotTeams: team1Bots=%d, team2Bots=%d", team1Bots, team2Bots);

    int botsPerTeam = g_MinBots / 2;
    int extraBot = g_MinBots % 2;

    if (team1Bots < botsPerTeam + extraBot)
    {
        int botsToAdd = botsPerTeam + extraBot - team1Bots;
        for (int i = 0; i < botsToAdd; i++)
        {
            AddBotToTeam(CS_TEAM_T);
        }
    }
    else if (team1Bots > botsPerTeam)
    {
        int botsToRemove = team1Bots - botsPerTeam;
        for (int client = 1; client <= MaxClients && botsToRemove > 0; client++)
        {
            if (IsClientConnected(client) && IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == CS_TEAM_T)
            {
                KickClient(client, "Too many bots on T team");
                botsToRemove--;
            }
        }
    }

    if (team2Bots < botsPerTeam)
    {
        int botsToAdd = botsPerTeam - team2Bots;
        for (int i = 0; i < botsToAdd; i++)
        {
            AddBotToTeam(CS_TEAM_CT);
        }
    }
    else if (team2Bots > botsPerTeam)
    {
        int botsToRemove = team2Bots - botsPerTeam;
        for (int client = 1; client <= MaxClients && botsToRemove > 0; client++)
        {
            if (IsClientConnected(client) && IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == CS_TEAM_CT)
            {
                KickClient(client, "Too many bots on CT team");
                botsToRemove--;
            }
        }
    }

    PrintToServer("[DEBUG] BalanceBotTeams After Adjustment: team1Bots=%d, team2Bots=%d", team1Bots, team2Bots);
}

public void AddBotToTeam(int team)
{
    if (team == CS_TEAM_T)
    {
        // Add a bot to Team T
        CreateFakeClient("Terrorist Bot");
        //PrintToServer("[DEBUG] Added bot to Team T");
    }
    else if (team == CS_TEAM_CT)
    {
        // Add a bot to Team CT
        CreateFakeClient("Counter-Terrorist Bot");
        //PrintToServer("[DEBUG] Added bot to Team CT");
    }
}

public int GetHumanPlayerCount()
{
    int humanCount = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client) && !IsClientObserver(client))
        {
            int team = GetClientTeam(client);
            if (team != CS_TEAM_SPECTATOR)
            {
                humanCount++;
            }
        }
    }

    return humanCount;
}

public int Max(int a, int b)
{
    return (a > b) ? a : b;
}

public int Min(int a, int b)
{
    return (a < b) ? a : b;
}

public void OnPlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
    int humanCount = GetHumanPlayerCount();

    int g_MaxBots = GetConVarInt(max_bots);
    if (humanCount > g_MaxBots)
    {
        // Remove excess bots
        for (int client = 1; client <= MaxClients; client++)
        {
            if (IsClientConnected(client) && IsClientInGame(client) && IsFakeClient(client))
            {
                KickClient(client, "Too many bots, player joined.");
            }
        }
    }
}

public void OnPlayerDisConnect(Event event, const char[] name, bool dontBroadcast)
{
    int humanCount = GetHumanPlayerCount();
    int g_MinBots = GetConVarInt(min_bots);
    int g_MaxBots = GetConVarInt(max_bots);

    if (humanCount < g_MinBots)
    {
        int botsToAdd = g_MinBots - humanCount;
        for (int i = 0; i < botsToAdd && MaxClients - humanCount > 0; i++)
        {
            AddBotToTeam(CS_TEAM_T);
            humanCount++;
        }

        for (int i = 0; i < botsToAdd && MaxClients - humanCount > 0; i++)
        {
            AddBotToTeam(CS_TEAM_CT);
            humanCount++;
        }
    }
}
