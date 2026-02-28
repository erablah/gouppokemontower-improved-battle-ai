#===============================================================================
# 2. GeneralMoveAgainstTargetScore Handlers
#===============================================================================

#===============================================================================
# override predicted_damage more score for predicted KO move
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:predicted_damage,
  proc { |score, move, user, target, ai, battle|
    if move.damagingMove?
      dmg = ai.damage_moves(user, target)[move.id]&.dig(:dmg) ||
            move.predicted_damage(user: user, target: target)
      old_score = score
      if target.effects[PBEffects::Substitute] > 0
        score += ([15.0 * dmg / target.effects[PBEffects::Substitute], 20].min).to_i
        PBDebug.log_score_change(score - old_score, "damaging move (predicted damage #{dmg} = #{100 * dmg / target.hp}% of target's Substitute)")
      else
        score += ([25.0 * dmg / target.hp, 30].min).to_i
        PBDebug.log_score_change(score - old_score, "damaging move (predicted damage #{dmg} = #{100 * dmg / target.hp}% of target's HP)")
        if ai.trainer.has_skill_flag?("HPAware") && dmg >= target.hp * 0.9   # Predicted to KO the target
          old_score = score
          score += 50
          PBDebug.log_score_change(score - old_score, "predicted to KO the target")
          if move.move.multiHitMove? && target.hp == target.totalhp &&
             (target.has_active_ability?(:STURDY) || target.has_active_item?(:FOCUSSASH))
            old_score = score
            score += 8
            PBDebug.log_score_change(score - old_score, "predicted to overcome the target's Sturdy/Focus Sash")
          end
        end
      end
    end
    next score
  }
)

#===============================================================================
# 6. Active pivot move boost (U-turn, Volt Switch, etc.)
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:boost_pivot_moves,
  proc { |score, move, user, target, ai, battle|
    next score if !ai.trainer.high_skill?
    next score if !battle.pbCanChooseNonActive?(user.battler.index)

    is_pivot = [
      "SwitchOutUserDamagingMove"
    ].include?(ai.safe_function_code(move))
    next score unless is_pivot

    score += 10

    # Prefer if target is slower than a foe
    if !user.faster_than?(target)
      score += 5
      PBDebug.log_score_change(5, "6. Slow Pivot preference.")
    end

    PBDebug.log_score_change(10, "6. Active Pivot move boost.")
    next score
  }
)

#===============================================================================
# 16. Penalize single-stage stat drop moves
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:nerf_weak_debuffs,
  proc { |score, move, user, target, ai, battle|
    if move.statusMove? &&
       ai.safe_function_code(move)&.include?("LowerTarget") &&
       ai.safe_function_code(move)&.end_with?("1")
      score -= 20
    end
    next score
  }
)

#-------------------------------------------------------------------------------
# [NEW] Penalize useless moves (low damage)
#-------------------------------------------------------------------------------
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:penalize_useless_moves,
  proc { |score, move, user, target, ai, battle|
    if move.damagingMove?
      # Skip penalty for damaging pivot moves (U-turn, Volt Switch, etc.)
      pivot_codes = ["SwitchOutUserDamagingMove", "LowerTargetAtkSpAtk1SwitchOutUser"]
      next score if pivot_codes.include?(ai.safe_function_code(move))

      dmg     = ai.damage_moves(user, target)[move.id]&.dig(:dmg) ||
                move.predicted_damage(user: user, target: target)
      pct_dmg = dmg.to_f / target.totalhp.to_f
      will_ko = dmg.to_f >= target.hp.to_f
      next score if will_ko

      if pct_dmg < 0.20
        score -= 50
        PBDebug.log_score_change(-50, "Penalize useless move: very low predicted damage (#{(pct_dmg * 100).round(1)}%).")
      elsif pct_dmg < 0.40
        score -= 20
        PBDebug.log_score_change(-20, "Penalize weak move: consider switching (#{(pct_dmg * 100).round(1)}%).")
      end
    end
    next score
  }
)

#===============================================================================
# [NEW] Forced switch + hazard synergy
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:phaze_with_hazards,
  proc { |score, move, user, target, ai, battle|
    next score unless ai.trainer.high_skill?
    phaze_codes = [
      "SwitchOutTargetStatusMove",
      "SwitchOutTargetDamagingMove"
    ]
    next score unless phaze_codes.include?(ai.safe_function_code(move))

    foe_side = target.pbOwnSide
    hazard_value = 0
    hazard_value += 10 if foe_side.effects[PBEffects::StealthRock]
    hazard_value += 5 * foe_side.effects[PBEffects::Spikes]
    hazard_value += 5 * foe_side.effects[PBEffects::ToxicSpikes]
    hazard_value += 8 if foe_side.effects[PBEffects::StickyWeb]

    if hazard_value > 0
      score += hazard_value
      PBDebug.log_score_change(hazard_value, "Phaze synergy with hazards.")
    end

    # Boost if target has set up
    target_boosts = 0
    GameData::Stat.each_battle do |s|
      stage = target.stages[s.id]
      target_boosts += stage if stage > 0
    end
    if target_boosts >= 2
      score += 15
      PBDebug.log_score_change(15, "Phaze to reset target's +#{target_boosts} boosts.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Knock Off — bonus for removing target's item
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:boost_knock_off,
  proc { |score, move, user, target, ai, battle|
    next score unless ai.safe_function_code(move) == "RemoveTargetItem"
    next score unless target.item_active?
    next score if target.has_active_ability?(:STICKYHOLD)

    # Base bonus for item removal
    score += 10
    PBDebug.log_score_change(10, "Knock Off: removing target's item.")

    # Extra bonus for high-value items
    high_value_items = [
      :LEFTOVERS, :EVIOLITE, :LIFEORB, :ASSAULTVEST, :ROCKYHELMET,
    ]
    if target.has_active_item?(high_value_items)
      score += 5
      PBDebug.log_score_change(5, "Knock Off: target has high-value item.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Priority move bonus when user is slower
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:boost_priority_when_slower,
  proc { |score, move, user, target, ai, battle|
    next score unless move.damagingMove?
    next score unless move.move.priority > 0
    next score if user.faster_than?(target)

    # FailsIfTargetActed moves (e.g. Sucker Punch) only go first if the foe
    # actually uses an attacking move — skip the bonus 50% of the time since
    # it's not guaranteed to beat the foe's speed.
    if move.move.is_a?(Battle::Move::FailsIfTargetActed) && ai.pbAIRandom(100) < 50
      PBDebug.log_ai("[boost_priority] skip FailsIfTargetActed priority bonus (uncertain)")
      next score
    end

    score += 8
    PBDebug.log_score_change(8, "Priority move bonus: user is slower than target.")
    next score
  }
)


