#===============================================================================
# * STAB Charm
#===============================================================================

class Battle::Move
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    # Global abilities
    if (@battle.pbCheckGlobalAbility(:DARKAURA) && type == :DARK) ||
       (@battle.pbCheckGlobalAbility(:FAIRYAURA) && type == :FAIRY)
      if @battle.pbCheckGlobalAbility(:AURABREAK)
        multipliers[:power_multiplier] *= 3 / 4.0
      else
        multipliers[:power_multiplier] *= 4 / 3.0
      end
    end
    # Ability effects that alter damage
    if user.abilityActive?
      Battle::AbilityEffects.triggerDamageCalcFromUser(
        user.ability, user, target, self, multipliers, baseDmg, type
      )
    end
    if !@battle.moldBreaker
      # NOTE: It's odd that the user's Mold Breaker prevents its partner's
      #       beneficial abilities (i.e. Flower Gift boosting Atk), but that's
      #       how it works.
      user.allAllies.each do |b|
        next if !b.abilityActive?
        Battle::AbilityEffects.triggerDamageCalcFromAlly(
          b.ability, user, target, self, multipliers, baseDmg, type
        )
      end
      if target.abilityActive?
        Battle::AbilityEffects.triggerDamageCalcFromTarget(
          target.ability, user, target, self, multipliers, baseDmg, type
        )
      end
    end
    if target.abilityActive?
      Battle::AbilityEffects.triggerDamageCalcFromTargetNonIgnorable(
        target.ability, user, target, self, multipliers, baseDmg, type
      )
    end
    if !@battle.moldBreaker
      target.allAllies.each do |b|
        next if !b.abilityActive?
        Battle::AbilityEffects.triggerDamageCalcFromTargetAlly(
          b.ability, user, target, self, multipliers, baseDmg, type
        )
      end
    end
    # Item effects that alter damage
    if user.itemActive?
      Battle::ItemEffects.triggerDamageCalcFromUser(
        user.item, user, target, self, multipliers, baseDmg, type
      )
    end
    if target.itemActive?
      Battle::ItemEffects.triggerDamageCalcFromTarget(
        target.item, user, target, self, multipliers, baseDmg, type
      )
    end
    # Parental Bond's second attack
    if user.effects[PBEffects::ParentalBond] == 1
      multipliers[:power_multiplier] /= (Settings::MECHANICS_GENERATION >= 7) ? 4 : 2
    end
    # Other
    if user.effects[PBEffects::MeFirst]
      multipliers[:power_multiplier] *= 1.5
    end
    if user.effects[PBEffects::HelpingHand] && !self.is_a?(Battle::Move::Confusion)
      multipliers[:power_multiplier] *= 1.5
    end
    if user.effects[PBEffects::Charge] > 0 && type == :ELECTRIC
      multipliers[:power_multiplier] *= 2
    end
    # Mud Sport
    if type == :ELECTRIC
      if @battle.allBattlers.any? { |b| b.effects[PBEffects::MudSport] }
        multipliers[:power_multiplier] /= 3
      end
      if @battle.field.effects[PBEffects::MudSportField] > 0
        multipliers[:power_multiplier] /= 3
      end
    end
    # Water Sport
    if type == :FIRE
      if @battle.allBattlers.any? { |b| b.effects[PBEffects::WaterSport] }
        multipliers[:power_multiplier] /= 3
      end
      if @battle.field.effects[PBEffects::WaterSportField] > 0
        multipliers[:power_multiplier] /= 3
      end
    end
    # Terrain moves
    terrain_multiplier = (Settings::MECHANICS_GENERATION >= 8) ? 1.3 : 1.5
    case @battle.field.terrain
    when :Electric
      multipliers[:power_multiplier] *= terrain_multiplier if type == :ELECTRIC && user.affectedByTerrain?
    when :Grassy
      multipliers[:power_multiplier] *= terrain_multiplier if type == :GRASS && user.affectedByTerrain?
    when :Psychic
      multipliers[:power_multiplier] *= terrain_multiplier if type == :PSYCHIC && user.affectedByTerrain?
    when :Misty
      multipliers[:power_multiplier] /= 2 if type == :DRAGON && target.affectedByTerrain?
    end
    # Badge multipliers
    if @battle.internalBattle
      if user.pbOwnedByPlayer?
        if physicalMove? && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_ATTACK
          multipliers[:attack_multiplier] *= 1.1
        elsif specialMove? && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_SPATK
          multipliers[:attack_multiplier] *= 1.1
        end
      end
      if target.pbOwnedByPlayer?
        if physicalMove? && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_DEFENSE
          multipliers[:defense_multiplier] *= 1.1
        elsif specialMove? && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_SPDEF
          multipliers[:defense_multiplier] *= 1.1
        end
      end
    end
    # Multi-targeting attacks
    multipliers[:final_damage_multiplier] *= 0.75 if numTargets > 1
    # Weather
    case user.effectiveWeather
    when :Sun, :HarshSun
      case type
      when :FIRE
        multipliers[:final_damage_multiplier] *= 1.5
      when :WATER
        if @function_code = "IncreasePowerInSunWeather"
          multipliers[:final_damage_multiplier] *= 1.5
        else
          multipliers[:final_damage_multiplier] /= 2
        end
      end
    when :Rain, :HeavyRain
      case type
      when :FIRE
        multipliers[:final_damage_multiplier] /= 2
      when :WATER
        multipliers[:final_damage_multiplier] *= 1.5
      end
    when :Sandstorm
      if target.pbHasType?(:ROCK) && specialMove? && @function_code != "UseTargetDefenseInsteadOfTargetSpDef"
        multipliers[:defense_multiplier] *= 1.5
      end
    when :ShadowSky
      multipliers[:final_damage_multiplier] *= 1.5 if type == :SHADOW
    end
    # Critical hits
    if target.damageState.critical
      if Settings::NEW_CRITICAL_HIT_RATE_MECHANICS
        multipliers[:final_damage_multiplier] *= 1.5
      else
        multipliers[:final_damage_multiplier] *= 2
      end
    end
    # Random variance
    if !self.is_a?(Battle::Move::Confusion)
      random = 85 + @battle.pbRandom(16)
      multipliers[:final_damage_multiplier] *= random / 100.0
    end
    # STAB
    if type && user.pbHasType?(type)
      if user.hasActiveAbility?(:ADAPTABILITY)
        multipliers[:final_damage_multiplier] *= 2
      else
        multipliers[:final_damage_multiplier] *= 1.5
      end
    end
    # Type effectiveness
    multipliers[:final_damage_multiplier] *= target.damageState.typeMod
    # Burn
    if user.status == :BURN && physicalMove? && damageReducedByBurn? &&
       !user.hasActiveAbility?(:GUTS)
      multipliers[:final_damage_multiplier] /= 2
    end
    # Aurora Veil, Reflect, Light Screen
    if !ignoresReflect? && !target.damageState.critical &&
       !user.hasActiveAbility?(:INFILTRATOR)
      if target.pbOwnSide.effects[PBEffects::AuroraVeil] > 0
        if @battle.pbSideBattlerCount(target) > 1
          multipliers[:final_damage_multiplier] *= 2 / 3.0
        else
          multipliers[:final_damage_multiplier] /= 2
        end
      elsif target.pbOwnSide.effects[PBEffects::Reflect] > 0 && physicalMove?
        if @battle.pbSideBattlerCount(target) > 1
          multipliers[:final_damage_multiplier] *= 2 / 3.0
        else
          multipliers[:final_damage_multiplier] /= 2
        end
      elsif target.pbOwnSide.effects[PBEffects::LightScreen] > 0 && specialMove?
        if @battle.pbSideBattlerCount(target) > 1
          multipliers[:final_damage_multiplier] *= 2 / 3.0
        else
          multipliers[:final_damage_multiplier] /= 2
        end
      end
    end
    # Minimize
    if target.effects[PBEffects::Minimize] && tramplesMinimize?
      multipliers[:final_damage_multiplier] *= 2
    end
    # Adds 25% more damage to STAB Bonus.
    if type && user.pbHasType?(type) && $player.activeCharm?(:STABCHARM) && user.pbOwnedByPlayer?
      multipliers[:final_damage_multiplier] *= 1.25
    end
	# Resistor Charm
	if Effectiveness.super_effective?(target.damageState.typeMod) && $player.activeCharm?(:RESISTORCHARM) && target.pbOwnedByPlayer?
	  multipliers[:final_damage_multiplier] *= 0.75
	end
    # Move-specific base damage modifiers
    multipliers[:power_multiplier] = pbBaseDamageMultiplier(multipliers[:power_multiplier], user, target)
    # Move-specific final damage modifiers
    multipliers[:final_damage_multiplier] = pbModifyDamage(multipliers[:final_damage_multiplier], user, target)
  end
end