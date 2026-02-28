#===============================================================================
# 3. move effect handlers (many overrides)
#===============================================================================

module AIEffectScoreHelper
  def self.get_inherent_preference(move, multiplier)
    chance = move.move.addlEffect
    chance = move.move.accuracy if chance == 0
    return (multiplier * (chance / 100.0)).round
  end

  def self.get_target_heal_penalty(target, ai)
    penalty = 0
    if target.has_active_ability?(:SHEDSKIN)
      penalty -= 8
    elsif target.has_active_ability?(:HYDRATION) &&
          [:Rain, :HeavyRain].include?(target.battler.effectiveWeather)
      penalty -= 15
    end
    ai.each_same_side_battler(target.side) do |b, i|
      penalty -= 8 if i != target.index && b.has_active_ability?(:HEALER)
    end
    return penalty
  end
end

#===============================================================================
# FlinchTarget
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("FlinchTarget",
  proc { |score, move, user, target, ai, battle|
    next score if target.faster_than?(user) || target.effects[PBEffects::Substitute] > 0
    next score if target.has_active_ability?(:INNERFOCUS) && !battle.moldBreaker
    add_effect = move.get_score_change_for_additional_effect(user, target)
    next score if add_effect == -999   # Additional effect will be negated
    score += add_effect

    # Inherent preference scaled by effect chance
    score += AIEffectScoreHelper.get_inherent_preference(move, 30)

    # Prefer if the target is paralysed, confused or infatuated, to compound the
    # turn skipping
    score += 8 if target.status == :PARALYSIS ||
                  target.effects[PBEffects::Confusion] > 1 ||
                  target.effects[PBEffects::Attract] >= 0
    next score
  }
)

#===============================================================================
# SleepTarget
#===============================================================================
# Add score modifier for Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("SleepTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    next useless_score if target.effects[PBEffects::Yawn] > 0   # Target is going to fall asleep anyway
    # No score modifier if the sleep will be removed immediately
    next useless_score if target.has_active_item?([:CHESTOBERRY, :LUMBERRY])
    next useless_score if target.faster_than?(user) &&
                          target.has_active_ability?(:HYDRATION) &&
                          [:Rain, :HeavyRain].include?(target.battler.effectiveWeather)
    if target.battler.pbCanSleep?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect
      
      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 30)

      # Prefer if the user or an ally has a move/ability that is better if the target is asleep
      ai.each_same_side_battler(user.side) do |b, i|
        score += 5 if b.has_move_with_function?("DoublePowerIfTargetAsleepCureTarget",
                                                "DoublePowerIfTargetStatusProblem",
                                                "HealUserByHalfOfDamageDoneIfTargetAsleep",
                                                "StartDamageTargetEachTurnIfTargetAsleep")
        score += 10 if b.has_active_ability?(:BADDREAMS)
      end
      # Don't prefer if target benefits from having the sleep status problem
      # NOTE: The target's Guts/Quick Feet will benefit from the target being
      #       asleep, but the target won't (usually) be able to make use of
      #       them, so they're not worth considering.
      score -= 10 if target.has_active_ability?(:EARLYBIRD)
      score -= 8 if target.has_active_ability?(:MARVELSCALE)
      # Don't prefer if target has a move it can use while asleep
      score -= 8 if target.check_for_move { |m| m.usableWhenAsleep? }
      # Don't prefer if the target can heal itself (or be healed by an ally)
      score += AIEffectScoreHelper.get_target_heal_penalty(target, ai)
    end
    next score
  }
)

#===============================================================================
# PoisonTarget
#===============================================================================
# Add score modifier for Barb Barrage and Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("PoisonTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    next useless_score if target.has_active_ability?(:POISONHEAL)
    # No score modifier if the poisoning will be removed immediately
    next useless_score if target.has_active_item?([:PECHABERRY, :LUMBERRY])
    next useless_score if target.faster_than?(user) &&
                          target.has_active_ability?(:HYDRATION) &&
                          [:Rain, :HeavyRain].include?(target.battler.effectiveWeather)
    if target.battler.pbCanPoison?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect

      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 30)

      # Prefer if the target is at high HP
      if ai.trainer.has_skill_flag?("HPAware")
        score += 15 * target.hp / target.totalhp
      end
      # Prefer if the user or an ally has a move/ability that is better if the target is poisoned
      ai.each_same_side_battler(user.side) do |b, i|
        score += 5 if b.has_move_with_function?("DoublePowerIfTargetPoisoned",
                                                "DoublePowerIfTargetStatusProblem",
                                                "DoublePowerIfTargetPoisonedPoisonTarget",
                                                "DoublePowerIfTargetStatusProblemBurnTarget")
        score += 10 if b.has_active_ability?(:MERCILESS)
      end
      # Don't prefer if target benefits from having the poison status problem
      score -= 8 if target.has_active_ability?([:GUTS, :MARVELSCALE, :QUICKFEET, :TOXICBOOST])
      score -= 25 if target.has_active_ability?(:POISONHEAL)
      score -= 20 if target.has_active_ability?(:SYNCHRONIZE) &&
                     user.battler.pbCanPoisonSynchronize?(target.battler)
      score -= 5 if target.has_move_with_function?("DoublePowerIfUserPoisonedBurnedParalyzed",
                                                   "CureUserBurnPoisonParalysis")
      score -= 15 if target.check_for_move { |m|
        m.function_code == "GiveUserStatusToTarget" && user.battler.pbCanPoison?(target.battler, false, m)
      }
      # Don't prefer if the target won't take damage from the poison
      score -= 20 if !target.battler.takesIndirectDamage?
      # Don't prefer if the target can heal itself (or be healed by an ally)
      score += AIEffectScoreHelper.get_target_heal_penalty(target, ai)
    end
    next score
  }
)

#===============================================================================
# ParalyzeTarget
#===============================================================================
# Add score modifier for Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("ParalyzeTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    # No score modifier if the paralysis will be removed immediately
    next useless_score if target.has_active_item?([:CHERIBERRY, :LUMBERRY])
    next useless_score if target.faster_than?(user) &&
                          target.has_active_ability?(:HYDRATION) &&
                          [:Rain, :HeavyRain].include?(target.battler.effectiveWeather)
    if target.battler.pbCanParalyze?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect
      
      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 20)

      # Prefer if the target is faster than the user but will become slower if
      # paralysed
      if target.faster_than?(user)
        user_speed = user.rough_stat(:SPEED)
        target_speed = target.rough_stat(:SPEED)
        score += 15 if target_speed < user_speed * ((Settings::MECHANICS_GENERATION >= 7) ? 2 : 4)
      end
      # Prefer if the target is confused or infatuated, to compound the turn skipping
      score += 7 if target.effects[PBEffects::Confusion] > 1
      score += 7 if target.effects[PBEffects::Attract] >= 0
      # Prefer if the user or an ally has a move/ability that is better if the target is paralysed
      ai.each_same_side_battler(user.side) do |b, i|
        score += 5 if b.has_move_with_function?("DoublePowerIfTargetParalyzedCureTarget",
                                                "DoublePowerIfTargetStatusProblem",
                                                "DoublePowerIfTargetStatusProblemBurnTarget")
      end
      # Don't prefer if target benefits from having the paralysis status problem
      score -= 8 if target.has_active_ability?([:GUTS, :MARVELSCALE, :QUICKFEET])
      score -= 20 if target.has_active_ability?(:SYNCHRONIZE) &&
                     user.battler.pbCanParalyzeSynchronize?(target.battler)
      score -= 5 if target.has_move_with_function?("DoublePowerIfUserPoisonedBurnedParalyzed",
                                                   "CureUserBurnPoisonParalysis")
      score -= 15 if target.check_for_move { |m|
        m.function_code == "GiveUserStatusToTarget" && user.battler.pbCanParalyze?(target.battler, false, m)
      }
      # Don't prefer if the target can heal itself (or be healed by an ally)
      score += AIEffectScoreHelper.get_target_heal_penalty(target, ai)
    end
    next score
  }
)

#===============================================================================
# BurnTarget
#===============================================================================
# Add score modifier for Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("BurnTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    # No score modifier if the burn will be removed immediately
    next useless_score if target.has_active_item?([:RAWSTBERRY, :LUMBERRY])
    next useless_score if target.faster_than?(user) &&
                          target.has_active_ability?(:HYDRATION) &&
                          [:Rain, :HeavyRain].include?(target.battler.effectiveWeather)
    if target.battler.pbCanBurn?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect
      
      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 20)

      # Prefer if the target knows any physical moves that will be weaked by a burn
      if !target.has_active_ability?(:GUTS) && target.check_for_move { |m| m.physicalMove? }
        score += 8
        score += 8 if !target.check_for_move { |m| m.specialMove? }
      end
      # Prefer if the user or an ally has a move/ability that is better if the target is burned
      ai.each_same_side_battler(user.side) do |b, i|
        score += 5 if b.has_move_with_function?("DoublePowerIfTargetStatusProblem",
                                                "DoublePowerIfTargetStatusProblemBurnTarget")
      end
      # Don't prefer if target benefits from having the burn status problem
      score -= 8 if target.has_active_ability?([:FLAREBOOST, :GUTS, :MARVELSCALE, :QUICKFEET])
      score -= 5 if target.has_active_ability?(:HEATPROOF)
      score -= 20 if target.has_active_ability?(:SYNCHRONIZE) &&
                     user.battler.pbCanBurnSynchronize?(target.battler)
      score -= 5 if target.has_move_with_function?("DoublePowerIfUserPoisonedBurnedParalyzed",
                                                   "CureUserBurnPoisonParalysis")
      score -= 15 if target.check_for_move { |m|
        m.function_code == "GiveUserStatusToTarget" && user.battler.pbCanBurn?(target.battler, false, m)
      }
      # Don't prefer if the target won't take damage from the burn
      score -= 20 if !target.battler.takesIndirectDamage?
      # Don't prefer if the target can heal itself (or be healed by an ally)
      score += AIEffectScoreHelper.get_target_heal_penalty(target, ai)
    end
    next score
  }
)

#===============================================================================
# FreezeTarget
#===============================================================================
# Add score modifier for Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("FreezeTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    # No score modifier if the freeze will be removed immediately
    next useless_score if target.has_active_item?([:ASPEARBERRY, :LUMBERRY])
    next useless_score if target.faster_than?(user) &&
                          target.has_active_ability?(:HYDRATION) &&
                          [:Rain, :HeavyRain].include?(target.battler.effectiveWeather)
    if target.battler.pbCanFreeze?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect
      
      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 30)

      # Prefer if the user or an ally has a move/ability that is better if the target is frozen
      ai.each_same_side_battler(user.side) do |b, i|
        score += 5 if b.has_move_with_function?("DoublePowerIfTargetStatusProblem",
                                                "DoublePowerIfTargetStatusProblemBurnTarget")
      end
      # Don't prefer if target benefits from having the frozen status problem
      # NOTE: The target's Guts/Quick Feet will benefit from the target being
      #       frozen, but the target won't be able to make use of them, so
      #       they're not worth considering.
      score -= 8 if target.has_active_ability?(:MARVELSCALE)
      # Don't prefer if the target knows a move that can thaw it
      score -= 15 if target.check_for_move { |m| m.thawsUser? }
      # Don't prefer if the target can heal itself (or be healed by an ally)
      score += AIEffectScoreHelper.get_target_heal_penalty(target, ai)
    end
    next score
  }
)

#===============================================================================
# [NEW] Taunt Override — Tactical Taunt
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("DisableTargetStatusMoves",
  proc { |score, move, user, target, ai, battle|
    next Battle::AI::MOVE_USELESS_SCORE if !target.check_for_move { |m| m.statusMove? }

    # Already taunted
    next Battle::AI::MOVE_USELESS_SCORE if target.effects[PBEffects::Taunt] > 0

    # Mental Herb cures taunt
    next Battle::AI::MOVE_USELESS_SCORE if target.has_active_item?(:MENTALHERB)

    # Not worth on Choice-locked targets
    if !target.effects[PBEffects::ChoiceBand]
      if target.has_active_item?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF]) ||
         target.has_active_ability?(:GORILLATACTICS)
        next Battle::AI::MOVE_USELESS_SCORE
      end
    end

    # Count status moves the target has
    status_count = 0
    has_setup = false
    has_recovery = false
    target.battler.eachMove do |m|
      if m.statusMove? && (m.pp > 0 || m.total_pp == 0)
        status_count += 1
        has_setup = true if m.function_code.start_with?("RaiseUser")
        healing_codes = [
          "HealUserHalfOfTotalHP",
          "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn",
          "HealUserDependingOnWeather"
        ]
        has_recovery = true if healing_codes.include?(m.function_code)
      end
    end

    # Base score for each status move the target has
    score += status_count * 3

    # Prefer taunting setup mons
    score += 10 if has_setup

    # Prefer taunting recovery users
    score += 8 if has_recovery

    # Prefer if target has protection moves
    if target.check_for_move { |m|
         m.statusMove? && m.function_code.start_with?("Protect")
       }
      score += 5
    end

    PBDebug.log_score_change(score - 100, "Taunt: #{status_count} status moves#{has_setup ? ', has setup' : ''}#{has_recovery ? ', has recovery' : ''}.")
    next score
  }
)

#===============================================================================
# [NEW] Yawn Override — Tactical Yawn
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("SleepTargetNextTurn",
  proc { |score, move, user, target, ai, battle|
    useless_score = Battle::AI::MOVE_USELESS_SCORE

    # Already drowsy or asleep
    next useless_score if target.effects[PBEffects::Yawn] > 0
    next useless_score if target.status == :SLEEP

    # Can't sleep
    next useless_score if !target.battler.pbCanSleep?(user.battler, false, move.move)

    # Immediate cure
    next useless_score if target.has_active_item?([:CHESTOBERRY, :LUMBERRY])
    next useless_score if target.faster_than?(user) &&
                          target.has_active_ability?(:HYDRATION) &&
                          [:Rain, :HeavyRain].include?(target.battler.effectiveWeather)

    # Electric Terrain blocks sleep on grounded
    if ai.trainer.high_skill?
      next useless_score if user.battler.battle.field.terrain == :Electric &&
                            target.battler.affectedByTerrain?
    end

    # Base preference — Yawn forces switches, which is inherently useful
    score += 15
    PBDebug.log_score_change(15, "Yawn: forces switch or sleeps target.")

    # Prefer as pseudo-phaze when hazards are up
    foe_side = target.pbOwnSide
    hazard_value = 0
    hazard_value += 8 if foe_side.effects[PBEffects::StealthRock]
    hazard_value += 4 * foe_side.effects[PBEffects::Spikes]
    hazard_value += 4 * foe_side.effects[PBEffects::ToxicSpikes]
    hazard_value += 5 if foe_side.effects[PBEffects::StickyWeb]

    if hazard_value > 0
      score += hazard_value
      PBDebug.log_score_change(hazard_value, "Yawn + hazard synergy.")
    end

    # Prefer against setup mons — forces them to switch or sleep
    target_boosts = 0
    GameData::Stat.each_battle do |s|
      target_boosts += target.stages[s.id] if target.stages[s.id] > 0
    end
    if target_boosts >= 2
      score += 10
      PBDebug.log_score_change(10, "Yawn vs boosted foe (+#{target_boosts}).")
    end

    # Don't prefer if target can heal
    score += AIEffectScoreHelper.get_target_heal_penalty(target, ai)

    next score
  }
)

#===============================================================================
# [NEW] Haze / Clear Smog / Spectral Thief — Counter foe stat boosts
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("ResetTargetStatStages",
  proc { |score, move, user, target, ai, battle|
    target_boosts = 0
    target_drops = 0
    GameData::Stat.each_battle do |s|
      target_boosts += target.stages[s.id] if target.stages[s.id] > 0
      target_drops += target.stages[s.id].abs if target.stages[s.id] < 0
    end

    if target_boosts >= 2
      bonus = 8 + (target_boosts * 5)
      score += bonus
      PBDebug.log_score_change(bonus, "Clear Smog vs boosted foe (+#{target_boosts}).")
    end

    # Penalize if target has more drops than boosts (we'd be helping them)
    if target_drops > target_boosts
      score -= 10
      PBDebug.log_score_change(-10, "Clear Smog would reset target's negative stages.")
    end

    next score
  }
)

Battle::AI::Handlers::MoveEffectScore.add("ResetAllBattlersStatStages",
  proc { |score, move, user, ai, battle|
    net_value = 0

    ai.each_foe_battler(user.side) do |b, i|
      GameData::Stat.each_battle do |s|
        net_value += b.stages[s.id] if b.stages[s.id] > 0  # Foe boosts: good to reset
      end
    end

    # Subtract user's own boosts (bad to reset)
    user_boosts = 0
    GameData::Stat.each_battle do |s|
      user_boosts += user.stages[s.id] if user.stages[s.id] > 0
    end
    net_value -= user_boosts

    if net_value >= 2
      bonus = 5 + (net_value * 4)
      score += bonus
      PBDebug.log_score_change(bonus, "Haze: foe has +#{net_value} net boosts to clear.")
    elsif net_value < 0
      penalty = net_value * 5
      score += penalty
      PBDebug.log_score_change(penalty, "Haze would erase user's own boosts.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Encore — score based on target's last used move
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("DisableTargetUsingDifferentMove",
  proc { |score, move, user, target, ai, battle|
    # Already encored
    next Battle::AI::MOVE_USELESS_SCORE if target.effects[PBEffects::Encore] > 0

    # Mental Herb cures Encore immediately
    next Battle::AI::MOVE_USELESS_SCORE if target.has_active_item?(:MENTALHERB)

    # Target hasn't moved yet — Encore will fail
    last_move_id = target.battler.lastMoveUsed
    next Battle::AI::MOVE_USELESS_SCORE unless last_move_id

    last_move_data = GameData::Move.try_get(last_move_id)
    next score unless last_move_data

    last_move_category = last_move_data.category   # 0=Physical, 1=Special, 2=Status
    last_move_power    = last_move_data.power
    last_move_type     = last_move_data.type

    # Locking target into a status/setup move is very valuable
    if last_move_category == 2
      score += 20
      PBDebug.log_score_change(20, "Encore: target's last move was a status move.")
    else
      # Check STAB
      is_stab = target.has_type?(last_move_type)

      if !is_stab && last_move_power <= 60
        # Weak non-STAB attack — worth locking
        score += 15
        PBDebug.log_score_change(15, "Encore: target's last move is a weak non-STAB attack.")
      elsif is_stab && last_move_power >= 80
        # Strong STAB attack — don't lock target into this
        score -= 10
        PBDebug.log_score_change(-10, "Encore: target's last move is a strong STAB attack.")
      end
    end

    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("UserStealTargetPositiveStatStages",
  proc { |score, move, user, target, ai, battle|
    target_boosts = 0
    GameData::Stat.each_battle do |s|
      target_boosts += target.stages[s.id] if target.stages[s.id] > 0
    end

    if target_boosts >= 2
      bonus = 10 + (target_boosts * 5)
      score += bonus
      PBDebug.log_score_change(bonus, "Spectral Thief vs boosted foe (+#{target_boosts}).")
    end

    next score
  }
)
