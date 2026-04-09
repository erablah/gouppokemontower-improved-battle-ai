# Battle-related bug fixes


class Battle::AI::AITrainer
  alias remove_flags_best_traniner set_up_skill_flags
  def set_up_skill_flags
    remove_flags_best_traniner
    if best_skill?
      @skill_flags.delete("ReserveLastPokemon")
    end
  end
end

# AI compute takes a lot of time, so slow animated battler frame stepping only
# while battle speedup is active.
class DeluxeBitmapWrapper
  alias _tower_speedup_aware_update update
  def update
    return false if self.disposed?
    return false if $PokemonSystem.animated_sprites > 0
    return false if @speed <= 0
    timer = System.uptime
    delay = ((@speed / 2.0) * Settings::ANIMATION_FRAME_DELAY).round / 1000.0
    if defined?($GameSpeed) && $GameSpeed && $GameSpeed > 0 &&
       defined?(SPEEDUP_STAGES) && SPEEDUP_STAGES[$GameSpeed]
      delay *= SPEEDUP_STAGES[$GameSpeed]
    end
    return if timer - @last_uptime < delay
    (@reversed) ? @frame_idx -= 1 : @frame_idx += 1
    @frame_idx = 0 if @frame_idx >= @total_frames
    @frame_idx = @total_frames - 1 if @frame_idx < 0
    @last_uptime = timer
  end
end

class Battle::Move
  # drdooms charm bugfix and also drought water move bugfix
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    args = [user, target, numTargets, type, baseDmg]
    pbCalcDamageMults_Global(*args, multipliers)
    pbCalcDamageMults_Abilities(*args, multipliers)
    pbCalcDamageMults_Items(*args, multipliers)
    if user.effects[PBEffects::ParentalBond] == 1
      multipliers[:power_multiplier] /= (Settings::MECHANICS_GENERATION >= 7) ? 4 : 2
    end
    pbCalcDamageMults_Other(*args, multipliers)
    pbCalcDamageMults_Field(*args, multipliers)
    pbCalcDamageMults_Badges(*args, multipliers)
    multipliers[:final_damage_multiplier] *= 0.75 if numTargets > 1
    pbCalcDamageMults_Weather(*args, multipliers)
    pbCalcDamageMults_Random(*args, multipliers)
    pbCalcDamageMults_Type(*args, multipliers)
    pbCalcDamageMults_Status(*args, multipliers)
    pbCalcDamageMults_Screens(*args, multipliers)
    if target.effects[PBEffects::Minimize] && tramplesMinimize?
      multipliers[:final_damage_multiplier] *= 2
    end
    if defined?(PBEffects::GlaiveRush) && target.effects[PBEffects::GlaiveRush] > 0
      multipliers[:final_damage_multiplier] *= 2 
    end
    multipliers[:power_multiplier] = pbBaseDamageMultiplier(multipliers[:power_multiplier], user, target)
    multipliers[:final_damage_multiplier] = pbModifyDamage(multipliers[:final_damage_multiplier], user, target)
    # Adds 25% more damage to STAB Bonus.
    has_stab = user.tera? ? (user.pbPreTeraTypes.include?(type) || user.typeTeraBoosted?(type)) : user.pbHasType?(type)
    if type && has_stab && $player.activeCharm?(:STABCHARM) && user.pbOwnedByPlayer?
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

  #-----------------------------------------------------------------------------
  # Aliased to allow Z-Moves to partially hit through Protect.
  #-----------------------------------------------------------------------------
  alias zmove_pbCalcDamageMultipliers pbCalcDamageMultipliers
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    zmove_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    multipliers[:final_damage_multiplier] /= 4 if zMove? && target.isProtected?(user, self)
  end

  #-----------------------------------------------------------------------------
  # Aliased to allow Dynamax moves to partially hit through Protect.
  #-----------------------------------------------------------------------------
  alias dynamax_pbCalcDamageMultipliers pbCalcDamageMultipliers
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    dynamax_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    multipliers[:final_damage_multiplier] /= 4 if dynamaxMove? && target.isProtected?(user, self)
  end

  alias piercingdrill_pbCalcDamageMultipliers pbCalcDamageMultipliers
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    piercingdrill_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    if contactMove? && (user.hasActiveAbility?(:UNSEENFIST) || user.hasActiveAbility?(:PIERCINGDRILL)) &&
       target.isProtected?(user, self)
      PBDebug.log("[PIERCINGDRILL] #{user.pbThis} pierces Protect with #{name}, applying 1/4 damage")
      multipliers[:final_damage_multiplier] /= 4
    end
  end
end