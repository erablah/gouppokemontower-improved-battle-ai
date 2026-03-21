#===============================================================================
# 2. GeneralMoveAgainstTargetScore Handlers
#===============================================================================

# overwrite existing :predicted_damage handler with a no-op since it's fully replaced by :one_v_one_move_score
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:predicted_damage,
  proc { |score, move, user, target, ai, battle|
    next score 
  }
)

#===============================================================================
# Unified 1v1 move scoring: damage scaling, OHKO bonus, weak-move penalty,
# and survival check (replaces :predicted_damage, :penalize_useless_moves,
# and :evade_knockout)
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:one_v_one_move_score,
  proc { |score, move, user, target, ai, battle|
    next score unless ai.trainer.has_skill_flag?("HPAware")

    # --- Foe threat data (shared by damaging and status paths) ---
    summary   = ai.matchup_summary
    foe_entry = summary[:foes][target.index]
    next score unless foe_entry

    foe_dmg      = foe_entry[:best_dmg]
    foe_best_pri = foe_entry[:best_priority]

    # Priority-aware speed: who acts first?
    if move.move.priority > foe_best_pri
      user_outspeeds = true
    elsif foe_best_pri > move.move.priority
      user_outspeeds = false
    else
      user_outspeeds = user.faster_than?(target)
    end

    # --- Universal survival check (all move types) ---
    # If foe can OHKO and acts first, any move is likely wasted
    if foe_dmg >= user.hp && !user_outspeeds && user.effects[PBEffects::Substitute] <= 0
      foe_move = foe_entry[:best_move]
      if foe_move&.is_a?(Battle::Move::FailsIfTargetActed) && ai.pbAIRandom(100) < 25
        PBDebug.log_ai("[1v1] skip Sucker Punch KO penalty (25% chance it fails)")
      else
        score -= 200
        PBDebug.log_score_change(-200, "1v1: foe can OHKO and outspeeds")
      end
    end

    # --- Status moves: survival check only, no damage scoring ---
    next score unless move.damagingMove?

    # --- Damaging moves below ---
    pivot_codes = ["SwitchOutUserDamagingMove", "LowerTargetAtkSpAtk1SwitchOutUser"]
    is_pivot = pivot_codes.include?(ai.safe_function_code(move)) &&
               battle.pbCanChooseNonActive?(user.battler.index)

    user_dmg = ai.damage_moves(user, target)[move.id]&.dig(:dmg) ||
               move.predicted_damage(user: user, target: target)

    # Substitute: use Sub HP for damage calculations (move hits Sub first)
    effective_hp = target.effects[PBEffects::Substitute] > 0 ? target.effects[PBEffects::Substitute] : target.hp

    # --- 1v1 result (use effective_hp so OHKO/win checks respect Substitute) ---
    result = ai.one_v_one_result(
      user_dmg: user_dmg, foe_dmg: foe_dmg,
      user_hp: user.hp, foe_hp: effective_hp,
      user_outspeeds: user_outspeeds
    )

    # A) Base damage scaling: 0 to +30 based on damage relative to effective HP
    base = ([30.0 * user_dmg / effective_hp, 30].min).to_i
    score += base
    PBDebug.log_score_change(base, "1v1: base damage (#{user_dmg}/#{effective_hp})")

    next score if is_pivot  # pivot moves: base damage + survival check only

    # B) Weak move penalty (applied regardless of win/loss — encourage switching or setup)
    pct = user_dmg.to_f / target.totalhp
    if !result[:user_can_ohko] && pct < 0.20
      score -= 40
      PBDebug.log_score_change(-40, "1v1: move very weak (#{(pct * 100).round(1)}%)")
    elsif !result[:user_can_ohko] && pct < 0.40
      penalty = (40 * [(0.40 - pct) / 0.20, 1.0].min).round
      score -= penalty
      PBDebug.log_score_change(-penalty, "1v1: move weak (#{(pct * 100).round(1)}%)")
    end

    # C) OHKO bonus (only if user actually wins — foe OHKO + faster means user dies first)
    if result[:user_can_ohko] && result[:user_wins]
      bonus = user_outspeeds ? 30 : 15
      score += bonus
      PBDebug.log_score_change(bonus, "1v1: can OHKO target#{user_outspeeds ? ' (outspeeds)' : ''}")

    # D) User wins in multiple turns (capped so it never fully overrides weak-move penalty)
    elsif result[:user_wins]
      bonus = (20.0 / result[:u_turns]).to_i.clamp(5, 15)  # 2HKO->10, 3HKO->6, 4HKO->5...
      score += bonus
      PBDebug.log_score_change(bonus, "1v1: user wins in #{result[:u_turns]} turns")
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

    score += 5

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
# [NEW] reset enemy boosts
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:phaze_with_hazards,
  proc { |score, move, user, target, ai, battle|
    next score unless ai.trainer.high_skill?
    phaze_codes = [
      "SwitchOutTargetStatusMove",
      "SwitchOutTargetDamagingMove"
    ]
    next score unless phaze_codes.include?(ai.safe_function_code(move))

    # Boost if target has set up
    target_boosts = 0
    GameData::Stat.each_battle do |s|
      stage = target.stages[s.id]
      target_boosts += stage if stage > 0
    end
    if target_boosts >= 1
      score +=30
      PBDebug.log_score_change(30, "Phaze to reset target's +#{target_boosts} boosts.")
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
    score += 5
    PBDebug.log_score_change(10, "Knock Off: removing target's item.")

    # Extra bonus for high-value items
    high_value_items = [
      :LEFTOVERS, :EVIOLITE, :LIFEORB, :ASSAULTVEST, :ROCKYHELMET,
    ]
    if target.has_active_item?(high_value_items)
      score += 10
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


