untyped
global function GamemodeFW_Init
global function RateSpawnpoints_FW
//global function SetupFWTerritoryTrigger

// for battery_port.gnut to work
global function FW_ReplaceMegaTurretFromTurretInfo
global function FW_GetTurretInfoFromMegaTurret

// fw specific titanfalls
global function FW_PlayerInFriendlyTerritory
global function FW_ReCalculateTitanReplacementPoint

// basically needs to match "waves count - bosswaves count"
const int FW_MAX_LEVELS = 3

// to confirm it's a npc from camps..
const string FW_NPC_SCRIPTNAME = "fw_npcsFromCamp"
const int FW_AI_TEAM = TEAM_BOTH
const float WAVE_STATE_TRANSITION_TIME = 5.0

// from sh_gamemode_fw, if half of these npcs cleared in one camp, it gets escalate
const int FW_GRUNT_COUNT = 36//32
const int FW_SPECTRE_COUNT = 24
const int FW_REAPER_COUNT = 2

// max deployment each camp
const int FW_GRUNT_MAX_DEPLOYED = 8 
const int FW_SPECTRE_MAX_DEPLOYED = 8 
const int FW_REAPER_MAX_DEPLOYED = 1

// if other camps been cleaned many times, we levelDown
const int FW_IGNORE_NEEDED = 2

global HarvesterStruct& fw_harvesterMlt
global HarvesterStruct& fw_harvesterImc


//array< HarvesterStruct& > harvesters = [ fw_harvesterMlt , fw_harvesterImc ]
global struct TurretSite
{
    entity site
    entity turret
    entity minimapstate
    string turretflagid
}

// this is not using respawn's remaining codes!
struct CampSiteStruct
{
    entity camp
    entity info
    entity tracker
    array<entity> validDropPodSpawns
    array<entity> validTitanSpawns
    string campId // "A", "B", "C"
    int ignoredSinceLastClean
}

struct CampSpawnStruct
{
    string spawnContent // what npcs to spawn
    int maxSpawnCount // max spawn count on this camp
    int countPerSpawn // how many npcs to deploy per spawn, for droppods most be 4
    int killsToEscalate // how many kills needed to escalate
}

struct
{
    array<HarvesterStruct> harvesters

    array<entity> camps

    array<entity> fwTerritories

    array<TurretSite> turretsites

    array<CampSiteStruct> fwCampSites

    array<entity> etitaninmlt
    array<entity> etitaninimc

    entity harvesterMlt_info
    entity harvesterImc_info

    table<int, CampSpawnStruct> fwNpcLevel // basically use to powerup certian camp, sync with alertLevel
    table< string, table< string, int > > trackedCampNPCSpawns
}file

void function GamemodeFW_Init()
{
    file.harvesters.append(fw_harvesterMlt)
    file.harvesters.append(fw_harvesterImc)

    AiGameModes_SetGruntWeapons( [ "mp_weapon_rspn101", "mp_weapon_dmr", "mp_weapon_r97", "mp_weapon_lmg" ] )
	AiGameModes_SetSpectreWeapons( [ "mp_weapon_hemlok_smg", "mp_weapon_doubletake", "mp_weapon_mastiff" ] )

    AddCallback_EntitiesDidLoad( LoadEntities )
    AddCallback_GameStateEnter( eGameState.Prematch, OnFWGamePrematch )
    AddCallback_GameStateEnter( eGameState.Playing, OnFWGamePlaying )

    ScoreEvent_SetupEarnMeterValuesForMixedModes()

    ClassicMP_ForceDisableEpilogue( true ) // temp

    RegisterSignal( "FlashTurretFlag" )
    // need to be in LoadEntities(), before harvester creation
    //AddSpawnCallbackEditorClass( "trigger_multiple", "trigger_fw_territory", SetupFWTerritoryTrigger )
    // noneed to use it rn
    //AddSpawnCallbackEditorClass( "info_target", "info_fw_camp", InitCampTracker )
}

void function RateSpawnpoints_FW( int checkClass, array<entity> spawnpoints, int team, entity player )
{
    if ( HasSwitchedSides() )
		team = GetOtherTeam( team )

	// check hardpoints, determine which ones we own
	array<entity> startSpawns = SpawnPoints_GetPilotStart( team )
	vector averageFriendlySpawns

	// average out startspawn positions
	foreach ( entity spawnpoint in startSpawns )
		averageFriendlySpawns += spawnpoint.GetOrigin()

	averageFriendlySpawns /= startSpawns.len()

	entity friendlyTerritory
	foreach ( entity territory in file.fwTerritories )
	{
		if ( team == territory.GetTeam() )
        {
            friendlyTerritory = territory
            break
        }
	}

	vector ratingPos
	if ( IsValid( friendlyTerritory ) )
		ratingPos = friendlyTerritory.GetOrigin()
	else
		ratingPos = averageFriendlySpawns

	foreach ( entity spawnpoint in spawnpoints )
	{
		// idk about magic number here really
		float rating = 1.0 - ( Distance2D( spawnpoint.GetOrigin(), ratingPos ) / 1000.0 )
		spawnpoint.CalculateRating( checkClass, player.GetTeam(), rating, rating )
	}
}

void function OnFWGamePrematch()
{
    FW_createHarvester()
    InitCampSpawner()
}

void function OnFWGamePlaying()
{
    startFWHarvester()
    FWAreaThreatLevelThink()
    StartFWCampThink()
}

void function InitCampSpawner() // can edit this to make more spawns, alertLevel icons supports max to lv3( 0,1,2 )
{
    // lv1 spawns: grunts
    CampSpawnStruct campSpawnLv1
    campSpawnLv1.spawnContent = "npc_soldier"
    campSpawnLv1.maxSpawnCount = FW_GRUNT_MAX_DEPLOYED
    campSpawnLv1.countPerSpawn = 4 // how many npcs to deploy per spawn, for droppods most be 4
    campSpawnLv1.killsToEscalate = FW_GRUNT_COUNT / 2

    file.fwNpcLevel[0] <- campSpawnLv1

    // lv2 spawns: spectres
    CampSpawnStruct campSpawnLv2
    campSpawnLv2.spawnContent = "npc_spectre"
    campSpawnLv2.maxSpawnCount = FW_SPECTRE_MAX_DEPLOYED
    campSpawnLv2.countPerSpawn = 4 // how many npcs to deploy per spawn, for droppods most be 4
    campSpawnLv2.killsToEscalate = FW_SPECTRE_COUNT / 2

    file.fwNpcLevel[1] <- campSpawnLv2

    // lv3 spawns: reapers
    CampSpawnStruct campSpawnLv3
    campSpawnLv3.spawnContent = "npc_super_spectre"
    campSpawnLv3.maxSpawnCount = FW_REAPER_MAX_DEPLOYED
    campSpawnLv3.countPerSpawn = 1 // how many npcs to deploy per spawn
    campSpawnLv3.killsToEscalate = FW_REAPER_COUNT / 2 // only 1 kill needed to spawn the boss?

    file.fwNpcLevel[2] <- campSpawnLv3
}

void function InitCampTracker( entity camp )
{
    print("InitCampTracker")
    CampSiteStruct campsite
    campsite.camp = camp
    file.fwCampSites.append( campsite )

    entity placementHelper = CreateEntity( "info_placement_helper" )
    placementHelper.SetOrigin( camp.GetOrigin() ) // tracker needs a owner to display
    //prop.SetModel( $"models/dev/empty_model.mdl" )
    campsite.info = placementHelper
    DispatchSpawn( placementHelper )

    float radius = float( camp.kv.radius ) // radius to show up icon and spawn ais

    entity tracker = GetAvailableCampLocationTracker()
    tracker.SetOwner( placementHelper )
    campsite.tracker = tracker
    SetLocationTrackerRadius( tracker, radius )
    DispatchSpawn( tracker )

    // get droppod spawns
    foreach ( entity spawnpoint in SpawnPoints_GetDropPod() )
        if ( Distance( camp.GetOrigin(), spawnpoint.GetOrigin() ) < radius )
            campsite.validDropPodSpawns.append( spawnpoint )
    
    // get titan spawns
    foreach ( entity spawnpoint in SpawnPoints_GetTitan() )
        if ( Distance( camp.GetOrigin(), spawnpoint.GetOrigin() ) < radius )
            campsite.validTitanSpawns.append( spawnpoint )
}

void function StartFWCampThink()
{
    foreach( CampSiteStruct camp in file.fwCampSites )
    {
        //print( "has " + string( file.fwCampSites.len() ) + " camps in total" )
        //print( "campId is " + camp.campId )
        thread FWAiCampThink( camp )
    }
}

// this is not using respawn's remaining code!
void function FWAiCampThink( CampSiteStruct campsite )
{
    string campId = campsite.campId
    string alertVarName = "fwCampAlert" + campId
    string stressVarName = "fwCampStress" + campId

    while( GetGameState() == eGameState.Playing )
    {
        wait WAVE_STATE_TRANSITION_TIME

        int alertLevel = GetGlobalNetInt( alertVarName )
        //print( "campsite" + campId + ".ignoredSinceLastClean: " + string( campsite.ignoredSinceLastClean ) )
        if( campsite.ignoredSinceLastClean >= FW_IGNORE_NEEDED && alertLevel > 1 ) // has been ignored many times, level > 1
        {
            // reset level
            alertLevel = 0 
            SetGlobalNetInt( alertVarName, 0 )
        }

        // under attack, clean this
        campsite.ignoredSinceLastClean = 0 

        CampSpawnStruct curSpawnStruct = file.fwNpcLevel[alertLevel]
        string npcToSpawn = curSpawnStruct.spawnContent
        int maxSpawnCount = curSpawnStruct.maxSpawnCount
        int countPerSpawn = curSpawnStruct.countPerSpawn
        int killsToEscalate = curSpawnStruct.killsToEscalate

        // for this time's loop
        file.trackedCampNPCSpawns[campId] = {}
        int killsNeeded = killsToEscalate
        int lastNpcLeft
        while( true ) 
        {
            WaitFrame()

            //print( alertVarName + " : " + string( GetGlobalNetInt( alertVarName ) ) )
            //print( stressVarName + " : " + string( GetGlobalNetFloat( stressVarName ) ) )
            //print( "campsite" + campId + ".ignoredSinceLastClean: " + string( campsite.ignoredSinceLastClean ) )

            if( !( npcToSpawn in file.trackedCampNPCSpawns[campId] ) ) // init it
                file.trackedCampNPCSpawns[campId][npcToSpawn] <- 0

            int npcsLeft = file.trackedCampNPCSpawns[campId][npcToSpawn]
            killsNeeded -= lastNpcLeft - npcsLeft

            if( killsNeeded <= 0 ) // check if needs more kills
            {
                if( alertLevel + 1 >= FW_MAX_LEVELS - 1 ) // next upgrade reached max level!
                    SetGlobalNetInt( alertVarName, FW_MAX_LEVELS - 1 )
                else
                    SetGlobalNetInt( alertVarName, alertLevel + 1 ) // normal level up
                // can't use float rn
                //SetGlobalNetFloat( stressVarName, 1.0 ) // refill
                AddIgnoredCountToOtherCamps( campsite )
                break
            }

            // update stress bar
            float campStressLeft = float( killsNeeded ) / float( killsToEscalate )
            // can't use float rn
            //SetGlobalNetFloat( stressVarName, campStressLeft )
            //print( "campStressLeft: " + string( campStressLeft ) )

            if( maxSpawnCount - npcsLeft >= countPerSpawn && killsNeeded >= countPerSpawn ) // keep spawning
            {
                // spawn functions, for fw we only spawn one kind of enemy each time
                // light units
                if( npcToSpawn == "npc_soldier"
                    || npcToSpawn == "npc_spectre"
                    || npcToSpawn == "npc_stalker" )
                    thread FW_SpawnDroppodSquad( campsite, npcToSpawn )

                // reapers
                if( npcToSpawn == "npc_super_spectre" )
                    thread FW_SpawnReaper( campsite )

                file.trackedCampNPCSpawns[campId][npcToSpawn] += countPerSpawn

                // titans?
                //else if( npcToSpawn == "npc_titan" )
                //{
                //    file.trackedCampNPCSpawns[campId][npcToSpawn] += 4
                //}
            }

            lastNpcLeft = file.trackedCampNPCSpawns[campId][npcToSpawn]
        }
    }
}

void function AddIgnoredCountToOtherCamps( CampSiteStruct senderCamp )
{
    foreach( CampSiteStruct camp in file.fwCampSites )
    {
        //print( "senderCampId is: " + senderCamp.campId )
        //print( "curCampId is " + camp.campId )
        if( camp.campId != senderCamp.campId ) // other camps
        {
            camp.ignoredSinceLastClean += 1
        }
    }
}

// functions from at
void function FW_SpawnDroppodSquad( CampSiteStruct campsite, string aiType )
{
	entity spawnpoint
	if ( campsite.validDropPodSpawns.len() == 0 )
		spawnpoint = campsite.tracker // no spawnPoints valid, use camp itself to spawn
	else
		spawnpoint = campsite.validDropPodSpawns.getrandom()
	
	// add variation to spawns
	wait RandomFloat( 1.0 )
	
	AiGameModes_SpawnDropPod( spawnpoint.GetOrigin(), spawnpoint.GetAngles(), FW_AI_TEAM, aiType, void function( array<entity> guys ) : ( campsite, aiType ) 
	{
		FW_HandleSquadSpawn( guys, campsite, aiType )
	})
}

void function FW_HandleSquadSpawn( array<entity> guys, CampSiteStruct campsite, string aiType )
{
	foreach ( entity guy in guys )
	{
		guy.EnableNPCFlag( NPC_ALLOW_HAND_SIGNALS | NPC_ALLOW_FLEE ) // NPC_ALLOW_PATROL | NPC_ALLOW_INVESTIGATE is not allowed
		guy.SetScriptName( FW_NPC_SCRIPTNAME ) // well no need
        // show on minimap to let players kill them
        guy.Minimap_AlwaysShow( TEAM_MILITIA, null )
        guy.Minimap_AlwaysShow( TEAM_IMC, null )

		// untrack them on death
		thread FW_WaitToUntrackNPC( guy, campsite.campId, aiType )
	}
    // at least don't let them running around
    thread FW_ForceAssaultInCamp( guys, campsite.camp )
}

void function FW_SpawnReaper( CampSiteStruct campsite )
{
	entity spawnpoint
	if ( campsite.validDropPodSpawns.len() == 0 )
		spawnpoint = campsite.tracker // no spawnPoints valid, use camp itself to spawn
	else
		spawnpoint = campsite.validDropPodSpawns.getrandom()

	// add variation to spawns
	wait RandomFloat( 1.0 )
	
	AiGameModes_SpawnReaper( spawnpoint.GetOrigin(), spawnpoint.GetAngles(), FW_AI_TEAM, "npc_super_spectre_aitdm",void function( entity reaper ) : ( campsite ) 
	{
        reaper.SetScriptName( FW_NPC_SCRIPTNAME ) // no neet rn
        // show on minimap to let players kill them
        reaper.Minimap_AlwaysShow( TEAM_MILITIA, null )
        reaper.Minimap_AlwaysShow( TEAM_IMC, null )
        
        // at least don't let them running around
        thread FW_ForceAssaultInCamp( [reaper], campsite.camp )
		// untrack them on death
		thread FW_WaitToUntrackNPC( reaper, campsite.campId, "npc_super_spectre" )
	})
}

void function FW_ForceAssaultInCamp( array<entity> guys, entity camp )
{
    while( true )
    {
        bool oneGuyValid = false
        foreach( entity guy in guys )
        {
            if( IsValid( guy ) )
            {
                guy.AssaultPoint( camp.GetOrigin() )
                guy.AssaultSetGoalRadius( float( camp.kv.radius ) / 2 ) // the camp's radius
                oneGuyValid = true
            }
        }
        if( !oneGuyValid ) // no guys left
            return

        wait RandomFloatRange( 10, 15 ) // make randomness
    }
}

void function FW_WaitToUntrackNPC( entity guy, string campId, string aiType )
{
	guy.WaitSignal( "OnDeath", "OnDestroy" )
    if( aiType in file.trackedCampNPCSpawns[ campId ] ) // maybe escalated?
	    file.trackedCampNPCSpawns[ campId ][ aiType ]--
}

void function SetupFWTerritoryTrigger( entity trigger )
{
    /*foreach( trigger in GetEntArrayByClass_Expensive( "trigger_multiple" ) )
    {
        switch( trigger.kv.editorclass )
		{
			case "trigger_fw_territory":
                print("trigger_fw_territory detected")
                trigger.ConnectOutput( "OnStartTouch", EntityEnterFWTrig )
	            trigger.ConnectOutput( "OnEndTouch", EntityLeaveFWTrig )
                break
		}
    }*/
    print("trigger_fw_territory detected")
    file.fwTerritories.append( trigger )
    trigger.ConnectOutput( "OnStartTouch", EntityEnterFWTrig )
	trigger.ConnectOutput( "OnEndTouch", EntityLeaveFWTrig )

    // respawn didn't leave a key for trigger's team, let's set it.
    if( Distance( trigger.GetOrigin(), file.harvesterMlt_info.GetOrigin() ) > Distance( trigger.GetOrigin(), file.harvesterImc_info.GetOrigin() ) )
        SetTeam( trigger, TEAM_IMC )
    else
        SetTeam( trigger, TEAM_MILITIA )
}

bool function FW_PlayerInFriendlyTerritory( entity player )
{
    foreach( entity trigger in file.fwTerritories )
    {
        if( trigger.GetTeam() == player.GetTeam() ) // is it friendly one?
        {
            if( GetAllEntitiesInTrigger( trigger ).contains( player ) ) // is player inside?
                return true
        }
    }
    return false // can't find the player
}

// territory trigger don't have a kv.radius, let's use a const
// 1800 will pretty much get harvester's near titan startpoints
const float FW_SPAWNPOINT_SEARCH_RADIUS = 1800

vector function FW_ReCalculateTitanReplacementPoint( vector baseOrigin, int team )
{
    entity teamHarvester
    // find team's harvester
    if( team == TEAM_IMC )
        teamHarvester = fw_harvesterImc.harvester
    else if( team == TEAM_MILITIA )
        teamHarvester = fw_harvesterMlt.harvester
    else
        unreachable // crash the game

    if( Distance2D( baseOrigin, teamHarvester.GetOrigin() ) <= FW_SPAWNPOINT_SEARCH_RADIUS ) // close enough!
        return baseOrigin // this origin is good enough
    
    // if not close enough to base, re-calculate
    array<entity> fortWarPoints = FW_GetTitanSpawnPointsForTeam( team )
	entity validPoint = GetClosest( fortWarPoints, baseOrigin )
	return validPoint.GetOrigin()
}

array<entity> function FW_GetTitanSpawnPointsForTeam( int team )
{
    array<entity> validSpawnPoints
    entity teamHarvester
    // find team's harvester
    if( team == TEAM_IMC )
        teamHarvester = fw_harvesterImc.harvester
    else if( team == TEAM_MILITIA )
        teamHarvester = fw_harvesterMlt.harvester
    else
        unreachable // crash the game
    
    array<entity> allPoints
    // same as _replacement_titans_drop.gnut does
    allPoints.extend( GetEntArrayByClass_Expensive( "info_spawnpoint_titan" ) )
    allPoints.extend( GetEntArrayByClass_Expensive( "info_spawnpoint_titan_start" ) )
    allPoints.extend( GetEntArrayByClass_Expensive( "info_replacement_titan_spawn" ) )

    // get valid points from all points
    foreach( entity point in allPoints )
    {
        if( Distance2D( point.GetOrigin(), teamHarvester.GetOrigin() ) <= FW_SPAWNPOINT_SEARCH_RADIUS )
            validSpawnPoints.append( point )
    }

    return validSpawnPoints
}

void function EntityEnterFWTrig( entity trigger, entity ent, entity caller, var value )
{
    if( !IsValid( ent ) ) // post-spawns
        return
    if( !ent.IsPlayer() && !ent.IsNPC() ) // no neet to add props i guess
        return
    // functions that trigger_multiple missing
    if( IsValid( ent ) )
    {
        ScriptTriggerAddEntity( trigger, ent )
        thread ScriptTriggerPlayerDisconnectThink( trigger, ent )
    }

    if( !IsValid(ent) )
        return
    if ( ent.IsPlayer() ) // notifications for player
    {
        MessageToPlayer( ent, eEventNotifications.Clear ) // clean up
        bool sameTeam = ent.GetTeam() == trigger.GetTeam()
        if ( sameTeam )
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyEnterFriendlyArea" )
        else
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyEnterEnemyArea" )
    }
}

void function EntityLeaveFWTrig( entity trigger, entity ent, entity caller, var value )
{
    if( !IsValid( ent ) ) // post-spawns
        return
    if( !ent.IsPlayer() && !ent.IsNPC() ) // no neet to remove props i guess
        return
    // functions that trigger_multiple missing
    if( IsValid( ent ) )
    {
        if( ent in trigger.e.scriptTriggerData.entities ) // need to check this!
            ScriptTriggerRemoveEntity( trigger, ent )
    }

    if( !IsValid(ent) )
        return
    if ( ent.IsPlayer() ) // notifications for player
    {
        MessageToPlayer( ent, eEventNotifications.Clear ) // clean up
        bool sameTeam = ent.GetTeam() == trigger.GetTeam()
        if ( sameTeam )
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyExitFriendlyArea" )
        else
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyExitEnemyArea" )
    }
}

void function FWAreaThreatLevelThink()
{
    thread FWAreaThreatLevelThink_Threaded()
}

void function FWAreaThreatLevelThink_Threaded()
{
    entity imcTerritory
    entity mltTerritory
    foreach( entity territory in file.fwTerritories )
    {
        if( territory.GetTeam() == TEAM_IMC )
            imcTerritory = territory
        else
            mltTerritory = territory
    }

    float lastWarningTime // for debounce
    bool warnImcTitanApproach
    bool warnMltTitanApproach
    bool warnImcTitanInArea
    bool warnMltTitanInArea

    while( GetGameState() == eGameState.Playing )
    {
        //print( " imc threat level is: " + string( GetGlobalNetInt( "imcTowerThreatLevel" ) ) )
        //print( " mlt threat level is: " + string( GetGlobalNetInt( "milTowerThreatLevel" ) ) )
        float imcLastDamage = fw_harvesterImc.lastDamage
        float mltLastDamage = fw_harvesterMlt.lastDamage

        if( imcLastDamage + 5 >= Time() ) // harvester recent damaged
            SetGlobalNetInt( "imcTowerThreatLevel", 3 ) // 3 will show a "harvester being damaged" warning to player
        if( mltLastDamage + 5 >= Time() )
            SetGlobalNetInt( "milTowerThreatLevel", 3 ) // 3 will show a "harvester being damaged" warning to player

        if( warnImcTitanInArea && imcLastDamage + 5 < Time() )
            SetGlobalNetInt( "imcTowerThreatLevel", 2 ) // 2 will show a "titan in area" warning to player
        if( warnMltTitanInArea && imcLastDamage + 5 < Time() )
            SetGlobalNetInt( "milTowerThreatLevel", 2 ) // 2 will show a "titan in area" warning to player

        if( warnImcTitanApproach && !warnImcTitanInArea && imcLastDamage + 5 < Time() )
            SetGlobalNetInt( "imcTowerThreatLevel", 1 ) // 1 will show a "titan approach" waning to player
        if( warnImcTitanInArea && !warnMltTitanInArea && imcLastDamage + 5 < Time() )
            SetGlobalNetInt( "milTowerThreatLevel", 1 ) // 1 will show a "titan approach" waning to player

        if( imcLastDamage + 5 < Time() && !warnImcTitanInArea && !warnImcTitanApproach )
            SetGlobalNetInt( "imcTowerThreatLevel", 0 ) // 0 will hide all warnings
        if( mltLastDamage + 5 < Time() && !warnMltTitanInArea && !warnMltTitanApproach )
            SetGlobalNetInt( "milTowerThreatLevel", 0 ) // 0 will hide all warnings

        // clean it here
        warnImcTitanInArea = false
        warnMltTitanInArea = false
        warnImcTitanApproach = false
        warnMltTitanApproach = false

        array<entity> allTitans = GetNPCArrayByClass( "npc_titan" )
        array<entity> playerTitans = GetPlayerArray()
        foreach( entity player in playerTitans )
        {
            if( IsAlive( player ) && player.IsTitan() )
            {
                allTitans.append( player )
            }
        }

        array<entity> imcEntArray = GetAllEntitiesInTrigger( imcTerritory )
        array<entity> mltEntArray = GetAllEntitiesInTrigger( mltTerritory )
        foreach( entity ent in imcEntArray )
        {
            //print( ent )
            if( IsValid( ent ) ) // since we're using a fake trigger, good to have this
            {
                if( ent.IsPlayer() || ent.IsNPC() )
                {
                    if( ent.IsTitan() && ent.GetTeam() != TEAM_IMC )
                        warnImcTitanInArea = true
                }
            }
        }
        foreach( entity ent in mltEntArray )
        {
            //print( ent )
            if( IsValid( ent ) ) // since we're using a fake trigger, good to have this
            {
                if( ent.IsPlayer() || ent.IsNPC() )
                {
                    if( ent.IsTitan() && ent.GetTeam() != TEAM_MILITIA )
                        warnMltTitanInArea = true
                }
            }
        }

        foreach( entity titan in allTitans )
        {
            if( !imcEntArray.contains( titan ) 
                && !mltEntArray.contains( titan ) 
                && titan.GetTeam() != TEAM_IMC
                && !titan.e.isHotDropping )
                warnImcTitanApproach = true // this titan must be in neatural space
            if( !mltEntArray.contains( titan ) 
                && !imcEntArray.contains( titan ) 
                && titan.GetTeam() != TEAM_MILITIA
                && !titan.e.isHotDropping )
                warnMltTitanApproach = true // this titan must be in neatural space
        }

        WaitFrame()
    }
}

void function startFWHarvester()
{
    thread HarvesterThink(fw_harvesterMlt)
	thread HarvesterAlarm(fw_harvesterMlt)
    thread HarvesterThink(fw_harvesterImc)
	thread HarvesterAlarm(fw_harvesterImc)
    thread UpdateHarvesterHealth( TEAM_IMC )
    thread UpdateHarvesterHealth( TEAM_MILITIA )
}



void function LoadEntities()
{
	foreach ( entity info_target in GetEntArrayByClass_Expensive( "info_target" ) )
	{
		if( info_target.HasKey( "editorclass" ) )
		{
			switch( info_target.kv.editorclass )
			{
				case "info_fw_team_tower":
                    if ( info_target.GetTeam() == TEAM_MILITIA )
                    {
                        //entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
					    file.harvesterMlt_info = info_target
                        print("fw_tower tracker spawned")
                    }
                    if ( info_target.GetTeam() == TEAM_IMC )
                    {
                        //entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
					    file.harvesterImc_info = info_target
                        print("fw_tower tracker spawned")
                    }
                    break
                case "info_fw_camp":
                    //entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
                    InitCampTracker( info_target )
                    print("fw_camp spawned")
                    break
                case "info_fw_turret_site":
                    print("info_fw_turret_siteID : " + expect string(info_target.kv.turretId) )
                    // set this for replace function to find
                    TurretSite turretsite
                    turretsite.site = info_target
                    file.turretsites.append( turretsite ) 

                    // create turret
                    entity turret = CreateNPC( "npc_turret_mega", info_target.GetTeam(), info_target.GetOrigin(), info_target.GetAngles() )
                    SetSpawnOption_AISettings( turret, "npc_turret_mega_fortwar" )
                    SetDefaultMPEnemyHighlight( turret ) // for sonar highlights to work
                    AddEntityCallback_OnDamaged( turret, OnMegaTurretDamaged )
                    DispatchSpawn( turret )
                    turretsite.turret = turret

                    // minimap icons
                    entity minimapstate = CreateEntity( "prop_script" )
                    minimapstate.SetValueForModelKey( info_target.GetModelName() )
                    minimapstate.SetOrigin( info_target.GetOrigin() )
                    minimapstate.SetAngles( info_target.GetAngles() )
                    SetTeam( minimapstate, info_target.GetTeam() )
                    minimapstate.kv.solid = SOLID_VPHYSICS
                    DispatchSpawn( minimapstate )
                    turret.s.minimapstate <- minimapstate
                    break
			}
		}
	}
    foreach ( entity script_ref in GetEntArrayByClass_Expensive( "script_ref" ) )
	{
		if( script_ref.HasKey( "editorclass" ) )
		{
			switch( script_ref.kv.editorclass )
			{
                case "info_fw_foundation_plate":
                    entity prop = CreatePropDynamic( script_ref.GetModelName(), script_ref.GetOrigin(), script_ref.GetAngles(), 6 )
                    break
                case "info_fw_battery_port":
                    entity prop = CreatePropDynamic( script_ref.GetModelName(), script_ref.GetOrigin(), script_ref.GetAngles(), 6 )
                    prop.kv.fadedist = 10000 // try not to fade
                    InitTurretBatteryPort( prop )
                    break
			}
		}
	}
    foreach ( entity trigger_multiple in GetEntArrayByClass_Expensive( "trigger_multiple" ) )
	{
        if( trigger_multiple.HasKey( "editorclass" ) )
		{
			switch( trigger_multiple.kv.editorclass )
			{
                case "trigger_fw_territory":
                    SetupFWTerritoryTrigger( trigger_multiple )
                    break
			}
		}
    }
	ValidateAndFinalizePendingStationaryPositions()
	initNetVars()
	//SetTeam( GetTeamEnt( TEAM_IMC ), TEAM_IMC )
}

// for battery_port, replace the turret with new one
entity function FW_ReplaceMegaTurretFromTurretInfo( entity info_target )
{
    TurretSite curTurretSite
    // find turretSiteStruct and add it
    foreach( TurretSite turretsite in file.turretsites )
    {
        if( turretsite.site == info_target )
            curTurretSite = turretsite
    }

    entity perviousTurret = curTurretSite.turret // get previous turret
    if( !IsValid( perviousTurret ) ) // previous turret not exist!
        return

    entity turret = CreateNPC( "npc_turret_mega", info_target.GetTeam(), info_target.GetOrigin(), info_target.GetAngles() )
    SetSpawnOption_AISettings( turret, "npc_turret_mega_fortwar" )
    SetDefaultMPEnemyHighlight( turret ) // for sonar highlights to work
    AddEntityCallback_OnDamaged( turret, OnMegaTurretDamaged )
    DispatchSpawn( turret )

    // apply settings to new turret, must up on date
    turret.s.IsOrigin <- perviousTurret.s.IsOrigin
    turret.s.minimapstate <- perviousTurret.s.minimapstate
    turret.s.turretflagid <- perviousTurret.s.turretflagid

    // update turretSiteStruct
    foreach( TurretSite turretsite in file.turretsites )
    {
        if( turretsite.site == info_target )
        {
            turretsite.turret = turret // only changed this
        }
    }
    
    perviousTurret.Destroy() // destroy previous one
    
    return turret
}

// can only get turrets create from CreateMegaTurretFromTurretInfo()
entity function FW_GetTurretInfoFromMegaTurret( entity turret )
{
    foreach( TurretSite turretsite in file.turretsites )
    {
        if( turretsite.turret == turret )
            return turretsite.site
    }
}

void function FW_createHarvester()
{
	fw_harvesterMlt = SpawnHarvester( file.harvesterMlt_info.GetOrigin(), file.harvesterMlt_info.GetAngles(), GetCurrentPlaylistVarInt( "fd_harvester_health", 25000 ), GetCurrentPlaylistVarInt( "fd_harvester_shield", 6000 ), TEAM_MILITIA )
    fw_harvesterMlt.harvester.Minimap_SetAlignUpright( true )
	fw_harvesterMlt.harvester.Minimap_AlwaysShow( TEAM_IMC, null )
	fw_harvesterMlt.harvester.Minimap_AlwaysShow( TEAM_MILITIA, null )
	fw_harvesterMlt.harvester.Minimap_SetHeightTracking( true )
	fw_harvesterMlt.harvester.Minimap_SetZOrder( MINIMAP_Z_OBJECT )
	fw_harvesterMlt.harvester.Minimap_SetCustomState( eMinimapObject_prop_script.FD_HARVESTER )
	AddEntityCallback_OnDamaged( fw_harvesterMlt.harvester, OnHarvesterDamaged )
    //Highlight_SetEnemyHighlight( fw_harvesterMlt.harvester, "fw_enemy" ) // fw's harvester needs this
    // don't set this, or sonar pulse will try to find it and failed to set highlight
    //fw_harvesterMlt.harvester.SetScriptName("fw_team_tower")

    fw_harvesterImc = SpawnHarvester( file.harvesterImc_info.GetOrigin(), file.harvesterImc_info.GetAngles(), GetCurrentPlaylistVarInt( "fd_harvester_health", 25000 ), GetCurrentPlaylistVarInt( "fd_harvester_shield", 6000 ), TEAM_IMC )
	fw_harvesterImc.harvester.Minimap_SetAlignUpright( true )
	fw_harvesterImc.harvester.Minimap_AlwaysShow( TEAM_IMC, null )
	fw_harvesterImc.harvester.Minimap_AlwaysShow( TEAM_MILITIA, null )
	fw_harvesterImc.harvester.Minimap_SetHeightTracking( true )
	fw_harvesterImc.harvester.Minimap_SetZOrder( MINIMAP_Z_OBJECT )
	fw_harvesterImc.harvester.Minimap_SetCustomState( eMinimapObject_prop_script.FD_HARVESTER )
    AddEntityCallback_OnDamaged( fw_harvesterImc.harvester, OnHarvesterDamaged )
    //Highlight_SetEnemyHighlight( fw_harvesterMlt.harvester, "fw_enemy" ) // fw's harvester needs this
    // don't set this, or sonar pulse will try to find it and failed to set highlight
    //fw_harvesterImc.harvester.SetScriptName("fw_team_tower")

    entity trackerMlt = GetAvailableBaseLocationTracker( )
    trackerMlt.SetOwner(fw_harvesterMlt.harvester)
    DispatchSpawn( trackerMlt )
    entity trackerImc = GetAvailableBaseLocationTracker( )
    trackerImc.SetOwner(fw_harvesterImc.harvester)
    DispatchSpawn( trackerImc )
    SetLocationTrackerRadius( trackerMlt , 65535 ) // whole map
    SetLocationTrackerRadius( trackerImc , 65535 ) // whole map

    // scores starts from 100
    GameRules_SetTeamScore( TEAM_MILITIA , 100)
    GameRules_SetTeamScore( TEAM_IMC , 100)
    GameRules_SetTeamScore2( TEAM_MILITIA , 100)
    GameRules_SetTeamScore2( TEAM_IMC , 100)
}

void function OnHarvesterDamaged( entity harvester, var damageInfo )
{
	if ( !IsValid( harvester ) )
		return

    GameRules_SetTeamScore( harvester.GetTeam() , 1.0 * GetHealthFrac( harvester ) * 100 )

    int damageSourceID = DamageInfo_GetDamageSourceIdentifier( damageInfo )
    entity attacker = DamageInfo_GetAttacker( damageInfo )
    float damageAmount = DamageInfo_GetDamage( damageInfo )

    if ( !damageSourceID && !damageAmount && !attacker )
        return

    HarvesterStruct harvesterstruct // current harveter's struct
    if( harvester.GetTeam() == TEAM_MILITIA )
        harvesterstruct = fw_harvesterMlt
    if( harvester.GetTeam() == TEAM_IMC )
        harvesterstruct = fw_harvesterImc

    if ( harvester.GetShieldHealth() - damageAmount <= 0 )
    {
        if ( !attacker.IsTitan() && attacker.IsPlayer() )
        {
            Remote_CallFunction_NonReplay( attacker , "ServerCallback_FW_NotifyTitanRequired" )
            DamageInfo_SetDamage( damageInfo, harvester.GetShieldHealth() )
            return
        }
        if( !harvesterstruct.harvesterShieldDown )
        {
            PlayFactionDialogueToTeam( "fortwar_baseShieldDownFriendly", harvester.GetTeam() )
            PlayFactionDialogueToTeam( "fortwar_baseShieldDownEnemy", GetOtherTeam(harvester.GetTeam()) )
            harvesterstruct.harvesterShieldDown = true // prevent shield dialogues from repeating
        }
        harvesterstruct.harvesterDamageTaken = harvesterstruct.harvesterDamageTaken + damageAmount // track damage for wave recaps
        float newHealth = harvester.GetHealth() - damageAmount
        float oldhealthpercent = ( ( harvester.GetHealth().tofloat() / harvester.GetMaxHealth() ) * 100 )
        float healthpercent = ( ( newHealth / harvester.GetMaxHealth() ) * 100 )

        if (healthpercent <= 75 && oldhealthpercent > 75) // we don't want the dialogue to keep saying "Harvester is below 75% health" everytime they take additional damage
        {
            PlayFactionDialogueToTeam( "fortwar_baseDmgFriendly75", harvester.GetTeam() )
            PlayFactionDialogueToTeam( "fortwar_baseDmgEnemy75", GetOtherTeam(harvester.GetTeam()) )
        }

        if (healthpercent <= 50 && oldhealthpercent > 50)
        {
            PlayFactionDialogueToTeam( "fortwar_baseDmgFriendly50", harvester.GetTeam() )
            PlayFactionDialogueToTeam( "fortwar_baseDmgEnemy50", GetOtherTeam(harvester.GetTeam()) )
        }

        if (healthpercent <= 25 && oldhealthpercent > 25)
        {
            PlayFactionDialogueToTeam( "fortwar_baseDmgFriendly25", harvester.GetTeam() )
            PlayFactionDialogueToTeam( "fortwar_baseDmgEnemy25", GetOtherTeam(harvester.GetTeam()) )
        }

        if (healthpercent <= 10)
        {
            //PlayFactionDialogueToTeam( "fd_baseLowHealth", TEAM_MILITIA )
        }

        if( newHealth <= 0 )
        {
            EmitSoundAtPosition(TEAM_UNASSIGNED,harvesterstruct.harvester.GetOrigin(),"coop_generator_destroyed")
            newHealth = 0
            //PlayFactionDialogueToTeam( "fd_baseDeath", TEAM_MILITIA )
            harvesterstruct.rings.Destroy()
            harvesterstruct.harvester.Dissolve( ENTITY_DISSOLVE_CORE, Vector( 0, 0, 0 ), 500 )
        }
        harvester.SetHealth( newHealth )
        harvesterstruct.havesterWasDamaged = true
    }

    if ( damageSourceID == eDamageSourceId.mp_titancore_laser_cannon )
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/100 ) // laser core shreds super well for some reason

    if ( damageSourceID == eDamageSourceId.mp_titanweapon_flightcore_rockets )
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/4 ) // flight core shreds super well for some reason

    if ( damageSourceID == eDamageSourceId.mp_titanweapon_meteor ||
        damageSourceID == eDamageSourceId.mp_titanweapon_flame_wall ||
        damageSourceID == eDamageSourceId.mp_titanability_slow_trap
    )
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/3 ) // nerf scorch

    if ( attacker.IsPlayer() )
    {
        attacker.NotifyDidDamage( harvester, DamageInfo_GetHitBox( damageInfo ), DamageInfo_GetDamagePosition( damageInfo ), DamageInfo_GetCustomDamageType( damageInfo ), DamageInfo_GetDamage( damageInfo ), DamageInfo_GetDamageFlags( damageInfo ), DamageInfo_GetHitGroup( damageInfo ), DamageInfo_GetWeapon( damageInfo ), DamageInfo_GetDistFromAttackOrigin( damageInfo ) )
        //attacker.AddToPlayerGameStat( PGS_PILOT_KILLS, DamageInfo_GetDamage( damageInfo ) * 0.01 )
    }

    harvesterstruct.lastDamage = Time()
    if ( harvester.GetHealth() == 0 )
        SetWinner( GetOtherTeam( harvester.GetTeam() ) )
}

void function OnMegaTurretDamaged( entity turret, var damageInfo )
{
    int damageSourceID = DamageInfo_GetDamageSourceIdentifier( damageInfo )
    entity attacker = DamageInfo_GetAttacker( damageInfo )
    float damageAmount = DamageInfo_GetDamage( damageInfo )
    int scriptType = DamageInfo_GetCustomDamageType( damageInfo )

    if( turret.GetShieldHealth() - damageAmount <= 0 && scriptType != damageTypes.rodeoBatteryRemoval ) // shield down
    {
        if ( !attacker.IsTitan() && attacker.IsPlayer() )
        {
            if( attacker.GetTeam() != turret.GetTeam() ) // good to have
                MessageToPlayer( attacker, eEventNotifications.TurretTitanDamageOnly )
            DamageInfo_SetDamage( damageInfo, turret.GetShieldHealth() )
            return
        }
    }
    if ( damageSourceID == eDamageSourceId.mp_titanweapon_meteor ||
        damageSourceID == eDamageSourceId.mp_titanweapon_flame_wall ||
        damageSourceID == eDamageSourceId.mp_titanability_slow_trap
    )
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/2 ) // nerf scorch
    if( turret.GetHealth() <= DamageInfo_GetDamage( damageInfo ) ) // killshot
    {
        string flag = expect string( turret.s.turretflagid )
        SetGlobalNetInt( "turretStateFlags" + flag, 1 ) // set turretSite to grey until it gets fixed
        return // don't trigger icon changes
    }

    TurretFlagDamageCallback( turret, damageInfo ) // this will affect turret's icons
}

void function TurretFlagDamageCallback( entity turret, var damageInfo )
{
    if ( !IsValid( turret ) )
        return
    bool isorigin = expect bool( turret.s.IsOrigin )
    if ( isorigin )
    {
        thread TurretFlagOnDamage_threaded( turret )
        return
    }
    thread NeturalTurretFlagOnDamage_threaded( turret )
}

void function TurretFlagOnDamage_threaded( entity turret )
{
    turret.Signal( "FlashTurretFlag" )
    turret.EndSignal( "FlashTurretFlag" ) // save for continously damages
    turret.EndSignal( "OnDeath" ) // end the function for deaths
    string flag = expect string( turret.s.turretflagid )
    if ( turret.GetTeam() == TEAM_IMC )
    {
        SetGlobalNetInt( "turretStateFlags" + flag, 26 )
        wait 2
        SetGlobalNetInt( "turretStateFlags" + flag, 10 )
        return
    }
    if( turret.GetTeam() == TEAM_MILITIA )
    {
        SetGlobalNetInt( "turretStateFlags" + flag, 28 )
        wait 2
        SetGlobalNetInt( "turretStateFlags" + flag, 13 )
        return
    }
}

void function NeturalTurretFlagOnDamage_threaded( entity turret )
{
    turret.Signal( "FlashTurretFlag" )
    turret.EndSignal( "FlashTurretFlag" ) // save for continously damages
    turret.EndSignal( "OnDeath" ) // end the function for deaths
    string flag = expect string( turret.s.turretflagid )
    if ( turret.GetTeam() == TEAM_IMC )
    {
        SetGlobalNetInt( "turretStateFlags" + flag, 18 )
        wait 2
        SetGlobalNetInt( "turretStateFlags" + flag, 2 )
        return
    }
    if( turret.GetTeam() == TEAM_MILITIA )
    {
        SetGlobalNetInt( "turretStateFlags" + flag, 21 )
        wait 2
        SetGlobalNetInt( "turretStateFlags" + flag, 4 )
        return
    }
    if ( GetGlobalNetInt( "turretStateFlags" + flag ) != 16 )
    {
        SetGlobalNetInt( "turretStateFlags" + flag, 16 )
        wait 2
        SetGlobalNetInt( "turretStateFlags" + flag, 1 )
        return
    }
}

void function initNetVars()
{
    foreach( turret in file.turretsites )
    {
        int id = int( string( turret.site.kv.turretId ) )
        string idString = string( id + 1 )
        int team = turret.turret.GetTeam()
        int stateFlag = 1 // netural
        turret.turret.s.IsOrigin <- false
        if( team == TEAM_IMC )
        {
            stateFlag = 10 // 10 means origin TEAM_IMC turret
            turret.turret.s.IsOrigin = true
        }
        if( team == TEAM_MILITIA )
        {
            stateFlag = 13 // 13 means origin TEAM_MILITIA turret
            turret.turret.s.IsOrigin = true
        }

        SetGlobalNetEnt( "turretSite" + idString, turret.turret )
        SetGlobalNetInt( "turretStateFlags" + idString, stateFlag )
        turret.turret.s.turretflagid <- idString
        TurretSiteWatcher( turret )
    }

    // camps don't have a id, set them manually
    foreach( int index, CampSiteStruct camp in file.fwCampSites )
    {
        if ( index == 0 )
        {
            camp.campId = "A"
            SetGlobalNetInt( "fwCampAlertA", 0 )
            SetGlobalNetInt( "fwCampStressA", 1 )
            // can't use float rn
            //SetGlobalNetFloat( "fwCampStressA", 1.0 )
            SetLocationTrackerID( camp.tracker, 0 )
            file.trackedCampNPCSpawns["A"] <- {}
            continue
        }
        if ( index == 1 )
        {
            camp.campId = "B"
            SetGlobalNetInt( "fwCampAlertB", 0 )
            SetGlobalNetInt( "fwCampStressB", 1 )
            // can't use float rn
            //SetGlobalNetFloat( "fwCampStressB", 1.0 )
            SetLocationTrackerID( camp.tracker, 1 )
            file.trackedCampNPCSpawns["B"] <- {}
            continue
        }
        if ( index == 2 )
        {
            camp.campId = "C"
            SetGlobalNetInt( "fwCampAlertC", 0 )
            SetGlobalNetInt( "fwCampStressC", 1 )
            // can't use float rn
            //SetGlobalNetFloat( "fwCampStressC", 1.0 )
            SetLocationTrackerID( camp.tracker, 2 )
            file.trackedCampNPCSpawns["C"] <- {}
            continue
        }
    }

}

void function TurretSiteWatcher( TurretSite turret )
{
    //expect entity(turret.turret.s.minimapstate)
    //entity megaturret = turret.turret.s.minimapstate
    entity megaturret = expect entity( turret.turret.s.minimapstate )
    if ( turret.turret.GetTeam() == TEAM_MILITIA || turret.turret.GetTeam() == TEAM_IMC )
    {
	    megaturret.Minimap_AlwaysShow( TEAM_IMC, null )
	    megaturret.Minimap_AlwaysShow( TEAM_MILITIA, null )
        megaturret.Minimap_SetCustomState( eMinimapObject_prop_script.FW_BUILDSITE_SHIELDED )
    }
    else
    {
        SetTeam( megaturret, 1 )
	    megaturret.Minimap_AlwaysShow( TEAM_IMC, null )
	    megaturret.Minimap_AlwaysShow( TEAM_MILITIA, null )
        megaturret.Minimap_SetCustomState( eMinimapObject_prop_script.FW_BUILDSITE_SHIELDED )
    }
    turret.turret.SetMaxHealth( 20000 )
    turret.turret.SetHealth( 20000 )
    turret.turret.SetShieldHealthMax( 10000 )
}

void function HarvesterThink( HarvesterStruct fd_harvester )
{
	entity harvester = fd_harvester.harvester


	EmitSoundOnEntity( harvester, "coop_generator_startup" )

	float lastTime = Time()
	wait 4
	int lastShieldHealth = harvester.GetShieldHealth()
	generateBeamFX( fd_harvester )
	generateShieldFX( fd_harvester )

	EmitSoundOnEntity( harvester, "coop_generator_ambient_healthy" )

	bool isRegening = false // stops the regenning sound to keep stacking on top of each other

	while ( IsAlive( harvester ) )
	{
		float currentTime = Time()
		float deltaTime = currentTime -lastTime

		if ( IsValid( fd_harvester.particleShield ) )
		{
			vector shieldColor = GetShieldTriLerpColor( 1.0 - ( harvester.GetShieldHealth().tofloat() / harvester.GetShieldHealthMax().tofloat() ) )
			EffectSetControlPointVector( fd_harvester.particleShield, 1, shieldColor )
		}

		if( IsValid( fd_harvester.particleBeam ) )
		{
			vector beamColor = GetShieldTriLerpColor( 1.0 - ( harvester.GetHealth().tofloat() / harvester.GetMaxHealth().tofloat() ) )
			EffectSetControlPointVector( fd_harvester.particleBeam, 1, beamColor )
		}

		if ( fd_harvester.harvester.GetShieldHealth() == 0 )
			if( IsValid( fd_harvester.particleShield ) )
				fd_harvester.particleShield.Destroy()

		if ( ( ( currentTime-fd_harvester.lastDamage ) >= GENERATOR_SHIELD_REGEN_DELAY ) && ( harvester.GetShieldHealth() < harvester.GetShieldHealthMax() ) )
		{
			if( !IsValid( fd_harvester.particleShield ) )
				generateShieldFX( fd_harvester )

			//printt((currentTime-fd_harvester.lastDamage))

			if( harvester.GetShieldHealth() == 0 )
				EmitSoundOnEntity( harvester, "coop_generator_shieldrecharge_start" )

			if (!isRegening)
			{
				EmitSoundOnEntity( harvester, "coop_generator_shieldrecharge_resume" )
				fd_harvester.harvesterShieldDown = false
				//if (GetGlobalNetBool( "FD_waveActive" ) )
					//PlayFactionDialogueToTeam( "fd_baseShieldRecharging", TEAM_MILITIA )
				//else
					//PlayFactionDialogueToTeam( "fd_baseShieldRechargingShort", TEAM_MILITIA )
				isRegening = true
			}

			float newShieldHealth = ( harvester.GetShieldHealthMax() / GENERATOR_SHIELD_REGEN_TIME * deltaTime ) + harvester.GetShieldHealth()

			if ( newShieldHealth >= harvester.GetShieldHealthMax() )
			{
				StopSoundOnEntity( harvester, "coop_generator_shieldrecharge_resume" )
				harvester.SetShieldHealth( harvester.GetShieldHealthMax() )
				EmitSoundOnEntity( harvester, "coop_generator_shieldrecharge_end" )
				//if( GetGlobalNetBool( "FD_waveActive" ) )
					//PlayFactionDialogueToTeam( "fd_baseShieldUp", TEAM_MILITIA )
				isRegening = false
			}
			else
			{
				harvester.SetShieldHealth( newShieldHealth )
			}
		} else if ( ( ( currentTime-fd_harvester.lastDamage ) < GENERATOR_SHIELD_REGEN_DELAY ) && ( harvester.GetShieldHealth() < harvester.GetShieldHealthMax() ) )
			isRegening = false

		if ( ( lastShieldHealth > 0 ) && ( harvester.GetShieldHealth() == 0 ) )
        {
            EmitSoundOnEntity( harvester, "TitanWar_Harvester_ShieldDown" ) // add this
			EmitSoundOnEntity( harvester, "coop_generator_shielddown" )
        }

		lastShieldHealth = harvester.GetShieldHealth()
		lastTime = currentTime
		WaitFrame()
	}

}

void function HarvesterAlarm( HarvesterStruct fd_harvester )
{
	while( IsAlive( fd_harvester.harvester ) )
	{
		if( fd_harvester.harvester.GetShieldHealth() == 0 )
		{
			wait EmitSoundOnEntity( fd_harvester.harvester, "coop_generator_underattack_alarm" )
		}
		else
		{
			WaitFrame()
		}
	}
}

void function UpdateHarvesterHealth( int team )
{
    entity harvester
    if( team == TEAM_MILITIA )
        harvester = fw_harvesterMlt.harvester
    if( team == TEAM_IMC )
        harvester = fw_harvesterImc.harvester

    while( true )
    {
        if( IsValid(harvester) )
        {
            GameRules_SetTeamScore2(team, 1.0 * harvester.GetShieldHealth()/harvester.GetShieldHealthMax() * 100 )
            WaitFrame()
        }
        else
        {
            SetWinner( GetOtherTeam(team) )
            break
        }
    }
}
