untyped
global function GamemodeFW_Init
global function SetupFWTerritoryTrigger

global HarvesterStruct& fw_harvester1
global HarvesterStruct& fw_harvester2


//array< HarvesterStruct& > harvesters = [ fw_harvester1 , fw_harvester2 ]
global struct TurretSite
{
    entity site
    entity turret
    entity minimapstate
}
struct {
    array<HarvesterStruct> harvesters
    array<entity> camps
    array<TurretSite> turretsites
    array<entity> etitaninmlt
    array<entity> etitaninimc
    entity harvester1_info
    entity harvester2_info
    bool havesterWasDamaged
	bool harvesterShieldDown
	float harvesterDamageTaken
}file



void function GamemodeFW_Init()
{
    file.harvesters.append(fw_harvester1)
    file.harvesters.append(fw_harvester2)
    if ( GameRules_GetGameMode() == "fw" )
    {
       AddCallback_EntitiesDidLoad( LoadEntities )
       AddCallback_GameStateEnter( eGameState.Prematch,FW_createHarvester )
       AddCallback_GameStateEnter( eGameState.Playing,startFWHarvester )
       AddSpawnCallbackEditorClass( "trigger_multiple", "trigger_fw_territory", SetupFWTerritoryTrigger )

       //noneed to use it rn
       //AddSpawnCallbackEditorClass( "info_target", "info_fw_camp", InitCampTracker )
    }
}



void function InitCampTracker( entity camp )
{
    print("InitCampTracker InitCampTracker InitCampTracker")
    entity prop = CreateEntity("prop_script")
    prop.SetOrigin( camp.GetOrigin() )
    prop.SetModel($"models/dev/empty_model.mdl")
    DispatchSpawn( prop )
    entity tracker = GetAvailableCampLocationTracker()
    tracker.SetOwner( prop )
    SetLocationTrackerRadius( tracker , 1200 )
    DispatchSpawn( tracker )
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
    trigger.ConnectOutput( "OnStartTouch", EntityEnterFWTrig )
	trigger.ConnectOutput( "OnEndTouch", EntityLeaveFWTrig )
}
void function EntityEnterFWTrig( entity trigger, entity ent, entity caller, var value )
{
    if( !IsValid(ent) )
        return
    if ( !ent.IsPlayer() )
        return
    if ( ent.GetTeam() == TEAM_MILITIA )
    {
        if ( Distance( ent.GetOrigin() , fw_harvester1.harvester.GetOrigin() ) > Distance( ent.GetOrigin() , fw_harvester2.harvester.GetOrigin() ) )
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyEnterEnemyArea" )
        else
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyEnterFriendlyArea" )
    }
    if ( ent.GetTeam() == TEAM_IMC )
    {
        if ( Distance( ent.GetOrigin() , fw_harvester1.harvester.GetOrigin() ) > Distance( ent.GetOrigin() , fw_harvester2.harvester.GetOrigin() ) )
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyEnterFriendlyArea" )
        else
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyEnterEnemyArea" )
    }
}
void function EntityLeaveFWTrig( entity trigger, entity ent, entity caller, var value )
{
    if( !IsValid(ent) )
        return
    if ( !ent.IsPlayer() )
        return
    if ( ent.GetTeam() == TEAM_MILITIA )
    {
        if ( Distance( ent.GetOrigin() , fw_harvester1.harvester.GetOrigin() ) > Distance( ent.GetOrigin() , fw_harvester2.harvester.GetOrigin() ) )
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyExitEnemyArea" )
        else
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyExitFriendlyArea" )
    }
    if ( ent.GetTeam() == TEAM_IMC )
    {
        if ( Distance( ent.GetOrigin() , fw_harvester1.harvester.GetOrigin() ) > Distance( ent.GetOrigin() , fw_harvester2.harvester.GetOrigin() ) )
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyExitFriendlyArea" )
        else
            Remote_CallFunction_NonReplay( ent , "ServerCallback_FW_NotifyExitEnemyArea" )
    }
}

void function startFWHarvester()
{
    /*foreach ( HarvesterStruct fd_harvester in harvesters )
    {
	    thread HarvesterThink(fd_harvester)
	    thread HarvesterAlarm(fd_harvester)
    }*/
    thread HarvesterThink(fw_harvester1)
	thread HarvesterAlarm(fw_harvester1)
    thread HarvesterThink(fw_harvester2)
	thread HarvesterAlarm(fw_harvester2)
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
                    if ( info_target.GetTeam() == 3 )
                    {
                        entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
					    file.harvester1_info = info_target
                        print("fw_tower tracker spawned")
                    }
                    if ( info_target.GetTeam() == 2 )
                    {
                        entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
					    file.harvester2_info = info_target
                        print("fw_tower tracker spawned")
                    }
                    break
                case "info_fw_camp":
                    print("fw_camp spawned")
                    break
                case "info_fw_turret_site":
                    print("info_fw_turret_siteID : " + expect string(info_target.kv.turretId) )
                    TurretSite turretsite
                    file.turretsites.append( turretsite )
                    entity turret = CreateNPC( "npc_turret_mega", info_target.GetTeam(), info_target.GetOrigin(), info_target.GetAngles() )
                    SetSpawnOption_AISettings( turret, "npc_turret_mega_fortwar" )
                    DispatchSpawn( turret )
                    turretsite.turret = turret
                    entity site = CreateEntity( "prop_script" )
                    site.SetValueForModelKey( info_target.GetModelName() )
                    site.SetOrigin( info_target.GetOrigin() )
                    site.SetAngles( info_target.GetAngles() )
                    SetTeam( site , info_target.GetTeam() )
                    site.kv.solid = SOLID_VPHYSICS
                    DispatchSpawn( site )
                    turretsite.minimapstate = site
                    turretsite.site = info_target
                    break
			}
		}
	}
    foreach ( entity info_target in GetEntArrayByClass_Expensive( "script_ref" ) )
	{
		if( info_target.HasKey( "editorclass" ) )
		{
			switch( info_target.kv.editorclass )
			{
                case "info_fw_foundation_plate":
                    entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
                    break
                case "info_fw_battery_port":
                    entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
                    prop.kv.fadedist = 10000 // try not to fade
                    InitTurretBatteryPort( prop )
                    prop.SetUsable()
                    prop.SetUsePrompts( "#FW_USE_TURRET_GENERATOR", "#FW_USE_TURRET_GENERATOR_PC" )
                    AddCallback_OnUseEntity( prop, FW_OnUseBatteryPort )
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

    print( "try to use batteryPort" )
    thread TryUseBatteryPort( user, entBeingUse )
}

void function FW_createHarvester()
{

	fw_harvester1 = SpawnHarvester( file.harvester1_info.GetOrigin(), file.harvester1_info.GetAngles(), GetCurrentPlaylistVarInt( "fd_harvester_health", 25000 ), GetCurrentPlaylistVarInt( "fd_harvester_shield", 6000 ), TEAM_MILITIA )
	fw_harvester1.harvester.Minimap_SetAlignUpright( true )
	fw_harvester1.harvester.Minimap_AlwaysShow( TEAM_IMC, null )
	fw_harvester1.harvester.Minimap_AlwaysShow( TEAM_MILITIA, null )
	fw_harvester1.harvester.Minimap_SetHeightTracking( true )
	fw_harvester1.harvester.Minimap_SetZOrder( MINIMAP_Z_OBJECT )
	fw_harvester1.harvester.Minimap_SetCustomState( eMinimapObject_prop_script.FD_HARVESTER )
	AddEntityCallback_OnDamaged( fw_harvester1.harvester, OnHarvesterDamaged )
    fw_harvester1.harvester.SetScriptName("fw_team_tower")



    fw_harvester2 = SpawnHarvester( file.harvester2_info.GetOrigin(), file.harvester2_info.GetAngles(), GetCurrentPlaylistVarInt( "fd_harvester_health", 25000 ), GetCurrentPlaylistVarInt( "fd_harvester_shield", 6000 ), TEAM_IMC )
	fw_harvester2.harvester.Minimap_SetAlignUpright( true )
	fw_harvester2.harvester.Minimap_AlwaysShow( TEAM_IMC, null )
	fw_harvester2.harvester.Minimap_AlwaysShow( TEAM_MILITIA, null )
	fw_harvester2.harvester.Minimap_SetHeightTracking( true )
	fw_harvester2.harvester.Minimap_SetZOrder( MINIMAP_Z_OBJECT )
	fw_harvester2.harvester.Minimap_SetCustomState( eMinimapObject_prop_script.FD_HARVESTER )
    AddEntityCallback_OnDamaged( fw_harvester2.harvester, OnHarvesterDamaged )
    fw_harvester2.harvester.SetScriptName("fw_team_tower")





    entity tracker1 = GetAvailableBaseLocationTracker( )
    tracker1.SetOwner(fw_harvester1.harvester)
    DispatchSpawn( tracker1 )
    entity tracker2 = GetAvailableBaseLocationTracker( )
    tracker2.SetOwner(fw_harvester2.harvester)
    DispatchSpawn( tracker2 )
    SetLocationTrackerRadius( tracker1 , 3000 )
    SetLocationTrackerRadius( tracker2 , 3000 )








    GameRules_SetTeamScore( TEAM_MILITIA , 100)
    GameRules_SetTeamScore( TEAM_IMC , 100)
    GameRules_SetTeamScore2( TEAM_MILITIA , 100)
    GameRules_SetTeamScore2( TEAM_IMC , 100)
}

void function OnHarvesterDamaged( entity harvester, var damageInfo )
{
	if ( !IsValid( harvester ) )
		return
    if ( harvester.GetTeam() == 3 )
    {
        fw_harvester1.lastDamage = Time()
        if ( harvester.GetHealth() == 0 )
            SetWinner(TEAM_IMC)
    }
    if ( harvester.GetTeam() == 2 )
    {
        fw_harvester2.lastDamage = Time()
        if ( harvester.GetHealth() == 0 )
            SetWinner(TEAM_MILITIA)
    }
    /*if ( harvester.GetShieldHealth() > 0 )
        GameRules_SetTeamScore2( harvester.GetTeam() , 1.0 * harvester.GetShieldHealth()/harvester.GetShieldHealthMax() * 100 )*/
    //else
        GameRules_SetTeamScore( harvester.GetTeam() , 1.0 * harvester.GetHealth()/harvester.GetMaxHealth() * 100 )




    int damageSourceID = DamageInfo_GetDamageSourceIdentifier( damageInfo )
    entity attacker = DamageInfo_GetAttacker( damageInfo )
    float damageAmount = DamageInfo_GetDamage( damageInfo )

    if ( !damageSourceID && !damageAmount && !attacker )
        return
    HarvesterStruct harvesterstruct
    if( harvester.GetTeam() == TEAM_MILITIA )
        harvesterstruct = fw_harvester1
    if( harvester.GetTeam() == TEAM_IMC )
        harvesterstruct = fw_harvester2



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

}


void function initNetVars()
{
    foreach( turret in file.turretsites )
    {
        if ( turret.site.kv.turretId == "0" )
        {
            SetGlobalNetEnt( "turretSite1" , turret.turret )
            SetGlobalNetInt("turretStateFlags1" , 1  )
            thread TurretSiteWatcher(turret)
        }
        if ( turret.site.kv.turretId == "1" )
        {
            SetGlobalNetEnt( "turretSite2" , turret.turret )
            SetGlobalNetInt("turretStateFlags2" , 1 )
            thread TurretSiteWatcher(turret)
        }
        if ( turret.site.kv.turretId == "2" )
        {
            SetGlobalNetEnt( "turretSite3" , turret.turret )
            SetGlobalNetInt("turretStateFlags3" , 1)
            thread TurretSiteWatcher(turret)
        }
        if ( turret.site.kv.turretId == "3" )
        {
            SetGlobalNetEnt( "turretSite4" , turret.turret )
            SetGlobalNetInt("turretStateFlags4" , 2 )
            thread TurretSiteWatcher(turret)
        }
        if ( turret.site.kv.turretId == "4" )
        {
            SetGlobalNetEnt( "turretSite5" , turret.turret )
            SetGlobalNetInt("turretStateFlags5" , 2 )
            thread TurretSiteWatcher(turret)
        }
        if ( turret.site.kv.turretId == "5" )
        {
            SetGlobalNetEnt( "turretSite6" , turret.turret )
            SetGlobalNetInt("turretStateFlags6" , 2 )
            thread TurretSiteWatcher(turret)
        }
        if ( turret.site.kv.turretId == "6" )
        {
            SetGlobalNetEnt( "turretSite7" , turret.turret )
            SetGlobalNetInt("turretStateFlags7" , 4 )
            thread TurretSiteWatcher(turret)
        }
        if ( turret.site.kv.turretId == "7" )
        {
            SetGlobalNetEnt( "turretSite8" , turret.turret )
            SetGlobalNetInt("turretStateFlags8" , 4)
            thread TurretSiteWatcher(turret)
        }
        if ( turret.site.kv.turretId == "8" )
        {
            SetGlobalNetEnt( "turretSite9" , turret.turret )
            SetGlobalNetInt("turretStateFlags9" , 4 )
            thread TurretSiteWatcher(turret)
        }
    }

}

void function TurretSiteWatcher( TurretSite turret )
{
    if ( turret.turret.GetTeam() == 3 || turret.turret.GetTeam() == 2 )
    {
	    turret.minimapstate.Minimap_AlwaysShow( TEAM_IMC, null )
	    turret.minimapstate.Minimap_AlwaysShow( TEAM_MILITIA, null )
        turret.minimapstate.Minimap_SetCustomState( eMinimapObject_prop_script.FW_BUILDSITE_SHIELDED )
    }
    else
    {
        SetTeam( turret.minimapstate , 1 )
	    turret.minimapstate.Minimap_AlwaysShow( TEAM_IMC, null )
	    turret.minimapstate.Minimap_AlwaysShow( TEAM_MILITIA, null )
        turret.minimapstate.Minimap_SetCustomState( eMinimapObject_prop_script.FW_BUILDSITE_SHIELDED )
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
        harvester = fw_harvester1.harvester
    if( team == TEAM_IMC )
        harvester = fw_harvester2.harvester

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










