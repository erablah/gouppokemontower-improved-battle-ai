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
    next score if user.wild?

    # --- Foe threat data (shared by damaging and status paths) ---
    summary   = ai.matchup_summary
    foe_entry = summary[:foes][target.index]
    next score unless foe_entry

    # Status move survival/fail checks are handled globally in GeneralMoveScore.
    if !move.damagingMove?
      next score
    end

    # --- Damaging moves below ---
    pivot_codes = ["SwitchOutUserDamagingMove", "LowerTargetAtkSpAtk1SwitchOutUser"]
    is_pivot = pivot_codes.include?(ai.safe_function_code(move)) &&
               battle.pbCanChooseNonActive?(user.battler.index)

    user_dmg = ai.damage_entry_for_move(user, target, move)&.dig(:dmg) || 0

    # A) Base damage scaling: 0 to +20 based on damage relative to effective HP
    base = ([20.0 * user_dmg / target.hp, 20].min).to_i
    score += base
    PBDebug.log_score_change(base, "1v1: base damage (#{user_dmg}/#{target.hp})")

    # --- 1v1 simulation from matchup_summary cache ---
    result = foe_entry[:move_results_by_id]&.dig(move.id) ||
             foe_entry[:move_results]&.dig(move.id)
    next score unless result
    interrupted_by_live_switch = result.terminated_by_switch &&
                                 result.switch_type == :live_switch
    foe_pivoted_out = result.terminated_by_switch &&
                      result.switch_type == :live_switch &&
                      result.switch_battler_index == target.index &&
                      !result.user_fainted

    # The per-move simulation already knows whether the foe KOs before the
    # user gets a turn, so prefer that over a separate speed/priority shortcut.
    if result.target_can_ohko? && !interrupted_by_live_switch
      score -= 100
      PBDebug.log_score_change(-100, "1v1: foe KOs before user acts")
    end

    next score if is_pivot  # pivot moves: base damage + survival check only

    # B) User loses the 1v1 — early return with penalty, score boosts for damage are already applied
    unless result.user_wins? || foe_pivoted_out
      score -= 50
      PBDebug.log_score_change(-50, "1v1: user loses matchup")
      next score
    end

    next score if foe_pivoted_out

    u_turns = result.target_ko_turn || 999

    # C) Weak move penalty based on turns to KO
    if !result.user_can_ohko? && u_turns >= 5
      score -= 40
      PBDebug.log_score_change(-40, "1v1: move very weak (#{u_turns}+ turns to KO)")
    elsif !result.user_can_ohko? && u_turns >= 4
      score -= 30
      PBDebug.log_score_change(-30, "1v1: move weak (#{u_turns} turns to KO)")
    elsif !result.user_can_ohko? && u_turns >= 3
      score -= 15
      PBDebug.log_score_change(-15, "1v1: move mediocre (#{u_turns} turns to KO)")
    end

    # D) Positive sim bonus
    if result.user_can_ohko? && !interrupted_by_live_switch
      bonus = result.target_got_action ? 15 : 30
      score += bonus
      PBDebug.log_score_change(bonus, "1v1: can OHKO target#{result.target_got_action ? '' : ' (before target acts)'}")
    else
      bonus = (20.0 / u_turns).to_i.clamp(5, 15)
      score += bonus
      PBDebug.log_score_change(bonus, "1v1: user wins in #{u_turns} turns")
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

    is_pivot = Battle::AI::SLOW_PIVOT_FUNCTION_CODES.include?(ai.safe_function_code(move))
    next score unless is_pivot

    score += 5

    # Prefer if target is slower than a foe
    if !user.faster_than?(target)
      score += 5
      PBDebug.log_score_change(5, "6. Slow Pivot preference.")
    end

    score += 5 if user.has_active_ability?(:REGENERATOR) && user.hp <= user.totalhp * 0.75
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
    next score unless target.item && target.item_active?
    next score if target.battler.unlosableItem?(target.item)
    next score if target.effects[PBEffects::Substitute] > 0
    next score if target.has_active_ability?(:STICKYHOLD)

    # Base bonus for item removal
    score += 5
    PBDebug.log_score_change(5, "Knock Off: removing target's item.")

    # Extra bonus for high-value items
    high_value_items = [
      :LEFTOVERS, :EVIOLITE, :LIFEORB, :ASSAULTVEST, :ROCKYHELMET,
    ]
    if target.has_active_item?(high_value_items)
      score += 10
      PBDebug.log_score_change(10, "Knock Off: target has high-value item.")
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

    score += 5
    PBDebug.log_score_change(5, "Priority move bonus: user is slower than target.")
    next score
  }
)


#===============================================================================
# override ability and item triggers because its already done in simulations(and is not fun for game player)
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:trigger_target_ability_or_item_upon_hit,
  proc { |score, move, user, target, ai, battle|
    next score
  }
)
