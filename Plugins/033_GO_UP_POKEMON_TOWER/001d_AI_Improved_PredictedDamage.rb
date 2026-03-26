#===============================================================================
# Battle::AI::AIMove — predicted_damage using actual battle simulation.
# Replaces rough_damage approximation with real pbCalcDamage.
#===============================================================================

class Battle::AI::AIMove
  #---------------------------------------------------------------------------
  # Override sub-methods to use SimBattler instead of .battler
  #---------------------------------------------------------------------------

  def rough_type(user = @ai.user)
    return @move.pbCalcType(user) if @ai.trainer.medium_skill?
    @move.type
  end

  def pbTarget(user = @ai.user)
    @move.pbTarget(user)
  end

  def rough_priority(user = @ai.user)
    ret = @move.pbPriority(user)
    if user.ability_active?
      ret = Battle::AbilityEffects.triggerPriorityChange(user.ability, user, @move, ret)
      user.effects[PBEffects::Prankster] = false   # Untrigger
    end
    ret
  end

  def targets_multiple_battlers?(user = @ai.user)
    target_data = pbTarget(user)
    return false if target_data.num_targets <= 1
    num_targets = 0
    case target_data.id
    when :AllAllies
      @ai.battle.allSameSideBattlers(user.index).each { |b| num_targets += 1 if b.index != user.index }
    when :UserAndAllies
      @ai.battle.allSameSideBattlers(user.index).each { |_b| num_targets += 1 }
    when :AllNearFoes
      @ai.battle.allOtherSideBattlers(user.index).each { |b| num_targets += 1 if b.near?(user) }
    when :AllFoes
      @ai.battle.allOtherSideBattlers(user.index).each { |_b| num_targets += 1 }
    when :AllNearOthers
      @ai.battle.allBattlers.each { |b| num_targets += 1 if b.near?(user) }
    when :AllBattlers
      @ai.battle.allBattlers.each { |_b| num_targets += 1 }
    end
    num_targets > 1
  end

  #---------------------------------------------------------------------------
  # predicted_damage: Main entry point for damage prediction.
  # Uses actual battle simulation via simulate_move.
  #
  # Parameters:
  #   user   - SimBattler (attacker)
  #   target - SimBattler (defender)
  #   switch_in - :user or :target if simulating switch-in (nil for active vs active)
  #   switch_in_stages - Hash of stat stages to apply on switch-in
  #---------------------------------------------------------------------------
  def predicted_damage(user:, target:, switch_in: nil, switch_in_stages: nil)
    sim_battle = @ai.sim_battle

    # Apply switch-in stages if provided (e.g., Baton Pass)
    if switch_in_stages
      receiver = (switch_in == :user) ? user : target
      switch_in_stages.each { |stat, stage| receiver.sim_stages[stat] = stage.clamp(-6, 6) }
    end

    # Simulate switch-in effects (weather, terrain, Intimidate)
    if switch_in
      switch_in_sim = (switch_in == :user) ? user : target
      sim_battle.field.weather = @ai.simulated_weather(switch_in_sim, sim_battle.field.weather)
      sim_battle.field.terrain = @ai.simulated_terrain(switch_in_sim, sim_battle.field.terrain)
      @ai.simulate_intimidate(user, target, switch_in)
    end

    # Check for move failure before simulating
    will_fail = check_move_failure(user, target)
    return 0 if will_fail

    # Run actual damage simulation
    result = @ai.simulate_move(user, target, @move, deterministic: true)
    dmg = result[:damage]

    # Apply Tera STAB correction if needed
    calc_type = rough_type(user)
    correction = tera_stab_correction(user, calc_type)
    if correction != 1.0
      PBDebug.log_ai("[predicted_damage] Tera STAB correction: #{correction.round(3)}x (#{calc_type})")
      dmg = (dmg * correction).round
    end

    dmg
  end

  #---------------------------------------------------------------------------
  # Check if move will fail before simulating
  #---------------------------------------------------------------------------
  def check_move_failure(user, target)
    # Temporarily set AI references for pbPredictMoveFailure compatibility
    prev_user   = @ai.instance_variable_get(:@user)
    prev_target = @ai.instance_variable_get(:@target)
    prev_move   = @ai.instance_variable_get(:@move)
    @ai.instance_variable_set(:@user, user)
    @ai.instance_variable_set(:@target, target)
    @ai.instance_variable_set(:@move, self)
    begin
      will_fail = (@ai.pbPredictMoveFailure rescue false) ||
                  (@ai.pbPredictMoveFailureAgainstTarget rescue false)
      will_fail
    ensure
      @ai.instance_variable_set(:@user, prev_user)
      @ai.instance_variable_set(:@target, prev_target)
      @ai.instance_variable_set(:@move, prev_move)
    end
  end

  #---------------------------------------------------------------------------
  # Tera STAB correction
  #---------------------------------------------------------------------------
  def tera_stab_correction(user, calc_type)
    return 1.0 unless user.tera?
    return 1.0 unless calc_type

    adaptability = user.hasActiveAbility?(:ADAPTABILITY)
    adaptability = false if user.tera_type == :STELLAR

    pre_types = user.pbPreTeraTypes
    is_original = pre_types.include?(calc_type)
    is_tera_boosted = user.typeTeraBoosted?(calc_type)

    current_types = user.pbTypes(true)
    applied = if current_types.include?(calc_type)
                adaptability ? 2.0 : 1.5
              else
                1.0
              end

    correct = if is_original && is_tera_boosted
                adaptability ? 2.25 : 2.0
              elsif is_original
                adaptability ? 2.0 : 1.5
              elsif is_tera_boosted
                stab = (user.tera_type == :STELLAR) ? 1.2 : 1.5
                adaptability ? 2.0 : stab
              else
                1.0
              end

    correct / applied
  end

  #---------------------------------------------------------------------------
  # Calculate expected number of hits for multi-hit moves
  #---------------------------------------------------------------------------
  def expected_multi_hits(user)
    if @move.is_a?(Battle::Move::HitTenTimes)
      return user.hasActiveItem?(:LOADEDDICE) ? 7.0 : 5.0
    end
    if @move.is_a?(Battle::Move::HitThreeTimes)
      return 3.0
    end
    if @move.is_a?(Battle::Move::HitTwoToFiveTimes)
      return 4.5 if user.hasActiveAbility?(:SKILLLINK)
      return 4.5 if user.hasActiveItem?(:LOADEDDICE)
      return 3.0
    end
    return 2.0 if @move.is_a?(Battle::Move::HitTwoTimes)
    1.0
  end
end

#===============================================================================
# Override MoveBasePower for multi-hit moves (accounts for Loaded Dice)
#===============================================================================
Battle::AI::Handlers::MoveBasePower.add("HitTwoToFiveTimes",
  proc { |power, move, user, target, ai, battle|
    next power * 5 if user.has_active_ability?(:SKILLLINK)
    next power * 4 if user.has_active_item?(:LOADEDDICE)
    next power * 31 / 10   # Average damage dealt
  }
)
Battle::AI::Handlers::MoveBasePower.copy("HitTwoToFiveTimes",
                                         "HitTwoToFiveTimesRaiseUserSpd1LowerUserDef1")

Battle::AI::Handlers::MoveBasePower.add("HitTwoToFiveTimesOrThreeForAshGreninja",
  proc { |power, move, user, target, ai, battle|
    if user.isSpecies?(:GRENINJA) && user.form == 2
      next move.move.pbBaseDamage(power, user, target) * move.move.pbNumHits(user, [target])
    end
    next power * 5 if user.has_active_ability?(:SKILLLINK)
    next power * 4 if user.has_active_item?(:LOADEDDICE)
    next power * 31 / 10   # Average damage dealt
  }
)
