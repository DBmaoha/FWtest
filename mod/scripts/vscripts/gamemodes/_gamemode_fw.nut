untyped
global function GamemodeFW_Init
global function RateSpawnpoints_FW
global function SetupFWTerritoryTrigger

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

global struct CampSiteStruct
{
    entity camp
    entity info
    string campId // "A", "B", "C"
}

struct
{
    array<HarvesterStruct> harvesters
    array<entity> camps
    array<entity> fwTerritories
    array<TurretSite> turretsites
    array<CampSiteStruct> campsites
    array<entity> etitaninmlt
    array<entity> etitaninimc
    entity harvesterMlt_info
    entity harvesterImc_info
    bool havesterWasDamaged
	bool harvesterShieldDown
	float harvesterDamageTaken
}file

void function GamemodeFW_Init()
{
    file.harvesters.append(fw_harvesterMlt)
    file.harvesters.append(fw_harvesterImc)
    if ( GameRules_GetGameMode() == "fw" )
    {
       AddCallback_EntitiesDidLoad( LoadEntities )
       AddCallback_GameStateEnter( eGameState.Prematch, FW_createHarvester )
       AddCallback_GameStateEnter( eGameState.Playing, OnFwGamePlaying )
       AddDamageCallback( "npc_turret_mega" , TurretFlagDamageCallback )

       // need to be in LoadEntities(), before harvester creation
       //AddSpawnCallbackEditorClass( "trigger_multiple", "trigger_fw_territory", SetupFWTerritoryTrigger )
       // noneed to use it rn
       //AddSpawnCallbackEditorClass( "info_target", "info_fw_camp", InitCampTracker )
    }
}














void function TurretFlagDamageCallback( entity turret , var damageinfo )
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
    string flag = expect string( turret.s.turretflagid )
    if ( turret.GetTeam() == TEAM_IMC && GetGlobalNetInt( "turretStateFlags" + flag ) != 26 )
    {
        SetGlobalNetInt( "turretStateFlags" + flag, 26 )
        wait 2
        SetGlobalNetInt( "turretStateFlags" + flag, 10 )
        return
    }
    if( turret.GetTeam() == TEAM_MILITIA && GetGlobalNetInt( "turretStateFlags" + flag ) != 28 )
    {
        SetGlobalNetInt( "turretStateFlags" + flag, 28 )
        wait 2
        SetGlobalNetInt( "turretStateFlags" + flag, 13 )
        return
    }
}
void function NeturalTurretFlagOnDamage_threaded( entity turret )
{
    string flag = expect string( turret.s.turretflagid )
    if ( turret.GetTeam() == TEAM_IMC && GetGlobalNetInt( "turretStateFlags" + flag ) != 18 )
    {
        SetGlobalNetInt( "turretStateFlags" + flag, 18 )
        wait 2
        SetGlobalNetInt( "turretStateFlags" + flag, 2 )
        return
    }
    if( turret.GetTeam() == TEAM_MILITIA && GetGlobalNetInt( "turretStateFlags" + flag ) != 21 )
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

void function OnFwGamePlaying()
{
    startFWHarvester()
    FWAreaThreatLevelThink()
}

void function InitCampTracker( entity camp )
{
    print("InitCampTracker")
    CampSiteStruct campsite
    file.campsites.append( campsite )
    entity prop = CreateEntity( "prop_script" )
    prop.SetOrigin( camp.GetOrigin() )
    prop.SetModel( $"models/dev/empty_model.mdl" )
    campsite.camp = prop
    DispatchSpawn( prop )
    entity tracker = GetAvailableCampLocationTracker()
    tracker.SetOwner( prop )
    campsite.info = tracker
    SetLocationTrackerRadius( tracker, float( camp.kv.radius ) )
    thread FWAiCampThink( camp )
    DispatchSpawn( tracker )

}

void function FWAiCampThink( entity camp )
{

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

void function EntityEnterFWTrig( entity trigger, entity ent, entity caller, var value )
{
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
            if( !imcEntArray.contains( titan ) && titan.GetTeam() != TEAM_IMC )
                warnImcTitanApproach = true // this titan must be in neatural space
            if( !mltEntArray.contains( titan ) && titan.GetTeam() != TEAM_MILITIA )
                warnMltTitanApproach = true // this titan must be in neatural space
        }

        WaitFrame()
    }
}

void function startFWHarvester()
{
    /*foreach ( HarvesterStruct fd_harvester in harvesters )
    {
	    thread HarvesterThink(fd_harvester)
	    thread HarvesterAlarm(fd_harvester)
    }*/
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
                        entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
					    file.harvesterMlt_info = info_target
                        print("fw_tower tracker spawned")
                    }
                    if ( info_target.GetTeam() == TEAM_IMC )
                    {
                        entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
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
                    TurretSite turretsite
                    file.turretsites.append( turretsite )
                    entity turret = CreateNPC( "npc_turret_mega", info_target.GetTeam(), info_target.GetOrigin(), info_target.GetAngles() )
                    SetSpawnOption_AISettings( turret, "npc_turret_mega_fortwar" )
                    SetDefaultMPEnemyHighlight( turret ) // for sonar highlights to work
                    AddEntityCallback_OnDamaged( turret, OnMegaTurretDamaged )
                    DispatchSpawn( turret )
                    turretsite.turret = turret
                    entity site = CreateEntity( "prop_script" )
                    site.SetValueForModelKey( info_target.GetModelName() )
                    site.SetOrigin( info_target.GetOrigin() )
                    site.SetAngles( info_target.GetAngles() )
                    SetTeam( site, info_target.GetTeam() )
                    site.kv.solid = SOLID_VPHYSICS
                    DispatchSpawn( site )
                    turret.s.minimapstate <- site
                    turretsite.site = info_target
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
                    prop.SetUsable()
                    prop.SetUsePrompts( "#FW_USE_TURRET_GENERATOR", "#FW_USE_TURRET_GENERATOR_PC" )
                    AddCallback_OnUseEntity( prop, FW_OnUseBatteryPort )
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

function FW_OnUseBatteryPort( entBeingUse, user )
{
    expect entity( entBeingUse )
    expect entity( user )

    //print( "try to use batteryPort" )
    thread TryUseBatteryPort( user, entBeingUse )
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
    fw_harvesterMlt.harvester.SetScriptName("fw_team_tower")

    fw_harvesterImc = SpawnHarvester( file.harvesterImc_info.GetOrigin(), file.harvesterImc_info.GetAngles(), GetCurrentPlaylistVarInt( "fd_harvester_health", 25000 ), GetCurrentPlaylistVarInt( "fd_harvester_shield", 6000 ), TEAM_IMC )
	fw_harvesterImc.harvester.Minimap_SetAlignUpright( true )
	fw_harvesterImc.harvester.Minimap_AlwaysShow( TEAM_IMC, null )
	fw_harvesterImc.harvester.Minimap_AlwaysShow( TEAM_MILITIA, null )
	fw_harvesterImc.harvester.Minimap_SetHeightTracking( true )
	fw_harvesterImc.harvester.Minimap_SetZOrder( MINIMAP_Z_OBJECT )
	fw_harvesterImc.harvester.Minimap_SetCustomState( eMinimapObject_prop_script.FD_HARVESTER )
    AddEntityCallback_OnDamaged( fw_harvesterImc.harvester, OnHarvesterDamaged )
    fw_harvesterImc.harvester.SetScriptName("fw_team_tower")

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

    if ( harvester.GetShieldHealth() == 0 )
    {
        if ( !attacker.IsTitan() && attacker.IsPlayer() )
        {
            Remote_CallFunction_NonReplay( attacker , "ServerCallback_FW_NotifyTitanRequired" )
            DamageInfo_SetDamage( damageInfo , 0 )
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

    if ( DamageInfo_GetDamageSourceIdentifier( damageInfo ) == eDamageSourceId.mp_titancore_laser_cannon )
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/100 ) // laser core shreds super well for some reason

    if ( DamageInfo_GetDamageSourceIdentifier( damageInfo ) == eDamageSourceId.mp_titanweapon_meteor ||
            DamageInfo_GetDamageSourceIdentifier( damageInfo ) == eDamageSourceId.mp_titanweapon_flame_wall ||
            DamageInfo_GetDamageSourceIdentifier( damageInfo ) == eDamageSourceId.mp_titanability_slow_trap
    )
        DamageInfo_SetDamage( damageInfo, DamageInfo_GetDamage( damageInfo )/2 )

    if ( attacker.IsPlayer() )
    {
        attacker.NotifyDidDamage( harvester, DamageInfo_GetHitBox( damageInfo ), DamageInfo_GetDamagePosition( damageInfo ), DamageInfo_GetCustomDamageType( damageInfo ), DamageInfo_GetDamage( damageInfo ), DamageInfo_GetDamageFlags( damageInfo ), DamageInfo_GetHitGroup( damageInfo ), DamageInfo_GetWeapon( damageInfo ), DamageInfo_GetDistFromAttackOrigin( damageInfo ) )
        //attacker.AddToPlayerGameStat( PGS_PILOT_KILLS, DamageInfo_GetDamage( damageInfo ) * 0.01 )
    }

    harvesterstruct.lastDamage = Time()
    if ( harvester.GetHealth() == 0 )
        SetWinner(TEAM_IMC)
}

void function OnMegaTurretDamaged( entity turret, var damageInfo )
{
    entity attacker = DamageInfo_GetAttacker( damageInfo )

    if( turret.GetShieldHealth() == 0 ) // shield down
    {
        if ( !attacker.IsTitan() && attacker.IsPlayer() )
        {
            if( attacker.GetTeam() != turret.GetTeam() ) // good to have
                MessageToPlayer( attacker, eEventNotifications.TurretTitanDamageOnly )
            DamageInfo_SetDamage( damageInfo , 0 )
            return
        }
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
    foreach( int index, CampSiteStruct camp in file.campsites )
    {
        if ( index == 0 )
        {
            camp.campId = "A"
            SetGlobalNetInt( "fwCampAlertA", 0 )
            SetGlobalNetInt( "fwCampStressA", 0 )
        }
        if ( index == 1 )
        {
            camp.campId = "B"
            SetGlobalNetInt( "fwCampAlertB", 0 )
            SetGlobalNetInt( "fwCampStressB", 0 )
        }
        if ( index == 1 )
        {
            camp.campId = "C"
            SetGlobalNetInt( "fwCampAlertC", 0 )
            SetGlobalNetInt( "fwCampStressC", 0 )
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
				file.harvesterShieldDown = false
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
			EmitSoundOnEntity( harvester, "coop_generator_shielddown" )

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










