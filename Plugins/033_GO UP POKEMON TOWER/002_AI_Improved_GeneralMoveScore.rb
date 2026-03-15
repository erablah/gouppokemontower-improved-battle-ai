#===============================================================================
# 1. GeneralMoveScore Handlers
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:smart_setup_move_final,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score unless move.statusMove?
    next score unless ai.safe_function_code(move)&.start_with?("RaiseUser")

    battler = user.battler
    next score unless battler

    # -----------------------------------------------------------------------
    # A. Parse @statUp — determine which stats are raised and by how much
    # -----------------------------------------------------------------------
    real_move = move.move
    stat_up = (real_move.respond_to?(:statUp) && real_move.statUp) ? real_move.statUp : nil
    PBDebug.log_ai("[smart_setup] statUp: #{stat_up}")

    # -----------------------------------------------------------------------
    # B. Assume stat boosts are inherently risky (-40)
    # -----------------------------------------------------------------------
    score -= 40
    PBDebug.log_score_change(-40, "GLOBAL NERF: Setup moves are inherently risky.")

    # -----------------------------------------------------------------------
    # C. Free setup cancel: when foes can't threaten the user
    #    → cancel the -50 penalty (+50)
    # -----------------------------------------------------------------------

    summary = ai.matchup_summary
    foe_can_ohko = summary[:foe_can_ohko]
    foe_threatens = summary[:foes].values.any? { |f| f[:best_dmg].to_f / battler.hp.to_f > 0.4 }
    foe_threatens = true if foe_can_ohko
    if foe_can_ohko
      score -= 200
      PBDebug.log_score_change(-200, "Setup blocked: foe can OHKO.")
      next score
    end
    unless foe_threatens
      score += 50
      PBDebug.log_score_change(50, "Free setup: foes can't threaten (>40%).")
    end

    # -----------------------------------------------------------------------
    # D. Block setup if no move can deal >40% to any foe
    # -----------------------------------------------------------------------
    has_good_damage = summary[:foes].values.any? { |f| f[:user_best_dmg].to_f / f[:foe_hp].to_f > 0.3 }
    if !has_good_damage
      score -= 50
      PBDebug.log_score_change(-50, "Setup blocked: No damaging move can do >30% of target HP.")
    end

    # -----------------------------------------------------------------------
    # E. Offensive stat boost cap: block further setup if any offensive stat is +3 or higher
    # -----------------------------------------------------------------------
    OFFENSIVE_STATS = [:ATTACK, :SPECIAL_ATTACK, :SPEED]
    max_offensive_boost = 0
    OFFENSIVE_STATS.each do |s|
      stage = battler.stages[s]
      max_offensive_boost = [max_offensive_boost, stage].max if stage > 0
    end
    # if max_offensive_boost >= 3
    #   score -= 100
    #   PBDebug.log_score_change(-100, "Setup blocked: an offensive stat is already at +#{max_offensive_boost}.")
    #   next score
    # end

    # -----------------------------------------------------------------------
    # F. Stat relevance check (only when statUp data is available)
    # -----------------------------------------------------------------------
    if stat_up
      raises_spd = false
      (stat_up.length / 2).times do |i|
        stat_id = stat_up[i * 2]
        case stat_id
        when :SPEED          then raises_spd = true
        end
      end

      # Speed breakpoint check
      if raises_spd
        user_speed = user.rough_stat(:SPEED)
        max_foe_speed = 0
        ai.each_foe_battler(user.side) do |b, _i|
          max_foe_speed = [max_foe_speed, b.rough_stat(:SPEED)].max
        end
        spd_stages = 0
        (stat_up.length / 2).times do |i|
          spd_stages = stat_up[i * 2 + 1] if stat_up[i * 2] == :SPEED
        end
        # Approximate boosted speed calculation (stage +1 = x1.5, +2 = x2.0, ...)
        current_spd_stage = battler.stages[:SPEED]
        new_stage = [current_spd_stage + spd_stages, 6].min
        spd_mult = (2.0 + new_stage) / 2.0
        current_mult = (2.0 + current_spd_stage) / 2.0
        current_mult = 0.25 if current_mult <= 0  # safeguard against division by zero
        base_speed = user_speed / current_mult  # un-boost
        boosted_speed = base_speed * spd_mult

        if user_speed < max_foe_speed && boosted_speed >= max_foe_speed
          score += 20
          PBDebug.log_score_change(20, "Speed breakpoint: boost would outspeed foe (#{boosted_speed.to_i} >= #{max_foe_speed}).")
        elsif user_speed >= max_foe_speed
          score += 5
          PBDebug.log_score_change(5, "Speed boost: already faster, slight bonus.")
        end
      end
    end

    # -----------------------------------------------------------------------
    # G. Final bonus based on stat relevance
    #    - Attack/Sp.Atk: +20 per effective stage, but only if the user
    #      has damaging moves in that category
    #    - Defensive stats (Def/Sp.Def): +10 per effective stage
    # -----------------------------------------------------------------------
    if stat_up
      has_physical = battler.moves.compact.any? { |m| m.physicalMove? }
      has_special  = battler.moves.compact.any? { |m| m.specialMove? }

      bonus = 0
      detail_parts = []
      (stat_up.length / 2).times do |i|
        stat_id = stat_up[i * 2]
        stages  = stat_up[i * 2 + 1]
        room    = 6 - battler.stages[stat_id]
        effective = [[stages, room].min, 0].max
        next if effective == 0

        case stat_id
        when :ATTACK
          if has_physical
            bonus += 10 * effective
            detail_parts << "Atk +#{effective}"
          end
        when :SPECIAL_ATTACK
          if has_special
            bonus += 10 * effective
            detail_parts << "SpA +#{effective}"
          end
        when :DEFENSE, :SPECIAL_DEFENSE
          bonus += 5 * effective
          detail_parts << "#{stat_id == :DEFENSE ? "Def" : "SpD"} +#{effective}"
        end
      end
    end

    bonus ||= 0
    score += bonus
    PBDebug.log_score_change(bonus, "Setup bonus: #{detail_parts ? detail_parts.join(", ") : "flat (no statUp data)"}.")

    next score
  }
)

#===============================================================================
# 2. Stat boost synergy with Stored Power, etc.
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:boost_setup_synergy,
  proc { |score, move, user, ai, battle|
    next score if !move.statusMove?

    # user is AIBattler; battler is the actual Battle::Battler
    has_stored_power = user.check_for_move do |m|
      ["PowerHigherWithUserPositiveStatStages",
       "PowerIncreasedByTargetStatChanges"].include?(ai.safe_function_code(m))
    end

    if has_stored_power && ai.safe_function_code(move)&.start_with?("RaiseUser")
      score += 80
      PBDebug.log_score_change(80, "2. Setup synergy with Stored Power.")
    end
    next score
  }
)

#===============================================================================
# 9. Prevent redundant hazard/screen setup and spike stacking penalty
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:prevent_redundant_effects,
  proc { |score, move, user, ai, battle|
    penalty = 0
    case ai.safe_function_code(move)
    when "AddStealthRocksToFoeSide"
      penalty = -200 if user.pbOpposingSide.effects[PBEffects::StealthRock]
    when "AddSpikesToFoeSide"
      existing = user.pbOpposingSide.effects[PBEffects::Spikes]
      if existing >= 3
        penalty = -200
      elsif existing >= 1
        # Stacking penalty: -30 for 2nd layer, -60 for 3rd layer attempt
        penalty = -(30 + (existing - 1) * 30)
      end
    when "AddToxicSpikesToFoeSide"
      existing = user.pbOpposingSide.effects[PBEffects::ToxicSpikes]
      if existing >= 2
        penalty = -200
      elsif existing >= 1
        penalty = -40  # 2nd layer of Toxic Spikes is significantly less useful
      end
    when "AddStickyWebToFoeSide"
      penalty = -200 if user.pbOpposingSide.effects[PBEffects::StickyWeb]
    when "UserSideDamageReduction" # Reflect, Light Screen, Aurora Veil
      is_reflect     = (move.id == :REFLECT)
      is_lightscreen = (move.id == :LIGHTSCREEN)
      is_aurora      = (move.id == :AURORAVEIL)

      own_side = user.pbOwnSide
      penalty = -200 if is_reflect     && own_side.effects[PBEffects::Reflect] > 0
      penalty = -200 if is_lightscreen && own_side.effects[PBEffects::LightScreen] > 0
      penalty = -200 if is_aurora      && own_side.effects[PBEffects::AuroraVeil] > 0
    end

    if penalty != 0
      score += penalty
      PBDebug.log_score_change(penalty, "9. Hazard stack penalty / redundant setup prevention.")
    end
    next score
  }
)

#===============================================================================
# 10. Penalize hazard setup when foe is boosted
# A boosted foe is an immediate threat — spending a turn on hazards wastes tempo.
#===============================================================================
HAZARD_FUNCTION_CODES = [
  "AddStealthRocksToFoeSide", "AddSpikesToFoeSide",
  "AddToxicSpikesToFoeSide", "AddStickyWebToFoeSide"
].freeze

Battle::AI::Handlers::GeneralMoveScore.add(:penalize_hazards_vs_boosted_foe,
  proc { |score, move, user, ai, battle|
    next score unless HAZARD_FUNCTION_CODES.include?(ai.safe_function_code(move))

    foe_boosts = 0
    ai.each_foe_battler(user.side) do |b, _i|
      GameData::Stat.each_battle do |s|
        stage = b.stages[s.id]
        foe_boosts += stage if stage > 0
      end
    end

    if foe_boosts >= 2
      penalty = 10 + (foe_boosts * 10)
      score -= penalty
      PBDebug.log_score_change(-penalty, "10. Hazard vs boosted foe (+#{foe_boosts} total boosts).")
    end
    next score
  }
)

#===============================================================================
# 15. General status move base score boost
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:boost_general_status_moves,
  proc { |score, move, user, ai, battle|
    next score if !ai.trainer.high_skill?

    if move.statusMove? &&
       !ai.safe_function_code(move)&.start_with?("ProtectUserEvenFromDynamaxMoves")
      score += 5
      PBDebug.log_score_change(5, "5. General Status Move Boost.")
    end
    next score
  }
)


#===============================================================================
# [NEW] Tactical Substitute usage AI
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:tactical_substitute,
  proc { |score, move, user, ai, battle|
    # Skip if not Substitute
    next score unless move.id == :SUBSTITUTE

    battler = user.battler
    next score unless battler

    # Don't use if Substitute is already active
    next Battle::AI::MOVE_USELESS_SCORE if battler.effects[PBEffects::Substitute] > 0

    # Don't use if HP is insufficient (need at least ~60%)
    hp_ratio = battler.hp.to_f / battler.totalhp
    next Battle::AI::MOVE_USELESS_SCORE if hp_ratio < 0.60

    # -------------------------------------------------------------------------
    # B. Foe threat analysis — reject if any foe can deal >25% in one hit
    # -------------------------------------------------------------------------
    summary = ai.matchup_summary
    threatened = summary[:foes].values.any? { |f| f[:best_dmg] > battler.totalhp * 0.3 }

    # Substitute is counterproductive when foe can break it in one hit
    next Battle::AI::MOVE_USELESS_SCORE if threatened

    # -------------------------------------------------------------------------
    # C. Evaluate plans behind Substitute
    # -------------------------------------------------------------------------

    future_value = 0

    # 1) Substitute value increases if user has setup moves
    if user.check_for_move { |m| ai.safe_function_code(m)&.start_with?("RaiseUser") }
      future_value += 20
    end

    # 2) Value increases if foe has status moves (Substitute blocks them)
    foe_has_status = false
    ai.each_foe_battler(user.side) do |b, _i|
      ai.known_foe_moves(b).each do |m|
        foe_has_status = true if m.statusMove?
      end
      break if foe_has_status
    end
    future_value += 15 if foe_has_status

    score += future_value
    PBDebug.log_score_change(
      future_value,
      "Tactical Substitute (HP=#{(hp_ratio * 100).to_i}%)."
    )

    next score
  }
)


Battle::AI::Handlers::GeneralMoveScore.add(:evade_knockout,
  proc { |score, move, user, ai, battle|
    # Skip if user has an active Substitute
    next score if user.effects[PBEffects::Substitute] > 0

    max_foe_speed   = 0
    foe_can_ko      = false
    priority_ko     = false
    priority_ko_move = nil   # save the threatening priority move for later

    ai.each_foe_battler(user.side) do |b, _i|
      next unless b.can_attack?
      max_foe_speed = [max_foe_speed, b.rough_stat(:SPEED)].max
      relevant = ai.damage_moves(b, user).values.reject { |md| move.move.priority > md[:move].priority }
      ko_moves = relevant.select { |md| md[:dmg] >= user.hp * 1.05 }
      ko_moves.each do |ko_entry|
        PBDebug.log_ai("[evade_ko] #{b.name} #{ko_entry[:move].name}: #{ko_entry[:dmg]} >= #{user.hp}")
        foe_can_ko = true
        if ko_entry[:move].priority > move.move.priority
          priority_ko      = true
          priority_ko_move = ko_entry[:move]
          PBDebug.log_ai("[evade_ko] #{b.name} has priority KO move: #{ko_entry[:move].name} (pri #{ko_entry[:move].priority} > #{move.move.priority})")
        end
      end
    end

    user_speed = [user.rough_stat(:SPEED), 1].max

    # Priority KO moves bypass speed — always penalize
    if priority_ko
      # implement chance for sucker punch
      if priority_ko_move&.is_a?(Battle::Move::FailsIfTargetActed) && ai.pbAIRandom(100) < 25
        PBDebug.log_ai("[evade_ko] skip sucker punch penalty (25% chance it will fail)")
        next score
      end
      score -= 200
      PBDebug.log_score_change(-200, "Penalize move: foe can KO with a higher-priority move.")
    elsif user_speed < max_foe_speed && foe_can_ko
      speed_ratio = max_foe_speed.to_f / user_speed.to_f
      chance = ((speed_ratio - 1.0) / 0.2 * 100).to_i.clamp(0, 100)
      PBDebug.log_ai("evade KO penalty chance is #{chance}%")

      if ai.pbAIRandom(100) < chance
        score -= 200
        PBDebug.log_score_change(-200, "Penalize move: user is slower than a foe who can KO. (Speed ratio: #{speed_ratio.round(2)}, Chance: #{chance}%)")
      end
    end

    next score
  }
)


#===============================================================================
# [NEW] Setup boost: when all foes are unable to act
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:boost_setup_when_foe_helpless,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score unless move.statusMove?
    next score unless ai.safe_function_code(move)&.start_with?("RaiseUser")

    any_foe_can_act = false
    ai.each_foe_battler(user.side) do |b, i|
      if b.can_attack?
        any_foe_can_act = true
        break
      end
    end

    unless any_foe_can_act
      score += 10
      PBDebug.log_score_change(10, "Setup boost: no foe can attack this turn.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Smart recovery usage (Recover, Roost, etc.)
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:smart_recovery,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    healing_codes = [
      "HealUserHalfOfTotalHP",
      "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn",
      "HealUserDependingOnWeather",
      "HealUserAndAlliesQuarterOfTotalHP"
    ]
    next score unless healing_codes.include?(ai.safe_function_code(move))

    battler = user.battler
    next score unless battler
    hp_ratio = battler.hp.to_f / battler.totalhp

    # Check if foe can 2HKO — recovery is futile
    summary = ai.matchup_summary
    max_foe_dmg = summary[:max_foe_dmg]
    PBDebug.log_ai("[smart_recovery] max foe dmg = #{max_foe_dmg} (#{(100.0 * max_foe_dmg / [1, battler.totalhp].max).round(1)}% totalhp, threshold 55%)")

    if max_foe_dmg >= battler.totalhp * 0.55
      score -= 60
      PBDebug.log_score_change(-60, "Recovery futile: foe can 2HKO (#{(100 * max_foe_dmg / battler.totalhp).to_i}% per hit).")
      next score
    end

    # Good recovery range: 40~60% HP
    if hp_ratio <= 0.60 && hp_ratio >= 0.40
      bonus = (15 + (20 * (0.60 - hp_ratio) / 0.20)).to_i  # 15~35
      score += bonus
      PBDebug.log_score_change(bonus, "Smart recovery at #{(hp_ratio * 100).to_i}% HP.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Smart Protect/Detect stalling
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:smart_protect,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    protect_codes = [
      "ProtectUser",
      "ProtectUserBanefulBunker",
      "ProtectUserFromDamagingMovesKingsShield",
      "ProtectUserFromTargetingMovesSpikyShield"
    ]
    next score unless protect_codes.include?(ai.safe_function_code(move))

    battler = user.battler
    next score unless battler

    # Consecutive Protect will fail
    if battler.effects[PBEffects::ProtectRate] > 1
      score -= 100
      PBDebug.log_score_change(-100, "Protect likely to fail (consecutive).")
      next score
    end

    stall_value = 0

    # Residual damage on foe
    ai.each_foe_battler(user.side) do |b, i|
      stall_value += 10 if b.status == :POISON && b.statusCount > 0  # Toxic
      stall_value += 8  if b.status == :BURN
      stall_value += 5  if b.status == :POISON && b.statusCount == 0
    end

    # Speed Boost synergy
    stall_value += 12 if user.has_active_ability?(:SPEEDBOOST)

    # Leftovers/Black Sludge recovery
    stall_value += 5 if user.has_active_item?(:LEFTOVERS) || user.has_active_item?(:BLACKSLUDGE)

    # Wish incoming (Wish is a position effect, not a battler effect)
    position = battle.positions[battler.index]
    stall_value += 10 if position && position.effects[PBEffects::Wish] > 0

    if stall_value > 0
      score += stall_value
      PBDebug.log_score_change(stall_value, "Protect stall value.")
    else
      score -= 20
      PBDebug.log_score_change(-20, "Protect has no stall value.")
    end

    next score
  }
)

# #===============================================================================
# # [NEW] Early hazard setup priority (per-hazard tuning)
# #===============================================================================
# Battle::AI::Handlers::GeneralMoveScore.add(:prioritize_early_hazards,
#   proc { |score, move, user, ai, battle|
#     next score unless ai.trainer.high_skill?

#     foe_reserves = battle.pbAbleNonActiveCount(user.idxOpposingSide)
#     next score unless foe_reserves >= 2

#     case ai.safe_function_code(move)
#     when "AddStealthRocksToFoeSide"
#       bonus = 3 + (foe_reserves * 3)   # +7 to +13
#       bonus += 5 if user.turnCount < 2
#       score += bonus
#       PBDebug.log_score_change(bonus, "Hazard priority (SR): #{foe_reserves} foe reserves.")
#     when "AddSpikesToFoeSide"
#       # No early-game boost once any layer is already set
#       next score if user.pbOpposingSide.effects[PBEffects::Spikes] >= 1
#       bonus = 3 + (foe_reserves * 2)   
#       bonus += 3 if user.turnCount < 2
#       score += bonus
#       PBDebug.log_score_change(bonus, "Hazard priority (Spikes): #{foe_reserves} foe reserves.")
#     when "AddToxicSpikesToFoeSide"
#       # No early-game boost once any layer is already set
#       next score if user.pbOpposingSide.effects[PBEffects::ToxicSpikes] >= 1
#       bonus = 3 + (foe_reserves * 3)  
#       bonus += 3 if user.turnCount < 2
#       score += bonus
#       PBDebug.log_score_change(bonus, "Hazard priority (TSpikes): #{foe_reserves} foe reserves.")
#     when "AddStickyWebToFoeSide"
#       bonus = 3 + (foe_reserves * 3)  
#       bonus += 3 if user.turnCount < 2
#       score += bonus
#       PBDebug.log_score_change(bonus, "Hazard priority (Web): #{foe_reserves} foe reserves.")
#     end

#     next score
#   }
# )

#===============================================================================
# [NEW] Smart Wish usage
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:smart_wish,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score unless ai.safe_function_code(move) == "HealUserPositionNextTurn"

    battler = user.battler
    next score unless battler

    # Block if Wish is already active on this position
    position = battle.positions[battler.index]
    if position && position.effects[PBEffects::Wish] > 0
      next Battle::AI::MOVE_USELESS_SCORE
    end

    hp_ratio = battler.hp.to_f / battler.totalhp

    # Bonus based on HP ratio
    if hp_ratio < 0.50
      score += 25
      PBDebug.log_score_change(25, "Wish: HP < 50% (#{(hp_ratio * 100).to_i}%).")
    elsif hp_ratio < 0.80
      score += 15
      PBDebug.log_score_change(15, "Wish: HP 50-80% (#{(hp_ratio * 100).to_i}%).")
    end

    # Wish + pivot synergy
    if user.check_for_move { |m| ai.safe_function_code(m)&.start_with?("SwitchOutUser") }
      score += 10
      PBDebug.log_score_change(10, "Wish: pivot move synergy.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Smart Rest usage
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:smart_rest,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score unless ai.safe_function_code(move) == "HealUserFullAndSleep"

    battler = user.battler
    next score unless battler

    hp_ratio = battler.hp.to_f / battler.totalhp

    # Not worth using above 70% HP
    next Battle::AI::MOVE_USELESS_SCORE if hp_ratio > 0.60

    # Already asleep
    next Battle::AI::MOVE_USELESS_SCORE if battler.status == :SLEEP

    # Big bonus if user has Sleep Talk
    if user.check_for_move { |m| m.usableWhenAsleep? }
      score += 30
      PBDebug.log_score_change(30, "Rest: has Sleep Talk combo.")
    end

    # Chesto/Lum Berry allows instant wake
    if user.has_active_item?([:CHESTOBERRY, :LUMBERRY])
      score += 20
      PBDebug.log_score_change(20, "Rest: has Chesto/Lum Berry for instant wake.")
    end

    # Early Bird shortens sleep duration
    if user.has_active_ability?(:EARLYBIRD)
      score += 15
      PBDebug.log_score_change(15, "Rest: Early Bird shortens sleep.")
    end

    # Penalize if foe can set up while user sleeps
    foe_has_setup = false
    ai.each_foe_battler(user.side) do |b, _i|
      ai.known_foe_moves(b).each do |m|
        if ai.safe_function_code(m)&.start_with?("RaiseUser")
          foe_has_setup = true
          break
        end
      end
      break if foe_has_setup
    end
    if foe_has_setup
      score -= 40
      PBDebug.log_score_change(-40, "Rest: foe has setup potential while user sleeps.")
    end

    next score
  }
)

