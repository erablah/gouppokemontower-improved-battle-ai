################################################################################
# 
# New ability handlers.
# 
################################################################################


#===============================================================================
# Armor Tail
#===============================================================================
Battle::AbilityEffects::MoveBlocking.copy(:DAZZLING, :QUEENLYMAJESTY, :ARMORTAIL)

#===============================================================================
# Rocky Payload
#===============================================================================
Battle::AbilityEffects::DamageCalcFromUser.add(:ROCKYPAYLOAD,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 1.5 if type == :ROCK
  }
)

#===============================================================================
# Sharpness
#===============================================================================
Battle::AbilityEffects::DamageCalcFromUser.add(:SHARPNESS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:power_multiplier] *= 1.5 if move.slicingMove?
  }
)

#===============================================================================
# Supreme Overlord
#===============================================================================
Battle::AbilityEffects::DamageCalcFromUser.add(:SUPREMEOVERLORD,
  proc { |ability, user, target, move, mults, baseDmg, type|
    bonus = user.effects[PBEffects::SupremeOverlord]
    next if bonus <= 0
    mults[:power_multiplier] *= (1 + (0.1 * bonus))
  }
)

Battle::AbilityEffects::OnSwitchIn.add(:SUPREMEOVERLORD,
  proc { |ability, battler, battle, switch_in|
    numFainted = [5, battler.num_fainted_allies].min
    next if numFainted <= 0
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("\\j[{1},은,는] 쓰러진 동료로부터 힘을 받았다!", battler.pbThis))
    battler.effects[PBEffects::SupremeOverlord] = numFainted
    battle.pbHideAbilitySplash(battler)
  }
)

#===============================================================================
# Mycelium Might
#===============================================================================
Battle::AbilityEffects::PriorityBracketChange.add(:MYCELIUMMIGHT,
  proc { |ability, battler, battle|
    choices = battle.choices[battler.index]
    if choices[0] == :UseMove
      next -1 if choices[2].statusMove?
    end
  }
)

#===============================================================================
# Purifying Salt
#===============================================================================
Battle::AbilityEffects::StatusImmunity.add(:PURIFYINGSALT,
  proc { |ability, battler, status|
    next true
  }
)

Battle::AbilityEffects::DamageCalcFromTarget.add(:PURIFYINGSALT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] /= 2 if type == :GHOST
  }
)

#===============================================================================
# Earth Eater
#===============================================================================
Battle::AbilityEffects::MoveImmunity.add(:EARTHEATER,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityHealingAbility(user, move, type, :GROUND, show_message)
  }
)

#===============================================================================
# Good As Gold
#===============================================================================
Battle::AbilityEffects::MoveImmunity.add(:GOODASGOLD,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if !move.statusMove?
    next false if user.index == target.index
    if show_message
      battle.pbShowAbilitySplash(target)
      if Battle::Scene::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} blocks {3}!",
           target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

#===============================================================================
# Well-Baked Body
#===============================================================================
Battle::AbilityEffects::MoveImmunity.add(:WELLBAKEDBODY,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityStatRaisingAbility(user, move, type, :FIRE, :DEFENSE, 2, show_message)
  }
)

#===============================================================================
# Wind Rider
#===============================================================================
Battle::AbilityEffects::MoveImmunity.add(:WINDRIDER,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if !move.windMove?
    next false if user.index == target.index
    if show_message
      battle.pbShowAbilitySplash(target)
      if target.pbCanRaiseStatStage?(:ATTACK, user, move)
        if Battle::Scene::USE_ABILITY_SPLASH
          target.pbRaiseStatStage(:ATTACK, 1, user)
        else
          target.pbRaiseStatStageByCause(:ATTACK, 1, user, target.abilityName)
        end
      elsif Battle::Scene::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made {3} ineffective!", target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

Battle::AbilityEffects::OnSwitchIn.add(:WINDRIDER,
  proc { |ability, battler, battle, switch_in|
    next if battler.pbOwnSide.effects[PBEffects::Tailwind] <= 0
    next if !battler.pbCanRaiseStatStage?(:ATTACK, battler)
    battler.pbRaiseStatStageByAbility(:ATTACK, 1, battler)
  }
)

#===============================================================================
# Anger Shell
#===============================================================================
Battle::AbilityEffects::AfterMoveUseFromTarget.add(:ANGERSHELL,
  proc { |ability, target, user, move, switched_battlers, battle|
    next if !move.damagingMove?
    next if !target.droppedBelowHalfHP
    showAnim = true
    battle.pbShowAbilitySplash(target)
    [:ATTACK, :SPECIAL_ATTACK, :SPEED].each do |stat|
      next if !target.pbCanRaiseStatStage?(stat, user, nil, true)
      if target.pbRaiseStatStage(stat, 1, user, showAnim)
        showAnim = false
      end
    end
    showAnim = true
    [:DEFENSE, :SPECIAL_DEFENSE].each do |stat|
      next if !target.pbCanLowerStatStage?(stat, user, nil, true)
      if target.pbLowerStatStage(stat, 1, user, showAnim)
        showAnim = false
      end
    end
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# Electromorphosis
#===============================================================================
Battle::AbilityEffects::OnBeingHit.add(:ELECTROMORPHOSIS,
  proc { |ability, user, target, move, battle|
    next if target.fainted?
    next if target.effects[PBEffects::Charge] > 0
    battle.pbShowAbilitySplash(target)
    target.effects[PBEffects::Charge] = 2
    battle.pbDisplay(_INTL("{1}에게 공격을 받아 {2}의 전기가 충전되었다!", move.name, target.pbThis(true)))
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# Lingering Aroma
#===============================================================================
Battle::AbilityEffects::OnBeingHit.copy(:MUMMY, :LINGERINGAROMA)

#===============================================================================
# Seed Sower
#===============================================================================
Battle::AbilityEffects::OnBeingHit.add(:SEEDSOWER,
  proc { |ability, user, target, move, battle|
    next if !move.damagingMove?
    next if battle.field.terrain == :Grassy
    battle.pbShowAbilitySplash(target)
    battle.pbStartTerrain(target, :Grassy)
  }
)

#===============================================================================
# Thermal Exchange
#===============================================================================
Battle::AbilityEffects::OnBeingHit.add(:THERMALEXCHANGE,
  proc { |ability, user, target, move, battle|
    next if move.calcType != :FIRE
    target.pbRaiseStatStageByAbility(:ATTACK, 1, target)
  }
)

Battle::AbilityEffects::StatusImmunity.add(:THERMALEXCHANGE,
  proc { |ability, battler, status|
    next true if status == :BURN
  }
)

Battle::AbilityEffects::StatusCure.copy(:WATERVEIL, :WATERBUBBLE, :THERMALEXCHANGE)

#===============================================================================
# Toxic Debris
#===============================================================================
Battle::AbilityEffects::OnBeingHit.add(:TOXICDEBRIS,
  proc { |ability, user, target, move, battle|
    next if !move.physicalMove?
    next if target.damageState.substitute
    next if target.pbOpposingSide.effects[PBEffects::ToxicSpikes] >= 2
    battle.pbShowAbilitySplash(target)
    target.pbOpposingSide.effects[PBEffects::ToxicSpikes] += 1
    battle.pbAnimation(:TOXICSPIKES, target, target.pbDirectOpposing)
    battle.pbDisplay(_INTL("{1} 주위에 독압적이 흩뿌려졌다!", target.pbOpposingTeam(true)))
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# Wind Power
#===============================================================================
Battle::AbilityEffects::OnBeingHit.add(:WINDPOWER,
  proc { |ability, user, target, move, battle|
    next if !move.windMove?
    next if target.effects[PBEffects::Charge] > 0
    battle.pbShowAbilitySplash(target)
    target.effects[PBEffects::Charge] = 2
    battle.pbDisplay(_INTL("{1}에게 공격을 받아 {2}의 전기가 충전되었다!", move.name, target.pbThis(true)))
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# Cud Chew
#===============================================================================
Battle::AbilityEffects::EndOfRoundEffect.add(:CUDCHEW,
  proc { |ability, battler, battle|
    echoln "Cud Chew Check"
    next if battler.item
    echoln "Cud Chew Not have item"
    next if !battler.recycleItem || !GameData::Item.get(battler.recycleItem).is_berry?
    echoln "Cud Chew recycle item"
    case battler.effects[PBEffects::CudChew]
    when 0 # End round after eat berry
      battler.effects[PBEffects::CudChew] += 1
    else # next turn after eat berry
      battler.effects[PBEffects::CudChew] = 0
      battle.pbShowAbilitySplash(battler, true)
      battle.pbHideAbilitySplash(battler)
      battler.pbHeldItemTriggerCheck(battler.recycleItem, true)
      battler.setRecycleItem(nil)
    end
  }
)

#===============================================================================
# Opportunist
#===============================================================================
Battle::AbilityEffects::OnOpposingStatGain.add(:OPPORTUNIST,
  proc { |ability, battler, battle, statUps|
    showAnim = true
    battle.pbShowAbilitySplash(battler)
    statUps.each do |stat, increment|
	    next if !battler.pbCanRaiseStatStage?(stat, battler)
      if battler.pbRaiseStatStage(stat, increment, battler, showAnim)
        showAnim = false
      end
    end
    battle.pbDisplay(_INTL("{1}'s stats won't go any higher!", battler.pbThis)) if showAnim
    battle.pbHideAbilitySplash(battler)
    battler.pbItemOpposingStatGainCheck(statUps)
    # Mirror Herb can trigger off this ability.
    if !showAnim 
      opposingStatUps = battle.sideStatUps[battler.idxOwnSide]
      battle.allOtherSideBattlers(battler.index).each do |b|
        next if !b || b.fainted?
        if b.itemActive?
          b.pbItemOpposingStatGainCheck(opposingStatUps)
        end
      end
      opposingStatUps.clear
    end
  }
)

#===============================================================================
# Costar
#===============================================================================
Battle::AbilityEffects::OnSwitchIn.add(:COSTAR,
  proc { |ability, battler, battle, switch_in|
    battler.allAllies.each do |b|
      next if b.index == battler.index
      next if !b.hasAlteredStatStages? && b.effects[PBEffects::FocusEnergy] == 0
      battle.pbShowAbilitySplash(battler)
      battler.effects[PBEffects::FocusEnergy] = b.effects[PBEffects::FocusEnergy]
      GameData::Stat.each_battle { |stat| battler.stages[stat.id] = b.stages[stat.id] }
      battle.pbDisplay(_INTL("{1} copied {2}'s stat changes!", battler.pbThis, b.pbThis(true)))
      battle.pbHideAbilitySplash(battler)
      break
    end
  }
)

#===============================================================================
# Zero To Hero
#===============================================================================
Battle::AbilityEffects::OnSwitchIn.add(:ZEROTOHERO,
  proc { |ability, battler, battle, switch_in|
    next if !battler.isSpecies?(:PALAFIN)
    next if battler.form == 0 || battler.ability_triggered?
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("\\j[{1},은,는] 변신하고 돌아왔다!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
    battle.pbSetAbilityTrigger(battler)
  }
)

Battle::AbilityEffects::OnSwitchOut.add(:ZEROTOHERO,
  proc { |ability, battler, endOfBattle|
    next if !battler.isSpecies?(:PALAFIN)
    next if battler.form == 1 || endOfBattle
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.pbChangeForm(1, "")
  }
)

#===============================================================================
# Commander
#===============================================================================
Battle::AbilityEffects::OnSwitchIn.add(:COMMANDER,
  proc { |ability, battler, battle, switch_in|
    next if battler.effects[PBEffects::Commander]
    next if defined?(battler.dynamax?) && battler.dynamax?
    showAnim = true
    battler.allAllies.each{|b|
      next if !b || !b.near?(battler) || b.fainted?
      next if battle.choices[b.index][0] == :SwitchOut
      next if !b.isSpecies?(:DONDOZO)
      next if b.effects[PBEffects::Commander]
      next if defined?(b.dynamax?) && b.dynamax?
      battle.pbShowAbilitySplash(battler)
      battle.pbClearChoice(battler.index)
      battle.pbDisplay(_INTL("\\j[{1},은,는] {2}의 입 속으로 들어갔다!", battler.pbThis, b.pbThis(true)))
      battle.scene.sprites["pokemon_#{battler.index}"].visible = false
      b.effects[PBEffects::Commander] = [battler.index, battler.form]
      battler.effects[PBEffects::Commander] = [b.index]
      [:ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED].each do |stat|
        next if !b.pbCanRaiseStatStage?(stat, b)
        if b.pbRaiseStatStage(stat, 2, b, showAnim)
          showAnim = false
        end
      end
      battle.pbHideAbilitySplash(battler)
      break
    }
  }
)

Battle::AbilityEffects::MoveImmunity.add(:COMMANDER,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if !target.isCommander?
    battle.pbDisplay(_INTL("{1} avoided the attack!", target.pbThis)) if show_message
    next true
  }
)

#===============================================================================
# Tablets of Ruin, Sword of Ruin, Vessel of Ruin, Beads of Ruin
#===============================================================================
Battle::AbilityEffects::OnSwitchIn.add(:TABLETSOFRUIN,
  proc { |ability, battler, battle, switch_in|
    case ability
    when :TABLETSOFRUIN then stat_name = GameData::Stat.get(:ATTACK).name
    when :SWORDOFRUIN   then stat_name = GameData::Stat.get(:DEFENSE).name
    when :VESSELOFRUIN  then stat_name = GameData::Stat.get(:SPECIAL_ATTACK).name
    when :BEADSOFRUIN   then stat_name = GameData::Stat.get(:SPECIAL_DEFENSE).name
    end
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1}의 \\j[{2},이,가] 주위의 모든 포켓몬의 \\j[{3},을,를] 약하게 했다!", battler.pbThis, battler.abilityName, stat_name))
    battle.pbHideAbilitySplash(battler)
  }
)

Battle::AbilityEffects::OnSwitchIn.copy(:TABLETSOFRUIN, :SWORDOFRUIN, :VESSELOFRUIN, :BEADSOFRUIN)

#===============================================================================
# Orichalcum Pulse
#===============================================================================
Battle::AbilityEffects::OnSwitchIn.add(:ORICHALCUMPULSE,
  proc { |ability, battler, battle, switch_in|
    if [:Sun, :HarshSun].include?(battler.effectiveWeather)
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("\\j[{1},은,는] 햇살을 받아 고대의 고동을 폭발시켰다!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    else
      battle.pbStartWeatherAbility(:Sun, battler)
      battle.pbDisplay(_INTL("\\j[{1},은,는] 햇살을 강하게 하여 고대의 고동을 폭발시켰다!", battler.pbThis))
    end
  }
)

Battle::AbilityEffects::DamageCalcFromUser.add(:ORICHALCUMPULSE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 4 / 3.0 if move.physicalMove? && [:Sun, :HarshSun].include?(user.effectiveWeather)
  }
)

#===============================================================================
# Hadron Engine
#===============================================================================
Battle::AbilityEffects::OnSwitchIn.add(:HADRONENGINE,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    if battle.field.terrain == :Electric
      battle.pbDisplay(_INTL("\\j[{1},은,는] 일렉트릭필드의 힘으로 미래 기관을 가동했다!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    else
      battle.pbStartTerrain(battler, :Electric)
      battle.pbDisplay(_INTL("\\j[{1},은,는] 일렉트릭필드를 전개하여 미래 기관을 가동했다!", battler.pbThis))
    end
  }
)

Battle::AbilityEffects::DamageCalcFromUser.add(:HADRONENGINE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 4 / 3.0 if move.specialMove? && user.battle.field.terrain == :Electric
  }
)

#===============================================================================
# Protosynthesis, Quark Drive
#===============================================================================
Battle::AbilityEffects::OnSwitchIn.add(:PROTOSYNTHESIS,
  proc { |ability, battler, battle, switch_in|
    next if battler.effects[PBEffects::Transform]
    case ability
    when :PROTOSYNTHESIS then field_check = [:Sun, :HarshSun].include?(battle.pbWeather)
    when :QUARKDRIVE     then field_check = battle.field.terrain == :Electric
    end
    if !field_check && !battler.effects[PBEffects::BoosterEnergy] && battler.effects[PBEffects::ParadoxStat]
      battle.pbDisplay(_INTL("{1}의 {2} 효과가 사라졌다!", battler.pbThis(true), battler.abilityName))
      battler.effects[PBEffects::ParadoxStat] = nil
    end
    next if battler.effects[PBEffects::ParadoxStat]
    next if !field_check && battler.item != :BOOSTERENERGY
    highestStat = nil
    highestStatVal = 0
    stageMul = [2, 2, 2, 2, 2, 2, 2, 3, 4, 5, 6, 7, 8]
    stageDiv = [8, 7, 6, 5, 4, 3, 2, 2, 2, 2, 2, 2, 2]
    battler.plainStats.each do |stat, val|
      stage = battler.stages[stat] + 6
      realStat = (val.to_f * stageMul[stage] / stageDiv[stage]).floor
      if realStat > highestStatVal
        highestStatVal = realStat 
        highestStat = stat
      end
    end
    if highestStat
      battle.pbShowAbilitySplash(battler)
      if field_check
        case ability
        when :PROTOSYNTHESIS then cause = "쾌청 상태"
        when :QUARKDRIVE     then cause = "일렉트릭 필드"
        end
        battle.pbDisplay(_INTL("#{cause}로 인해 {1}의 \\j[{2},이,가] 활성화되었다!", battler.pbThis(true), battler.abilityName))
      elsif battler.item_id == :BOOSTERENERGY
        battler.effects[PBEffects::BoosterEnergy] = true
        battle.pbDisplay(_INTL("\\j[{1},은,는] \\j[{2},을,를] 사용해 \\j[{3},을,를] 활성화시켰다!", battler.pbThis, battler.itemName, battler.abilityName))
        battler.pbHeldItemTriggered(battler.item)
      end
      battler.effects[PBEffects::ParadoxStat] = highestStat
      battle.pbDisplay(_INTL("{1}의 \\j[{2},이,가] 상승했다!", battler.pbThis, GameData::Stat.get(highestStat).name))
      battle.pbHideAbilitySplash(battler)
    end
  }
)

Battle::AbilityEffects::OnSwitchIn.copy(:PROTOSYNTHESIS, :QUARKDRIVE)

Battle::AbilityEffects::OnTerrainChange.add(:QUARKDRIVE,
  proc { |ability, battler, battle, switch_in|
    Battle::AbilityEffects.triggerOnSwitchIn(ability, battler, battle, switch_in)
  }
)

#-------------------------------------------------------------------------------
# Damage calcs (User).
Battle::AbilityEffects::DamageCalcFromUser.add(:PROTOSYNTHESIS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    next if user.effects[PBEffects::Transform]
    stat = user.effects[PBEffects::ParadoxStat]
    mults[:attack_multiplier] *= 1.3 if move.physicalMove? && stat == :ATTACK
    mults[:attack_multiplier] *= 1.3 if move.specialMove?  && stat == :SPECIAL_ATTACK
  }
)

Battle::AbilityEffects::DamageCalcFromUser.copy(:PROTOSYNTHESIS, :QUARKDRIVE)

#-------------------------------------------------------------------------------
# Damage calcs (Target).
Battle::AbilityEffects::DamageCalcFromTarget.add(:PROTOSYNTHESIS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    next if target.effects[PBEffects::Transform]
    stat = target.effects[PBEffects::ParadoxStat]
    mults[:defense_multiplier] *= 1.3 if move.physicalMove? && stat == :DEFENSE
    mults[:defense_multiplier] *= 1.3 if move.specialMove?  && stat == :SPECIAL_DEFENSE
  }
)

Battle::AbilityEffects::DamageCalcFromTarget.copy(:PROTOSYNTHESIS, :QUARKDRIVE)

#-------------------------------------------------------------------------------
# Speed calcs.
Battle::AbilityEffects::SpeedCalc.add(:PROTOSYNTHESIS,
  proc { |ability, battler, mult, ret|
    next mult if battler.effects[PBEffects::Transform]
    next mult * 1.5 if battler.effects[PBEffects::ParadoxStat] == :SPEED
  }
)

Battle::AbilityEffects::SpeedCalc.copy(:PROTOSYNTHESIS, :QUARKDRIVE)