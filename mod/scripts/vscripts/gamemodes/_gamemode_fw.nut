untyped
global function GamemodeFW_Init
global function RateSpawnpoints_FW

// i don't know how to use playlists in keyvalues folder, let's change maps manually
const array<string> FW_ALLOWED_MAPS =
[
    "mp_forwardbase_kodai",
    "mp_grave",
    "mp_homestead",
    "mp_thaw",
    "mp_eden",
    "mp_crashsite3",
    "mp_complex3"
]

// for battery_port.gnut to work
global function FW_ReplaceMegaTurret

// fw specific titanfalls
global function FW_PlayerInFriendlyTerritory
global function FW_ReCalculateTitanReplacementPoint

// default havester settings
const int FW_DEFAULT_HARVESTER_HEALTH = 25000
const int FW_DEFAULT_HARVESTER_SHIELD = 5000
// default turret settings
const int FW_DEFAULT_TURRET_HEALTH = 12500
const int FW_DEFAULT_TURRET_SHIELD = 4000

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

// debounce for showing damaged infos
const float FW_HARVESTER_DAMAGED_DEBOUNCE = 5.0
const float FW_TURRET_DAMAGED_DEBOUNCE = 2.0

global HarvesterStruct& fw_harvesterMlt
global HarvesterStruct& fw_harvesterImc

//array< HarvesterStruct& > harvesters = [ fw_harvesterMlt , fw_harvesterImc ]
struct TurretSiteStruct
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
    int npcsAlive
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

    array<TurretSiteStruct> turretsites

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
    AiGameModes_SetGruntWeapons( [ "mp_weapon_rspn101", "mp_weapon_dmr", "mp_weapon_r97", "mp_weapon_lmg" ] )
	AiGameModes_SetSpectreWeapons( [ "mp_weapon_hemlok_smg", "mp_weapon_doubletake", "mp_weapon_mastiff" ] )

    AddCallback_EntitiesDidLoad( LoadEntities )
    AddCallback_GameStateEnter( eGameState.Prematch, OnFWGamePrematch )
    AddCallback_GameStateEnter( eGameState.Playing, OnFWGamePlaying )

    AddSpawnCallback( "item_powerup", FWAddPowerUpIcon )

    ScoreEvent_SetupEarnMeterValuesForMixedModes()

    ClassicMP_ForceDisableEpilogue( true ) // temp

    // temp, force change maps
    AddCallback_GameStateEnter( eGameState.Postmatch, FWForceChangeMap )
}

//////////////////////////
///// TEMP FUNCTIONS /////
//////////////////////////

void function FWForceChangeMap()
{
    thread FWForceChangeMap_Threaded()
}

void function FWForceChangeMap_Threaded()
{
    wait 5

    string mapName = GetMapName()
    int curMapIdx = FW_ALLOWED_MAPS.find( mapName )

    int nextMapIdx = curMapIdx + 1
    if( nextMapIdx + 1 > FW_ALLOWED_MAPS.len() ) // last map
        nextMapIdx = 0

    GameRules_ChangeMap( FW_ALLOWED_MAPS[ nextMapIdx ], "fw" )
}

//////////////////////////////
///// TEMP FUNCTIONS END /////
//////////////////////////////



////////////////////////////////
///// SPAWNPOINT FUNCTIONS /////
////////////////////////////////

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

////////////////////////////////////
///// SPAWNPOINT FUNCTIONS END /////
////////////////////////////////////



//////////////////////////////
///// CALLBACK FUNCTIONS /////
//////////////////////////////

void function OnFWGamePrematch()
{
    InitFWScoreEvents()
    FW_createHarvester()
    InitFWCampSites()
    InitCampSpawnerLevel()
}

void function OnFWGamePlaying()
{
    startFWHarvester()
    FWAreaThreatLevelThink()
    StartFWCampThink()
    InitTurretSettings()
}

//////////////////////////////////
///// CALLBACK FUNCTIONS END /////
//////////////////////////////////


//////////////////////////////////
///// SCORE EVENTS FUNCTIONS /////
//////////////////////////////////

void function InitFWScoreEvents()
{
    // current using scoreEvents
    ScoreEvent_SetEarnMeterValues( "KillHeavyTurret", 0.0, 0.20 ) // only adds to titan's in this mode

    // save for later use of scoreEvents
	ScoreEvent_SetEarnMeterValues( "FortWarAssault", 0.10, 0.15 )
	ScoreEvent_SetEarnMeterValues( "FortWarDefense", 0.05, 0.10 )
	ScoreEvent_SetEarnMeterValues( "FortWarPerimeterDefense", 0.05, 0.10 )
	ScoreEvent_SetEarnMeterValues( "FortWarSiege", 0.1, 0.15 )
	ScoreEvent_SetEarnMeterValues( "FortWarSnipe", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarBaseConstruction", 0.1, 0.15 )
	ScoreEvent_SetEarnMeterValues( "FortWarForwardConstruction", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarInvasiveConstruction", 0.1, 0.15 )
	ScoreEvent_SetEarnMeterValues( "FortWarResourceDenial", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarTowerDamage", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarTowerDefense", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarTeamTurretControlBonus_One", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarTeamTurretControlBonus_Two", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarTeamTurretControlBonus_Three", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarTeamTurretControlBonus_Four", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarTeamTurretControlBonus_Five", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarTeamTurretControlBonus_Six", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarSecuringGatheredResources", 0.1, 0.15 )
    ScoreEvent_SetEarnMeterValues( "FortWarShieldDestroyed", 0.1, 0.15 )
}

//////////////////////////////////////
///// SCORE EVENTS FUNCTIONS END /////
//////////////////////////////////////



////////////////////////////////
///// INITIALIZE FUNCTIONS /////
////////////////////////////////

void function LoadEntities()
{
    // info_target
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
                        //print("fw_tower tracker spawned")
                    }
                    if ( info_target.GetTeam() == TEAM_IMC )
                    {
                        //entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
					    file.harvesterImc_info = info_target
                        //print("fw_tower tracker spawned")
                    }
                    break
                case "info_fw_camp":
                    //entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
                    InitCampTracker( info_target )
                    //print("fw_camp spawned")
                    break
                case "info_fw_turret_site":

                    string idString = expect string(info_target.kv.turretId)
                    int id = int( info_target.kv.turretId )
                    //print("info_fw_turret_siteID : " + idString )

                    // set this for replace function to find
                    TurretSiteStruct turretsite
                    file.turretsites.append( turretsite )

                    turretsite.site = info_target

                    // create turret, spawn with no team and set it after game starts
                    entity turret = CreateNPC( "npc_turret_mega", TEAM_UNASSIGNED, info_target.GetOrigin(), info_target.GetAngles() )
                    SetSpawnOption_AISettings( turret, "npc_turret_mega_fortwar" )
                    SetDefaultMPEnemyHighlight( turret ) // for sonar highlights to work
                    AddEntityCallback_OnDamaged( turret, OnMegaTurretDamaged )
                    DispatchSpawn( turret )

                    turretsite.turret = turret

                    // init turret settings
                    turret.s.minimapstate <- null               // entity, for saving turret's minimap handler
                    turret.s.baseTurret <- false                // bool, is this turret from base
                    turret.s.turretflagid <- ""                 // string, turret's id like "1", "2", "3"
                    turret.s.lastDamagedTime <- 0.0             // float, for showing turret underattack icons
                    turret.s.relatedBatteryPort <- null         // entity, corssfile

                    // minimap icons
                    entity minimapstate = CreateEntity( "prop_script" )
                    minimapstate.SetValueForModelKey( info_target.GetModelName() )
                    minimapstate.SetOrigin( info_target.GetOrigin() )
                    minimapstate.SetAngles( info_target.GetAngles() )
                    //SetTeam( minimapstate, info_target.GetTeam() ) // setTeam() for icons is done in TurretStateWatcher()
                    minimapstate.kv.solid = SOLID_VPHYSICS
                    DispatchSpawn( minimapstate )

                    turretsite.minimapstate = minimapstate
                    turret.s.minimapstate = minimapstate
                    
                    break
			}
		}
	}

    // script_ref
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
                //case "script_power_up_other":
                //    entity powerUp = CreateEntity( "item_powerup" )
			}
		}
	}

    // trigger_multiple
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

    // maybe for tick_spawning reapers?
	ValidateAndFinalizePendingStationaryPositions()
}

void function InitCampSpawnerLevel() // can edit this to make more spawns, alertLevel icons supports max to lv3( 0,1,2 )
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

////////////////////////////////////
///// INITIALIZE FUNCTIONS END /////
////////////////////////////////////



/////////////////////////////
///// POWERUP FUNCTIONS /////
/////////////////////////////

void function FWAddPowerUpIcon( entity powerup )
{
    powerup.Minimap_SetAlignUpright( true )
	powerup.Minimap_SetZOrder( MINIMAP_Z_OBJECT )
    powerup.Minimap_SetClampToEdge( false )
    powerup.Minimap_AlwaysShow( TEAM_MILITIA, null )
    powerup.Minimap_AlwaysShow( TEAM_IMC, null )
}

/////////////////////////////////
///// POWERUP FUNCTIONS END /////
/////////////////////////////////



/////////////////////////////
///// AICAMPS FUNCTIONS /////
/////////////////////////////

void function InitFWCampSites()
{
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

void function InitCampTracker( entity camp )
{
    //print("InitCampTracker")
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
		guy.EnableNPCFlag( NPC_ALLOW_PATROL | NPC_ALLOW_HAND_SIGNALS | NPC_ALLOW_FLEE ) // NPC_ALLOW_INVESTIGATE is not allowed
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

// maybe this will make them stay around the camp
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
                guy.AssaultSetGoalRadius( float( camp.kv.radius ) / 2 ) // the camp's radius / 2
                guy.AssaultSetFightRadius( 0 )
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

/////////////////////////////////
///// AICAMPS FUNCTIONS END /////
/////////////////////////////////



///////////////////////////////
///// TERRITORY FUNCTIONS /////
///////////////////////////////

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
    //print("trigger_fw_territory detected")
    file.fwTerritories.append( trigger )
    trigger.ConnectOutput( "OnStartTouch", EntityEnterFWTrig )
	trigger.ConnectOutput( "OnEndTouch", EntityLeaveFWTrig )

    // respawn didn't leave a key for trigger's team, let's set it.
    if( Distance( trigger.GetOrigin(), file.harvesterMlt_info.GetOrigin() ) > Distance( trigger.GetOrigin(), file.harvesterImc_info.GetOrigin() ) )
        SetTeam( trigger, TEAM_IMC )
    else
        SetTeam( trigger, TEAM_MILITIA )
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

// globlized!
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

///////////////////////////////////
///// TERRITORY FUNCTIONS END /////
///////////////////////////////////



////////////////////////////////
///// TITANSPAWN FUNCTIONS /////
////////////////////////////////

// territory trigger don't have a kv.radius, let's use a const
// 1800 will pretty much get harvester's near titan startpoints
const float FW_SPAWNPOINT_SEARCH_RADIUS = 1800

// globalized!
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

////////////////////////////////////
///// TITANSPAWN FUNCTIONS END /////
////////////////////////////////////



/////////////////////////////////
///// THREATLEVEL FUNCTIONS /////
/////////////////////////////////

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
        bool imcShieldDown = fw_harvesterImc.harvesterShieldDown
        bool mltShieldDown = fw_harvesterMlt.harvesterShieldDown

        // imc threatLevel
        if( imcLastDamage + FW_HARVESTER_DAMAGED_DEBOUNCE >= Time() && imcShieldDown )
            SetGlobalNetInt( "imcTowerThreatLevel", 3 ) // 3 will show a "harvester being damaged" warning to player
        else if( warnImcTitanInArea )
            SetGlobalNetInt( "imcTowerThreatLevel", 2 ) // 2 will show a "titan in area" warning to player
        else if( warnImcTitanApproach )
            SetGlobalNetInt( "imcTowerThreatLevel", 1 ) // 1 will show a "titan approach" waning to player
        else
            SetGlobalNetInt( "imcTowerThreatLevel", 0 ) // 0 will hide all warnings

        // militia threatLevel
        if( mltLastDamage + FW_HARVESTER_DAMAGED_DEBOUNCE >= Time() && mltShieldDown )
            SetGlobalNetInt( "milTowerThreatLevel", 3 ) // 3 will show a "harvester being damaged" warning to player
        else if( warnMltTitanInArea )
            SetGlobalNetInt( "milTowerThreatLevel", 2 ) // 2 will show a "titan in area" warning to player
        else if( warnMltTitanApproach )
            SetGlobalNetInt( "milTowerThreatLevel", 1 ) // 1 will show a "titan approach" waning to player
        else
            SetGlobalNetInt( "milTowerThreatLevel", 0 ) // 0 will hide all warnings


        // clean it here
        warnImcTitanInArea = false
        warnMltTitanInArea = false
        warnImcTitanApproach = false
        warnMltTitanApproach = false

        // get valid titans
        array<entity> allTitans = GetNPCArrayByClass( "npc_titan" )
        array<entity> allPlayers = GetPlayerArray()
        foreach( entity player in allPlayers )
        {
            if( IsAlive( player ) && player.IsTitan() )
            {
                allTitans.append( player )
            }
        }

        // check threats
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

/////////////////////////////////////
///// THREATLEVEL FUNCTIONS END /////
/////////////////////////////////////



////////////////////////////
///// TURRET FUNCTIONS /////
////////////////////////////

// for battery_port, replace the turret with new one
entity function FW_ReplaceMegaTurret( entity perviousTurret )
{
    if( !IsValid( perviousTurret ) ) // previous turret not exist!
        return

    entity turret = CreateNPC( "npc_turret_mega", perviousTurret.GetTeam(), perviousTurret.GetOrigin(), perviousTurret.GetAngles() )
    SetSpawnOption_AISettings( turret, "npc_turret_mega_fortwar" )
    SetDefaultMPEnemyHighlight( turret ) // for sonar highlights to work
    AddEntityCallback_OnDamaged( turret, OnMegaTurretDamaged )
    DispatchSpawn( turret )

    // apply settings to new turret, must up on date
    turret.s.baseTurret <- perviousTurret.s.baseTurret
    turret.s.minimapstate <- perviousTurret.s.minimapstate
    turret.s.turretflagid <- perviousTurret.s.turretflagid
    turret.s.lastDamagedTime <- perviousTurret.s.lastDamagedTime
    turret.s.relatedBatteryPort <- perviousTurret.s.relatedBatteryPort

    int maxHealth = perviousTurret.GetMaxHealth()
    int maxShield = perviousTurret.GetShieldHealthMax()
    turret.SetMaxHealth( maxHealth )
    turret.SetHealth( maxHealth )
    turret.SetShieldHealth( maxShield )
    turret.SetShieldHealthMax( maxShield )

    // update turretSiteStruct
    foreach( TurretSiteStruct turretsite in file.turretsites )
    {
        if( turretsite.turret == perviousTurret )
        {
            turretsite.turret = turret // only changed this
        }
    }

    perviousTurret.Destroy() // destroy previous one

    return turret
}

void function OnMegaTurretDamaged( entity turret, var damageInfo )
{
    int damageSourceID = DamageInfo_GetDamageSourceIdentifier( damageInfo )
    entity attacker = DamageInfo_GetAttacker( damageInfo )
    float damageAmount = DamageInfo_GetDamage( damageInfo )
    int scriptType = DamageInfo_GetCustomDamageType( damageInfo )

    if ( !damageSourceID && !damageAmount && !attacker )
        return

    if( turret.GetShieldHealth() - damageAmount <= 0 && scriptType != damageTypes.rodeoBatteryRemoval ) // this shot breaks shield
    {
        if ( !attacker.IsTitan() && !IsSuperSpectre( attacker ) )
        {
            if( attacker.IsPlayer() && attacker.GetTeam() != turret.GetTeam() ) // good to have
                MessageToPlayer( attacker, eEventNotifications.TurretTitanDamageOnly )
            DamageInfo_SetDamage( damageInfo, turret.GetShieldHealth() )
            return
        }
    }

    // successfully damaged turret
    turret.s.lastDamagedTime = Time()

    if ( damageSourceID == eDamageSourceId.mp_titanweapon_meteor_thermite || 
        damageSourceID == eDamageSourceId.mp_titanweapon_flame_wall ||
        damageSourceID == eDamageSourceId.mp_titanability_slow_trap ||
        damageSourceID == eDamageSourceId.mp_titancore_flame_wave_secondary
    )
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/2 ) // nerf scorch
}

void function InitTurretSettings()
{
    foreach( TurretSiteStruct turretSite in file.turretsites )
    {
        entity turret = turretSite.turret
        entity minimapstate = turretSite.minimapstate
        int teamNum = turretSite.site.GetTeam()
        int id = int( string( turretSite.site.kv.turretId ) )
        string idString = string( id + 1 )
        int team = int( string( turretSite.site.kv.teamnumber ) )

        int stateFlag = 1 // netural

        // spawn with teamNumber?
        if( team == TEAM_IMC || team == TEAM_MILITIA ) 
            turret.s.baseTurret = true

        //SetTeam( minimapstate, team ) // setTeam() for icons is done in TurretStateWatcher()
        SetTeam( turret, team )

        //print( "Try to set globatNetEnt: " + "turretSite" + idString )   

        turret.s.turretflagid = idString
        turretSite.turretflagid = idString

        thread TurretStateWatcher( turretSite )
    }
}

// about networkvar "turretStateFlags" value
// 1 means destoryed/netural
// 2 means imc turret
// 4 means mlt turret
// 10 means shielded imc turret
// 13 means shielded mlt turret
// 16 means destoryed/netural being attacked
// 18 means imc turret being attacked
// 20 means mlt turret being attacked
// 26 means shielded imc turret being attacked
// 28 means shielded mlt turret being attacked

// unsure:
// 24 means destroyed imc turret being attacked?
// 40 means destroyed imc turret?
// 48 means destroyed mlt turret being attacked?

const int TURRET_DESTROYED_FLAG = 1
const int TURRET_NEATURAL_FLAG = 1
const int TURRET_IMC_FLAG = 2
const int TURRET_MLT_FLAG = 4
const int TURRET_SHIELDED_IMC_FLAG = 10
const int TURRET_SHIELDED_MLT_FLAG = 13

const int TURRET_UNDERATTACK_NEATURAL_FLAG = 16
const int TURRET_UNDERATTACK_IMC_FLAG = 18
const int TURRET_UNDERATTACK_MLT_FLAG = 20
// neatural turret noramlly can't get shield
const int TURRET_SHIELDED_UNDERATTACK_IMC_FLAG = 26
const int TURRET_SHIELDED_UNDERATTACK_MLT_FLAG = 28

void function TurretStateWatcher( TurretSiteStruct turretSite )
{
    entity mapIcon = turretSite.minimapstate
    entity turret = turretSite.turret
    entity batteryPort = expect entity( turret.s.relatedBatteryPort )

    mapIcon.Minimap_AlwaysShow( TEAM_IMC, null )
	mapIcon.Minimap_AlwaysShow( TEAM_MILITIA, null )
    mapIcon.Minimap_SetCustomState( eMinimapObject_prop_script.FW_BUILDSITE_SHIELDED )

    turret.SetMaxHealth( FW_DEFAULT_TURRET_HEALTH )
    turret.SetHealth( FW_DEFAULT_TURRET_HEALTH )
    turret.SetShieldHealthMax( FW_DEFAULT_TURRET_SHIELD )

    string idString = turretSite.turretflagid
    string siteVarName = "turretSite" + idString
    string stateVarName = "turretStateFlags" + idString

    mapIcon.EndSignal( "OnDestroy" ) // mapIcon should be valid all time, tracking it is enough

    if( IsValid( batteryPort ) ) // has a related batteryPort
    {
        SetGlobalNetEnt( siteVarName, batteryPort ) // tracking batteryPort's positions and team
        batteryPort.EndSignal( "OnDestroy" ) // also track this
    }
    else
        SetGlobalNetEnt( siteVarName, mapIcon ) // tracking mapIcon's positions and team

    SetGlobalNetInt( stateVarName, TURRET_NEATURAL_FLAG ) // init for all turrets

    while( true )
    {
        WaitFrame() // start of the loop

        turret = turretSite.turret // need to keep updating, for sometimes it being replaced

        if( !IsValid( turret ) ) // replacing turret this frame
            continue // skip the loop once

        bool isBaseTurret = expect bool( turret.s.baseTurret )

        if( !IsAlive( turret ) ) // turret down, waiting to be repaired
        {
            if( !isBaseTurret ) // never reset base turret's team
            {
                SetTeam( turret, TEAM_UNASSIGNED )
                SetTeam( mapIcon, TEAM_UNASSIGNED )
                if( IsValid( batteryPort ) )
                    SetTeam( batteryPort, TEAM_UNASSIGNED )
            }
            SetGlobalNetInt( stateVarName, TURRET_DESTROYED_FLAG )
            continue
        }
        
        int turretTeam = turret.GetTeam()
        int iconTeam = turretTeam == TEAM_BOTH ? TEAM_UNASSIGNED : turretTeam // specific check
        SetTeam( mapIcon, iconTeam ) // update icon's team

        float lastDamagedTime = expect float( turret.s.lastDamagedTime )
        int stateFlag = TURRET_NEATURAL_FLAG

        // imc states
        if( iconTeam == TEAM_IMC )
        {
            if( lastDamagedTime + FW_TURRET_DAMAGED_DEBOUNCE >= Time() ) // recent underattack
            {
                if( turret.GetShieldHealth() > 0 ) // has shields
                    stateFlag = TURRET_SHIELDED_UNDERATTACK_IMC_FLAG
                else
                    stateFlag = TURRET_UNDERATTACK_IMC_FLAG
            }
            else if( turret.GetShieldHealth() > 0 ) // has shields left
                stateFlag = TURRET_SHIELDED_IMC_FLAG
            else
                stateFlag = TURRET_IMC_FLAG
        }

        // mlt states
        if( iconTeam == TEAM_MILITIA )
        {
            if( lastDamagedTime + FW_TURRET_DAMAGED_DEBOUNCE >= Time() ) // recent underattack
            {
                if( turret.GetShieldHealth() > 0 ) // has shields
                    stateFlag = TURRET_SHIELDED_UNDERATTACK_MLT_FLAG
                else
                    stateFlag = TURRET_UNDERATTACK_MLT_FLAG
            }
            else if( turret.GetShieldHealth() > 0 ) // has shields left
                stateFlag = TURRET_SHIELDED_MLT_FLAG
            else
                stateFlag = TURRET_MLT_FLAG
        }
        
        // neatural states
        if( iconTeam == TEAM_UNASSIGNED )
        {
            if( lastDamagedTime + FW_TURRET_DAMAGED_DEBOUNCE >= Time() ) // recent underattack
                stateFlag = TURRET_UNDERATTACK_NEATURAL_FLAG
            else
                stateFlag = TURRET_NEATURAL_FLAG
        }

        SetGlobalNetInt( stateVarName, stateFlag )

        WaitFrame()
    }

}

////////////////////////////////
///// TURRET FUNCTIONS END /////
////////////////////////////////



///////////////////////////////
///// HARVESTER FUNCTIONS /////
///////////////////////////////

void function startFWHarvester()
{
    thread HarvesterThink(fw_harvesterMlt)
	thread HarvesterAlarm(fw_harvesterMlt)
    thread HarvesterThink(fw_harvesterImc)
	thread HarvesterAlarm(fw_harvesterImc)
    thread UpdateHarvesterHealth( TEAM_IMC )
    thread UpdateHarvesterHealth( TEAM_MILITIA )
}

void function FW_createHarvester()
{
	fw_harvesterMlt = SpawnHarvester( file.harvesterMlt_info.GetOrigin(), file.harvesterMlt_info.GetAngles(), GetCurrentPlaylistVarInt( "fd_harvester_health", FW_DEFAULT_HARVESTER_HEALTH ), GetCurrentPlaylistVarInt( "fd_harvester_shield", FW_DEFAULT_HARVESTER_SHIELD ), TEAM_MILITIA )
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

    fw_harvesterImc = SpawnHarvester( file.harvesterImc_info.GetOrigin(), file.harvesterImc_info.GetAngles(), GetCurrentPlaylistVarInt( "fd_harvester_health", FW_DEFAULT_HARVESTER_HEALTH ), GetCurrentPlaylistVarInt( "fd_harvester_shield", FW_DEFAULT_HARVESTER_SHIELD ), TEAM_IMC )
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

    file.harvesters.append(fw_harvesterMlt)
    file.harvesters.append(fw_harvesterImc)

    entity trackerMlt = GetAvailableBaseLocationTracker()
    trackerMlt.SetOwner( fw_harvesterMlt.harvester )
    DispatchSpawn( trackerMlt )
    entity trackerImc = GetAvailableBaseLocationTracker()
    trackerImc.SetOwner( fw_harvesterImc.harvester )
    DispatchSpawn( trackerImc )
    SetLocationTrackerRadius( trackerMlt , 65535 ) // whole map
    SetLocationTrackerRadius( trackerImc , 65535 ) // whole map

    // scores starts from 100, TeamScore means harvester health; TeamScore2 means shield bar
    GameRules_SetTeamScore( TEAM_MILITIA , 100 )
    GameRules_SetTeamScore( TEAM_IMC , 100 )
    GameRules_SetTeamScore2( TEAM_MILITIA , 100 )
    GameRules_SetTeamScore2( TEAM_IMC , 100 )
}

void function OnHarvesterDamaged( entity harvester, var damageInfo )
{
	if ( !IsValid( harvester ) )
		return

    GameRules_SetTeamScore( harvester.GetTeam() , 1.0 * GetHealthFrac( harvester ) * 100 )

    int damageSourceID = DamageInfo_GetDamageSourceIdentifier( damageInfo )
    entity attacker = DamageInfo_GetAttacker( damageInfo )
    float damageAmount = DamageInfo_GetDamage( damageInfo )

    if ( !damageSourceID && !damageAmount && !attacker ) // actually not dealing any damage?
        return

    // done damage adjustments here, since harvester prop's health is setting manually through damageAmount
    if ( damageSourceID == eDamageSourceId.mp_titancore_laser_cannon )
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/100 ) // laser core shreds super well for some reason

    if ( damageSourceID == eDamageSourceId.mp_titanweapon_flightcore_rockets )
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/4 ) // flight core shreds super well for some reason

    if ( damageSourceID == eDamageSourceId.mp_titanweapon_meteor_thermite || 
        damageSourceID == eDamageSourceId.mp_titanweapon_flame_wall ||
        damageSourceID == eDamageSourceId.mp_titanability_slow_trap ||
        damageSourceID == eDamageSourceId.mp_titancore_flame_wave_secondary
    ) // scorch's thermite damages
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/4 ) // nerf scorch

    HarvesterStruct harvesterstruct // current harveter's struct
    if( harvester.GetTeam() == TEAM_MILITIA )
        harvesterstruct = fw_harvesterMlt
    if( harvester.GetTeam() == TEAM_IMC )
        harvesterstruct = fw_harvesterImc

    if ( harvester.GetShieldHealth() - damageAmount <= 0 ) // this shot breaks shield
    {
        damageAmount = DamageInfo_GetDamage( damageInfo ) // get damageAmount again after all damage adjustments

        if ( !attacker.IsTitan() )
        {
            if( attacker.IsPlayer() )
                Remote_CallFunction_NonReplay( attacker , "ServerCallback_FW_NotifyTitanRequired" )
            DamageInfo_SetDamage( damageInfo, harvester.GetShieldHealth() )
            damageAmount = 0 // never damage haveter's prop
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

    if ( attacker.IsPlayer() )
    {
        attacker.NotifyDidDamage( harvester, DamageInfo_GetHitBox( damageInfo ), DamageInfo_GetDamagePosition( damageInfo ), DamageInfo_GetCustomDamageType( damageInfo ), DamageInfo_GetDamage( damageInfo ), DamageInfo_GetDamageFlags( damageInfo ), DamageInfo_GetHitGroup( damageInfo ), DamageInfo_GetWeapon( damageInfo ), DamageInfo_GetDistFromAttackOrigin( damageInfo ) )
        //attacker.AddToPlayerGameStat( PGS_PILOT_KILLS, DamageInfo_GetDamage( damageInfo ) * 0.01 )
    }

    harvesterstruct.lastDamage = Time()
    if ( harvester.GetHealth() == 0 )
    {
        int winnerTeam = GetOtherTeam( harvester.GetTeam() )
        SetWinner( winnerTeam )
        GameRules_SetTeamScore( winnerTeam, 0 ) // force set score to 0( health 0% )
    }
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
            GameRules_SetTeamScore2( team, 1.0 * harvester.GetShieldHealth() / harvester.GetShieldHealthMax() * 100 )
            WaitFrame()
        }
        else
        {
            int winnerTeam = GetOtherTeam(team)
            SetWinner( winnerTeam )
            GameRules_SetTeamScore2( team, 0 ) // force set score2 to 0( shield bar will empty )
            break
        }
    }
}

///////////////////////////////////
///// HARVESTER FUNCTIONS END /////
///////////////////////////////////
