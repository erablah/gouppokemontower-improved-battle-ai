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