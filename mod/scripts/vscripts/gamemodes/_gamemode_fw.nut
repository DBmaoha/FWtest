untyped
global function GamemodeFW_Init
global function SetupFWTerritoryTrigger

global HarvesterStruct& fw_harvester1
global HarvesterStruct& fw_harvester2


//array< HarvesterStruct& > harvesters = [ fw_harvester1 , fw_harvester2 ]
struct {
    array<HarvesterStruct> harvesters
    array<entity> turretsites
    array<entity> megaturrets
    entity harvester1_info
    entity harvester2_info
    bool havesterWasDamaged
	bool harvesterShieldDown
	float harvesterDamageTaken
    array<entity> powerupSpawns
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
       ////battery spawn
       SH_PowerUp_Init()
       AddCallback_OnTouchHealthKit( "item_powerup", OnPowerupCollected )
	   AddCallback_GameStateEnter( eGameState.Prematch, RespawnPowerups )
       ////
       AddSpawnCallbackEditorClass( "trigger_multiple", "trigger_fw_territory", SetupFWTerritoryTrigger )
    }
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
                        entity prop = CreateEntity("script_ref")
                        prop.SetModel(info_target.GetModelName())
                        prop.SetOrigin(info_target.GetOrigin())
                        prop.SetAngles(info_target.GetAngles())
                        DispatchSpawn(prop)
					    file.harvester1_info = info_target
                        print( "harvester1 : " + info_target.kv.editorclass )
                    }
                    if ( info_target.GetTeam() == 2 )
                    {
                        entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
					    file.harvester2_info = info_target
                        print( "harvester2 : " + info_target.kv.editorclass )
                    }
                    break
                case "info_fw_camp":
                    break
                case "info_fw_turret_site":
                    print("info_fw_turret_siteID : " + expect string(info_target.kv.turretId) )
                    entity turret = CreateNPC( "npc_turret_mega", info_target.GetTeam(), info_target.GetOrigin(), info_target.GetAngles() )
                    SetSpawnOption_AISettings( turret, "npc_turret_mega_fortwar" )
                    DispatchSpawn( turret )
                    file.megaturrets.append(turret)
                    entity site = CreateEntity( "prop_script" )
                    site.SetValueForModelKey( info_target.GetModelName() )
                    site.SetOrigin( info_target.GetOrigin() )
                    site.SetAngles( info_target.GetAngles() )
                    site.kv.solid = SOLID_VPHYSICS
                    DispatchSpawn( site )
                    file.turretsites.append(info_target)
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
                    AddPowerupSpawn( info_target )
                    entity prop = CreatePropDynamic( info_target.GetModelName(), info_target.GetOrigin(), info_target.GetAngles(), 6 )
                    prop.SetUsable()
                    prop.SetUsePrompts( "", "#FW_USE_BATTERY" )
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
    thread ApplyBatteryToBatteryPort( user, entBeingUse )
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
    else
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
                Remote_CallFunction_NonReplay( attacker , "ServerCallback_FW_NotifyTitanRequired" )
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
    foreach( turret in file.megaturrets )
    {
        turret.Minimap_SetAlignUpright( true )
	    turret.Minimap_AlwaysShow( TEAM_IMC, null )
	    turret.Minimap_AlwaysShow( TEAM_MILITIA, null )
	    turret.Minimap_SetHeightTracking( true )
	    turret.Minimap_SetZOrder( MINIMAP_Z_OBJECT )
	    turret.Minimap_SetCustomState( eMinimapObject_prop_script.FW_BUILDSITE_TURRET )
    }
    foreach( turret in file.turretsites )
    {
        if ( turret.kv.turretId == "0" )
        {
            SetGlobalNetEnt( "turretSite1" , turret )
            SetGlobalNetInt("turretStateFlags1" , turret.GetTeam()  )
        }
        if ( turret.kv.turretId == "1" )
        {
            SetGlobalNetEnt( "turretSite2" , turret )
            SetGlobalNetInt("turretStateFlags2" , turret.GetTeam()  )
        }
        if ( turret.kv.turretId == "2" )
        {
            SetGlobalNetEnt( "turretSite3" , turret )
            SetGlobalNetInt("turretStateFlags3" , turret.GetTeam()  )
        }
        if ( turret.kv.turretId == "3" )
        {
            SetGlobalNetEnt( "turretSite4" , turret )
            SetGlobalNetInt("turretStateFlags4" , turret.GetTeam()  )
        }
        if ( turret.kv.turretId == "4" )
        {
            SetGlobalNetEnt( "turretSite5" , turret )
            SetGlobalNetInt("turretStateFlags5" , turret.GetTeam()  )
        }
        if ( turret.kv.turretId == "5" )
        {
            SetGlobalNetEnt( "turretSite6" , turret )
            SetGlobalNetInt("turretStateFlags6" , turret.GetTeam()  )
        }
        if ( turret.kv.turretId == "6" )
        {
            SetGlobalNetEnt( "turretSite7" , turret )
            SetGlobalNetInt("turretStateFlags7" , turret.GetTeam()  )
        }
        if ( turret.kv.turretId == "7" )
        {
            SetGlobalNetEnt( "turretSite8" , turret )
            SetGlobalNetInt("turretStateFlags8" , turret.GetTeam()  )
        }
        if ( turret.kv.turretId == "8" )
        {
            SetGlobalNetEnt( "turretSite9" , turret )
            SetGlobalNetInt("turretStateFlags9" , turret.GetTeam()  )
        }
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













void function AddPowerupSpawn( entity spawnpoint )
{
	file.powerupSpawns.append( spawnpoint )
}

void function RespawnPowerups()
{
	foreach ( entity spawnpoint in file.powerupSpawns )
	{
		PowerUp powerupDef = GetPowerUpFromItemRef( "mp_loot_titan_build_credit_lts" )
		thread PowerupSpawnerThink( spawnpoint, powerupDef )
	}
}

void function PowerupSpawnerThink( entity spawnpoint, PowerUp powerupDef )
{
	svGlobal.levelEnt.EndSignal( "CleanUpEntitiesForRoundEnd" )

	entity base = CreatePropDynamic( powerupDef.baseModel, spawnpoint.GetOrigin(), spawnpoint.GetAngles(), 2 )
	OnThreadEnd( function() : ( base )
	{
		base.Destroy()
	})

	while ( true )
	{
		if ( !powerupDef.spawnFunc() )
			return

		entity powerup = CreateEntity( "item_powerup" )

		powerup.SetOrigin( base.GetOrigin() + powerupDef.modelOffset )
		powerup.SetAngles( base.GetAngles() + powerupDef.modelAngles )
		powerup.SetValueForModelKey( powerupDef.model )
		powerup.s.powerupRef <- powerupDef.itemRef // this needs to be done before dispatchspawn since OnPowerupCollected will run as soon as we call dispatchspawn if there's a player on battery as it spawns

		DispatchSpawn( powerup )

		// unless i'm doing something really dumb, this all has to be done after dispatchspawn to get the powerup to not have gravity
		powerup.StopPhysics()
		powerup.SetOrigin( base.GetOrigin() + powerupDef.modelOffset )
		powerup.SetAngles( base.GetAngles() + powerupDef.modelAngles )

		powerup.SetModel( powerupDef.model )

		PickupGlow glow = CreatePickupGlow( powerup, powerupDef.glowColor.x.tointeger(), powerupDef.glowColor.y.tointeger(), powerupDef.glowColor.z.tointeger() )
		glow.glowFX.SetOrigin( spawnpoint.GetOrigin() ) // want the glow to be parented to the powerup, but have the position of the spawnpoint

		OnThreadEnd( function() : ( powerup )
		{
			if ( IsValid( powerup ) )
				powerup.Destroy()
		})

		powerup.WaitSignal( "OnDestroy" )
		wait powerupDef.respawnDelay
	}
}

bool function OnPowerupCollected( entity player, entity healthpack )
{
	PowerUp powerup = GetPowerUpFromItemRef( "mp_loot_titan_build_credit_lts" )

	if ( powerup.titanPickup == player.IsTitan() )
	{
		// hack because i couldn't figure out any other way to do this without modifying sh_powerup
		// ensure we don't kill the powerup if it's a battery the player can't pickup
		if ( powerup.index == ePowerUps.titanTimeReduction || powerup.index == ePowerUps.LTS_TitanTimeReduction )
		{
			if ( player.IsTitan() )
				return false

			if ( PlayerHasMaxBatteryCount( player ) )
				return false

			// this is seemingly innacurate to what fra actually did, but for whatever reason embarking with >1 bat crashes in vanilla code
			// so idk this is easier
			if ( GAMETYPE == FREE_AGENCY && ( IsValid( player.GetPetTitan() ) || IsTitanAvailable( player ) ) && GetPlayerBatteryCount( player ) > 0 )
				return false
		}

		// idk why the powerup.destroyFunc doesn't just return a bool? would mean they could just handle stuff like this in powerup code
		powerup.destroyFunc( player )
		return true // destroys the powerup
	}

	return false // keeps powerup alive
}