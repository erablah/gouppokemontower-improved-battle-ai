#===============================================================================
# 0. Override: Choice Item scoring — exempt Trick/Switcheroo entirely
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:good_move_for_choice_item,
  proc { |score, move, user, ai, battle|
    next score if move.move.powerMove?
    next score if !ai.trainer.medium_skill?
    next score if !user.has_active_item?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF]) &&
                  !user.has_active_ability?(:GORILLATACTICS)
    # Trick/Switcheroo removes the Choice item — no penalty
    next score if move.function_code == "UserTargetSwapItems"
    old_score = score
    if move.statusMove?
      score -= 25
      PBDebug.log_score_change(score - old_score, "don't want to be Choiced into a status move")
      next score
    end
    move_type = move.rough_type
    GameData::Type.each do |type_data|
      score -= 8 if type_data.immunities.include?(move_type)
    end
    if move.accuracy > 0
      score -= (0.2 * (100 - move.accuracy)).to_i
    end
    PBDebug.log_score_change(score - old_score, "move is less suitable to be Choiced into")
    next score
  }
)

Battle::AI::Handlers::GeneralMoveScore.add(:smart_setup_move_final,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score if user.wild?

    real_move = move.move
    fc = ai.safe_function_code(move) || ""
    # Ghost Curse sacrifices HP to curse — not a setup move
    next score if fc == "CurseTargetOrLowerUserSpd1RaiseUserAtkDef1" && user.has_type?(:GHOST)
    stat_up = (real_move.respond_to?(:statUp) && real_move.statUp) ? real_move.statUp : nil
    stat_up_from_fc = false

    # Fallback: parse stat_up from function code if @statUp is nil.
    # This also covers Dynamax "RaiseUserSide..." effects like Max Airstream.
    if !stat_up && fc.match?(/RaiseUser(?:Side)?/)
      # Handle RaiseUserMainStats first (all main stats)
      if fc.match?(/RaiseUser(?:Side)?MainStats/)
        stages = fc[/RaiseUser(?:Side)?MainStats(\d+)/, 1].to_i
        parsed = []
        [:ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED].each do |s|
          parsed.push(s, stages)
        end
        stat_up = parsed
        stat_up_from_fc = true
      else
        # Parse compound stat abbreviations like AtkDef1, SpAtkSpDefSpd2, Atk1Spd2
        # Sorted longest-first so "Attack" matches before "Atk", "SpAtk" before "Atk"
        stat_map = { "Attack" => :ATTACK, "Defense" => :DEFENSE,
                     "SpAtk" => :SPECIAL_ATTACK, "SpDef" => :SPECIAL_DEFENSE,
                     "Speed" => :SPEED, "Spd" => :SPEED,
                     "Atk" => :ATTACK, "Def" => :DEFENSE,
                     "Evasion" => :EVASION, "Acc" => :ACCURACY, "Eva" => :EVASION }
        stat_names = stat_map.keys.sort_by { |k| -k.length }
        stat_pattern = stat_names.map { |s| Regexp.escape(s) }.join("|")
        if fc =~ /RaiseUser(?:Side)?((?:(?:#{stat_pattern})\d*)+)/
          segment = $1
          pairs = []
          while !segment.empty?
            matched = false
            stat_names.each do |sname|
              next unless segment.start_with?(sname)
              segment = segment[sname.length..]
              digit = segment[/^\d+/]
              if digit
                segment = segment[digit.length..]
                pairs << [stat_map[sname], digit.to_i]
              else
                pairs << [stat_map[sname], nil]  # shared stage, filled below
              end
              matched = true
              break
            end
            break unless matched
          end
          # Fill nil stages with the last seen stage (e.g. AtkDef1 → both get 1)
          last_stage = pairs.reverse.find { |_, s| s }&.last || 1
          parsed = []
          pairs.each { |stat, stage| parsed.push(stat, stage || last_stage) }
          stat_up = parsed.empty? ? nil : parsed
          stat_up_from_fc = true if stat_up
        end
      end
    end
    next score unless stat_up

    is_status = move.statusMove?
    # Skip damaging moves whose stat boost is a non-guaranteed secondary effect
    # (e.g. Meteor Mash 20% Atk). Function-code-parsed boosts are always
    # guaranteed, and so are Dynamax side-boosting Max Moves like Max Airstream.
    guaranteed_damaging_setup = stat_up_from_fc || fc.start_with?("RaiseUserSide")
    if move.damagingMove? && !guaranteed_damaging_setup && real_move.addlEffect != 100
      PBDebug.log_ai("[smart_setup] Skipped #{move.name}: damaging boost isn't guaranteed.")
      next score
    end

    battler = user.battler
    next score unless battler

    speed_stage_gain = 0
    boosted_stats = []
    (stat_up.length / 2).times do |i|
      stat_id = stat_up[i * 2]
      stages  = stat_up[i * 2 + 1]
      boosted_stats << stat_id
      speed_stage_gain += stages if stat_id == :SPEED
    end
    if speed_stage_gain > 0 && battler.stages[:SPEED] >= 2
      speed_penalty = (boosted_stats.uniq == [:SPEED]) ? 40 : 20
      score -= speed_penalty
      PBDebug.log_score_change(-speed_penalty,
        "Setup speed penalty: Speed stage already #{battler.stages[:SPEED]}.")
    end

    # -----------------------------------------------------------------------
    # Phazing check (status setup moves only): skip if foe has a phazing
    # move that won't fail against the AI's battler.
    # -----------------------------------------------------------------------
    if is_status
      phaze_codes = ["SwitchOutTargetStatusMove", "SwitchOutTargetDamagingMove"]
      foe_has_phazing = false
      sim_move = Battle::AI::AIMove.new(ai)
      ai.each_foe_battler(user.side) do |b, _i|
        foe_has_phazing = ai.known_foe_moves(b).any? do |m|
          next false unless phaze_codes.include?(m.function_code)
          sim_move.set_up(m)
          !ai.pbPredictMoveFailureAgainstTarget(sim_move, b, user)
        end
        break if foe_has_phazing
      end
      if foe_has_phazing
        PBDebug.log_ai("[smart_setup] Skipped: foe has effective phazing move.")
        next Battle::AI::MOVE_FAIL_SCORE
      end
    end

    # -----------------------------------------------------------------------
    # Skip if all boosted stats are already maxed
    # -----------------------------------------------------------------------
    any_effective = (stat_up.length / 2).times.any? do |i|
      stat_id = stat_up[i * 2]
      stages  = stat_up[i * 2 + 1]
      battler.stages[stat_id] < [battler.stages[stat_id] + stages, 6].min
    end
    unless any_effective
      PBDebug.log_ai("[smart_setup] All boosted stats already maxed.")
      next score
    end

    # -----------------------------------------------------------------------
    # Per-foe 1v1 comparison: current vs boosted (using actual simulation)
    # -----------------------------------------------------------------------
    summary = ai.matchup_summary
    total_bonus = 0
    setup_move_id = move.id

    ai.each_foe_battler(user.side) do |b, _i|
      foe_entry = summary[:foes][b.index]
      next unless foe_entry

      # Unaware ignores all stat stage changes — setup is wasted
      if b.has_active_ability?(:UNAWARE)
        foe_bonus = is_status ? -40 : 0
        PBDebug.log_ai("[smart_setup] vs #{b.name}: foe has Unaware → #{foe_bonus}")
        total_bonus += foe_bonus
        next
      end

      foe_best_move = foe_entry[:best_move]
      next unless foe_best_move

      user_best = ai.best_damage_move_for_simulation(user, b)
      next unless user_best

      user_best_action = ai.simulation_action_for_move_data(user_best, b)
      foe_best = ai.best_damage_move_for_simulation(b, user)
      next unless foe_best
      foe_best_action = ai.simulation_action_for_move_data(foe_best, user)
      next unless user_best_action && foe_best_action

      # Current: user attacks with best move, foe attacks with best move
      current_result = foe_entry[:sim_result]
      next unless current_result

      # Boosted: user uses setup move first, then best attack; foe keeps attacking
      boosted_result = ai.simulate_battle(
        user.index, b.index,
        [setup_move_id, user_best_action],
        [foe_best_action],
        max_turns: 5
      )

      # --- Score comparison ---
      cur_wins = current_result.user_wins?
      bst_wins = boosted_result.user_wins?
      foe_bonus = 0

      if !cur_wins && bst_wins
        # Boost flips losing → winning
        foe_bonus = is_status ? 50 : 25
      elsif cur_wins && !bst_wins
        # Boost makes winning → losing (HP cost too high for status)
        foe_bonus = is_status ? -60 : -40
      elsif cur_wins && bst_wins
        # Both win — compare turns to KO and remaining HP
        cur_turns = current_result.target_ko_turn || 999
        bst_turns = boosted_result.target_ko_turn || 999
        # Boosted takes longer due to setup turn, but should deal more damage per hit
        # Score based on HP remaining after winning
        cur_hp_pct = current_result.user_hp.to_f / [user.totalhp, 1].max
        bst_hp_pct = boosted_result.user_hp.to_f / [user.totalhp, 1].max
        hp_saved = bst_hp_pct - cur_hp_pct
        # Base value: you win AND end up boosted for future matchups
        base = [cur_turns * 3, 15].min + 10
        if hp_saved > 0
          foe_bonus = base + (hp_saved * 40).round.clamp(0, 25)
        elsif hp_saved >= -0.05
          foe_bonus = base
        else
          foe_bonus = [base + (hp_saved * 30).round, 0].max
        end
      else
        # Both lose — status wastes a turn, damaging still deals damage
        foe_bonus = is_status ? -60 : 0
      end

      cur_turns = current_result.target_ko_turn || 999
      bst_turns = boosted_result.target_ko_turn || 999
      PBDebug.log_ai("[smart_setup] vs #{b.name}: cur=#{cur_wins ? 'W' : 'L'}(#{cur_turns}T) " \
                     "bst=#{bst_wins ? 'W' : 'L'}(#{bst_turns}T) → #{foe_bonus > 0 ? '+' : ''}#{foe_bonus}")
      total_bonus += foe_bonus
    end

    score += total_bonus
    PBDebug.log_score_change(total_bonus, "Setup simulation: 1v1 comparison.")

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
        penalty = -(20 + (existing - 1) * 20)
      end
    when "AddToxicSpikesToFoeSide"
      existing = user.pbOpposingSide.effects[PBEffects::ToxicSpikes]
      if existing >= 2
        penalty = -200
      elsif existing >= 1
        penalty = - 30  # 2nd layer of Toxic Spikes is significantly less useful
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
# 10. Penalize hazard setup when foe can boost
# A boosted foe is an immediate threat — spending a turn on hazards wastes tempo.
#===============================================================================
HAZARD_FUNCTION_CODES = [
  "AddStealthRocksToFoeSide", "AddSpikesToFoeSide",
  "AddToxicSpikesToFoeSide", "AddStickyWebToFoeSide"
].freeze

Battle::AI::Handlers::GeneralMoveScore.add(:penalize_hazards_vs_boosted_foe,
  proc { |score, move, user, ai, battle|
    next score unless HAZARD_FUNCTION_CODES.include?(ai.safe_function_code(move))

    if ai.foe_has_setup_move?(user)
      score -= 80
      PBDebug.log_score_change(-80, "Hazard vs foe with setup move(s).")
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
    next score if user.wild?

    battler = user.battler
    next score unless battler

    # Don't use if Substitute is already active
    next Battle::AI::MOVE_FAIL_SCORE if battler.effects[PBEffects::Substitute] > 0

    # -------------------------------------------------------------------------
    # Phazing check: Substitute doesn't block phazing moves
    # -------------------------------------------------------------------------
    phaze_codes = ["SwitchOutTargetStatusMove"]
    foe_has_phazing = false
    sim_move = Battle::AI::AIMove.new(ai)
    ai.each_foe_battler(user.side) do |b, _i|
      foe_has_phazing = ai.known_foe_moves(b).any? do |m|
        next false unless phaze_codes.include?(m.function_code)
        sim_move.set_up(m)
        !ai.pbPredictMoveFailureAgainstTarget(sim_move, b, user)
      end
      break if foe_has_phazing
    end
    if foe_has_phazing
      PBDebug.log_ai("[tactical_substitute] Skipped: foe has effective phazing move.")
      next Battle::AI::MOVE_FAIL_SCORE
    end

    # -------------------------------------------------------------------------
    # B. Foe threat analysis — reject if any foe can break the Substitute in one hit
    # -------------------------------------------------------------------------
    sub_break_threshold = battler.totalhp / 4.0
    threatened = false
    ai.each_foe_battler(user.side) do |b, _i|
      best_dmg = ai.best_damage_move(b, user)&.dig(:dmg) || 0
      PBDebug.log_ai(
        "[tactical_substitute] Threat check vs #{b.name}: best_dmg=#{best_dmg}, " \
        "sub_threshold=#{sub_break_threshold}"
      )
      if best_dmg >= sub_break_threshold
        threatened = true
        PBDebug.log_ai("[tactical_substitute] Rejected: #{b.name} can break Substitute in one hit.")
        break
      end
    end

    # Substitute is counterproductive when foe can break it in one hit
    next Battle::AI::MOVE_USELESS_SCORE if threatened

    # -------------------------------------------------------------------------
    # C. Evaluate plans behind Substitute
    # -------------------------------------------------------------------------

    future_value = 0

    # 1) Substitute value increases if user has setup moves
    if ai.battler_has_setup_move?(user)
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
      "Tactical Substitute (HP=#{(battler.hp * 100 / battler.totalhp)}%)."
    )

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
    next score unless ai.move_is_setup?(move, user)

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
    next score if user.wild?
    
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

    # Consecutive Protect — exponentially less likely to succeed
    if battler.effects[PBEffects::ProtectRate] > 1
      rate = battler.effects[PBEffects::ProtectRate]
      penalty = rate * 100
      score -= penalty
      PBDebug.log_score_change(-penalty, "Protect likely to fail (consecutive, rate=#{rate}).")
      next score
    end

    stall_value = 0

    # Residual damage on foe
    ai.each_foe_battler(user.side) do |b, i|
      stall_value += 10 if b.status == :POISON && b.statusCount > 0  # Toxic
      stall_value += 8  if b.status == :BURN
      stall_value += 5  if b.status == :POISON && b.statusCount == 0

      # Foe has setup moves — Protect gives them a free turn to boost
      if ai.battler_has_setup_move?(b)
        stall_value -= 15
        PBDebug.log_ai("[smart_protect] Foe #{b.name} has setup moves → -15 stall value.")
      end
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
      score -= 40
      PBDebug.log_score_change(-40, "Protect has no stall value.")
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
    if ai.foe_has_setup_move?(user)
      score -= 40
      PBDebug.log_score_change(-40, "Rest: foe has setup potential while user sleeps.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Status Move Survival / Fail Check (Global)
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:status_survival_check_global,
  proc { |score, move, user, ai, battle|
    next score if move.damagingMove?
    next score if user.wild?

    summary = ai.matchup_summary
    all_failed = true
    has_foes = false

    ai.each_foe_battler(user.side) do |b, _i|
      has_foes = true
      foe_entry = summary[:foes][b.index]
      next unless foe_entry

      survives = foe_entry[:status_survival]&.dig(move.id)
      if survives == true
        all_failed = false
        break
      end
    end

    if has_foes && all_failed
      score -= 100
      PBDebug.log_score_change(-100, "Global survival: status move fails or user KO'd before acting vs all foes")
    end

    next score
  }
)
