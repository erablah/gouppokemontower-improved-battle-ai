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
      score -= (0.4 * (100 - move.accuracy)).to_i
    end
    score -= 10 if move.move.pp <= 5
    PBDebug.log_score_change(score - old_score, "move is less suitable to be Choiced into")
    next score
  }
)

Battle::AI::Handlers::GeneralMoveScore.add(:smart_setup_move_final,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?

    real_move = move.move
    stat_up = (real_move.respond_to?(:statUp) && real_move.statUp) ? real_move.statUp : nil
    fc = ai.safe_function_code(move) || ""
    stat_up_from_fc = false

    # Fallback: parse stat_up from function code if @statUp is nil
    if !stat_up && fc.include?("RaiseUser")
      # Handle RaiseUserMainStats first (all main stats)
      if fc.include?("RaiseUserMainStats")
        stages = fc[/RaiseUserMainStats(\d+)/, 1].to_i
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
        if fc =~ /RaiseUser((?:(?:#{stat_pattern})\d*)+)/
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
    # (e.g. Meteor Mash 20% Atk). Function-code-parsed boosts are always guaranteed.
    if move.damagingMove? && !stat_up_from_fc && real_move.addlEffect != 100
      next score
    end

    battler = user.battler
    next score unless battler

    # -----------------------------------------------------------------------
    # Phazing check (status moves only)
    # -----------------------------------------------------------------------
    if is_status
      immune_to_phazing = battler.hasActiveAbility?(:GOODASGOLD) ||
                          battler.effects[PBEffects::Ingrain]
      unless immune_to_phazing
        phaze_codes = ["SwitchOutTargetStatusMove", "SwitchOutTargetDamagingMove"]
        foe_has_phazing = false
        ai.each_foe_battler(user.side) do |b, _i|
          foe_has_phazing = ai.known_foe_moves(b).any? do |m|
            next false unless phaze_codes.include?(m.function_code)
            next true if m.statusMove?
            calc_type = m.pbCalcType(b.battler)
            eff = Effectiveness.calculate(calc_type, *battler.pbTypes(true))
            !Effectiveness.ineffective?(eff)
          end
          break if foe_has_phazing
        end
        if foe_has_phazing
          PBDebug.log_ai("[smart_setup] Skipped: foe has effective phazing move.")
          next Battle::AI::MOVE_FAIL_SCORE
        end
      end
    end

    # -----------------------------------------------------------------------
    # Compute boost multipliers from stat_up (skip if all stats already maxed)
    # -----------------------------------------------------------------------
    has_physical = battler.moves.compact.any? { |m| m.physicalMove? }
    has_special  = battler.moves.compact.any? { |m| m.specialMove? }

    atk_mult = 1.0; spa_mult = 1.0; def_mult = 1.0; spdef_mult = 1.0; spd_boost = 0
    any_effective = false
    (stat_up.length / 2).times do |i|
      stat_id = stat_up[i * 2]
      stages  = stat_up[i * 2 + 1]
      cur = battler.stages[stat_id]
      new_s = [cur + stages, 6].min
      next if cur == new_s
      any_effective = true
      ratio = ai.stat_stage_mult(new_s) / ai.stat_stage_mult(cur)
      case stat_id
      when :ATTACK         then atk_mult = ratio if has_physical
      when :SPECIAL_ATTACK then spa_mult = ratio if has_special
      when :DEFENSE        then def_mult = ratio
      when :SPECIAL_DEFENSE then spdef_mult = ratio
      when :SPEED          then spd_boost = stages
      end
    end
    unless any_effective
      PBDebug.log_ai("[smart_setup] All boosted stats already maxed.")
      next score
    end

    # -----------------------------------------------------------------------
    # Per-foe 1v1 comparison: current vs boosted
    # -----------------------------------------------------------------------
    summary = ai.matchup_summary
    total_bonus = 0

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

      current_result = foe_entry[:one_v_one]
      foe_best_dmg  = foe_entry[:best_dmg]
      foe_best_move = foe_entry[:best_move]

      user_c = ai.make_combatant(user, b)
      foe_c  = ai.make_combatant(b, user)

      # --- Boosted user damage (pick best move and best priority after boost) ---
      user_dmg_data = ai.damage_moves(user, b)
      boosted_user_dmg = 0
      boosted_user_move = nil
      boosted_user_pri_dmg = 0
      user_dmg_data.each_value do |md|
        d = md[:dmg]
        if md[:move].physicalMove?
          d = (d * atk_mult).round
        elsif md[:move].specialMove?
          d = (d * spa_mult).round
        end
        if d > boosted_user_dmg
          boosted_user_dmg = d
          boosted_user_move = md[:move]
        end
        if md[:move].priority > 0 && d > boosted_user_pri_dmg
          boosted_user_pri_dmg = d
        end
      end

      # --- Boosted foe damage (reduced by our defensive boosts) ---
      boosted_foe_dmg = foe_best_dmg
      if foe_best_move
        if foe_best_move.physicalMove?
          boosted_foe_dmg = (foe_best_dmg / def_mult).round
        elsif foe_best_move.specialMove?
          boosted_foe_dmg = (foe_best_dmg / spdef_mult).round
        end
      end

      # --- Speed after boost ---
      if spd_boost > 0
        user_has_lagging = LAGGING_TAIL_ITEMS.include?(battler.item_id) && battler.itemActive?
        foe_has_lagging = LAGGING_TAIL_ITEMS.include?(b.battler.item_id) && b.battler.itemActive?
        if user_has_lagging && !foe_has_lagging
          boosted_outspeeds = false
        elsif foe_has_lagging && !user_has_lagging
          boosted_outspeeds = true
        else
          user_speed = user.rough_stat(:SPEED)
          cur_spd_stage = battler.stages[:SPEED]
          new_spd_stage = [cur_spd_stage + spd_boost, 6].min
          base_speed = user_speed / ai.stat_stage_mult(cur_spd_stage)
          boosted_speed = base_speed * ai.stat_stage_mult(new_spd_stage)
          trick_room = battle.field.effects[PBEffects::TrickRoom] > 0
          boosted_outspeeds = (boosted_speed > foe_entry[:speed]) ^ trick_room
        end
      else
        boosted_outspeeds = !foe_entry[:outspeeds]
      end

      # --- Status moves: user takes one hit during setup turn ---
      if is_status
        boosted_user_hp = user.hp - foe_best_dmg
        if boosted_user_hp <= 0
          total_bonus -= 200
          PBDebug.log_ai("[smart_setup] vs #{b.name}: would die during setup → -200")
          next
        end
        # Foe heals from drain during setup turn
        foe_mods = ai.move_sim_modifiers(foe_best_move)
        boosted_foe_hp = [b.hp + (foe_mods[:drain_factor] * foe_best_dmg).round, b.battler.totalhp].min
      else
        boosted_user_hp = user.hp
        boosted_foe_hp = b.hp
      end

      # --- Run boosted 1v1 ---
      boosted_result = ai.one_v_one_result(
        user_c.merge(dmg: boosted_user_dmg, move: boosted_user_move,
                     hp: boosted_user_hp, priority_dmg: boosted_user_pri_dmg),
        foe_c.merge(dmg: boosted_foe_dmg, hp: boosted_foe_hp),
        boosted_outspeeds
      )

      # --- Score comparison ---
      cur_wins = current_result[:user_wins]
      bst_wins = boosted_result[:user_wins]
      foe_bonus = 0

      if !cur_wins && bst_wins
        # Boost flips losing → winning
        foe_bonus = is_status ? 50 : 25
      elsif cur_wins && !bst_wins
        # Boost makes winning → losing (HP cost too high for status)
        foe_bonus = is_status ? -40 : -20
      elsif cur_wins && bst_wins
        # Both win — score by absolute HP saved (normalized to user's actual HP)
        current_remaining = current_result[:user_hp_pct] * user.hp
        boosted_remaining = boosted_result[:user_hp_pct] * boosted_user_hp
        dmg_saved_pct = (boosted_remaining - current_remaining) / [user.hp, 1].max.to_f
        # Base value: you win AND end up boosted for future matchups
        base = [current_result[:f_turns] * 3, 15].min + 10
        if dmg_saved_pct > 0
          # Saved HP on top of being boosted
          foe_bonus = base + (dmg_saved_pct * 40).round.clamp(0, 25)
        elsif dmg_saved_pct >= -0.01
          # Same damage — still good, you're boosted
          foe_bonus = base
        else
          # Costs more HP but still winning and boosted — reduce base
          foe_bonus = [base + (dmg_saved_pct * 30).round, 0].max
        end
      else
        # Both lose — status wastes a turn, damaging still deals damage
        foe_bonus = is_status ? -40 : 0
      end

      PBDebug.log_ai("[smart_setup] vs #{b.name}: cur=#{cur_wins ? 'W' : 'L'}(#{current_result[:u_turns]}T) " \
                     "bst=#{bst_wins ? 'W' : 'L'}(#{boosted_result[:u_turns]}T) → #{foe_bonus > 0 ? '+' : ''}#{foe_bonus}")
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
      PBDebug.log_score_change(-penalty, "Hazard vs boosted foe (+#{foe_boosts} total boosts).")
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

