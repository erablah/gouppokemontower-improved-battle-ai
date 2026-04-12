#===============================================================================
# ScoreReplacement Handlers
# Simple handlers that work with raw Pokemon data.
#===============================================================================

class Battle::AI
  SLOW_PIVOT_FUNCTION_CODES = [
    "SwitchOutUserStatusMove",
    "SwitchOutUserDamagingMove",
    "SwitchOutUserPassOnEffects",
    "LowerTargetAtkSpAtk1SwitchOutUser",
    "StartHailWeatherSwitchOutUser",
    "SwitchOutUserStartHailWeather",
    "UserMakeSubstituteSwitchOut"
  ].freeze

  HAZARD_CLEAR_FUNCTION_CODES = [
    "RemoveUserBindingAndEntryHazards",
    "RemoveUserBindingAndEntryHazardsPoisonTarget",
    "LowerTargetEvasion1RemoveSideEffects"
  ].freeze

  SWITCH_IN_SIM_MAX_TURNS = 4

  def replacement_1v1_results_key(idxBattler, pkmn)
    battler = @battle.battlers[idxBattler]
    party = @battle.pbParty(idxBattler)
    party_index = party.index(pkmn)
    foe_snapshot = @battle.allOtherSideBattlers(idxBattler).map do |foe|
      [foe.index, foe.pokemon&.personalID, foe.pokemonIndex, foe.turnCount, foe.fainted?]
    end
    [
      idxBattler,
      @battle.command_phase,
      battler.pokemon&.personalID,
      battler.pokemonIndex,
      party_index,
      pkmn.personalID,
      foe_snapshot
    ]
  end

  def replacement_1v1_results(idxBattler, pkmn)
    key = replacement_1v1_results_key(idxBattler, pkmn)
    @_replacement_1v1_results ||= {}
    @_replacement_1v1_results[key] ||= build_replacement_1v1_results(idxBattler, pkmn)
  end

  def replacement_1v1_result_for_foe(idxBattler, pkmn, foe_battler)
    foe_index = foe_battler.is_a?(Integer) ? foe_battler : foe_battler.index
    foe_results = replacement_1v1_results(idxBattler, pkmn)&.[](foe_index)
    return nil unless foe_results
    return foe_results if foe_battler.is_a?(Integer)
    return nil if foe_results[:foe_personal_id] != foe_battler.pokemon&.personalID
    foe_results
  end

  def replacement_1v1_move_result(foe_results, move_id)
    return nil unless foe_results
    foe_results[:damaging_move_results]&.find { |move_result| move_result[:move_id] == move_id }
  end

  def replacement_move_survives?(foe_results, move_id, status_move: false)
    return false unless foe_results
    if status_move
      cached = foe_results[:status_move_survival]&.dig(move_id)
      return cached.is_a?(Hash) ? cached[:success] == true : cached == true
    end

    damaging_result = replacement_1v1_move_result(foe_results, move_id)
    return false if !damaging_result || !damaging_result[:result]

    result = damaging_result[:result]
    result.user_succeeded && !result.user_fainted
  end

  def build_replacement_1v1_results(idxBattler, pkmn)
    party = @battle.pbParty(idxBattler)
    party_index = party.index(pkmn)
    return {} unless party_index

    pre_switch = { idxBattler => party_index }
    all_results = {}

    each_foe_battler(@user.side) do |b, _i|
      voluntary_switch = @battle.command_phase || (!b.movedThisRound? && b.turnCount > 0)
      foe_vs_current = best_damage_move(b, @user) unless @user.fainted?
      if voluntary_switch && !foe_vs_current
        all_results[b.index] = {
          foe_index: b.index,
          foe_personal_id: b.pokemon&.personalID,
          skipped_reason: :unknown_current_foe_move
        }
        next
      end
      foe_vs_current_action = foe_vs_current ? simulation_action_for_move_data(foe_vs_current) : nil

      foe_vs_reserve = best_damage_move_with_switch(b.index, idxBattler, pre_switch)
      foe_vs_reserve_action = foe_vs_reserve ? simulation_action_for_move_data(foe_vs_reserve) : foe_vs_current_action

      reserve_dmg = damage_moves_with_switch(idxBattler, b.index, pre_switch) || {}
      reserve_candidates = reserve_dmg.values.sort_by { |md| -md[:dmg] }

      foe_results = {
        foe_index: b.index,
        foe_personal_id: b.pokemon&.personalID,
        foe_vs_current: foe_vs_current,
        foe_vs_reserve: foe_vs_reserve,
        voluntary_switch: voluntary_switch,
        reserve_candidates: reserve_candidates.map(&:dup),
        damaging_move_results: [],
        status_move_survival: {},
        best_result: nil,
        best_move_action: nil
      }
      all_results[b.index] = foe_results

      if !foe_vs_reserve_action && reserve_candidates.empty?
        foe_results[:skip_scoring] = true
        next
      end

      # Only precompute the top damaging line for replacement scoring.
      # Other moves are simulated on-demand by explicit callers that need them.
      reserve_sim_candidates = reserve_candidates.first ? [reserve_candidates.first] : []

      reserve_sim_candidates.each do |md|
        move_action = simulation_action_for_move_data(md)
        next unless move_action

        sim = if voluntary_switch
          create_switched_sim(
            pre_switch,
            voluntary_switch: true,
            target_index: b.index,
            foe_move_id: foe_vs_current_action
          )
        else
          create_switched_sim(pre_switch)
        end
        result = simulate_battle(
          idxBattler, b.index,
          [move_action], [foe_vs_reserve_action],
          sim: sim, pre_switch: pre_switch, max_turns: Battle::AI::SWITCH_IN_SIM_MAX_TURNS
        )

        foe_results[:damaging_move_results] << {
          move_id: md[:move]&.id,
          action: move_action,
          move_data: md.dup,
          result: result
        }

        best_result = foe_results[:best_result]
        if best_result.nil? ||
           (result.user_wins? && !best_result.user_wins?) ||
           (result.user_wins? && best_result.user_wins? && (result.user_hp || 0) > (best_result.user_hp || 0)) ||
           (!result.user_wins? && !best_result.user_wins? && (result.target_hp || 0) < (best_result.target_hp || 0))
          foe_results[:best_result] = result
          foe_results[:best_move_action] = move_action
        end
      end
    end

    all_results
  end

  def score_replacement_1v1_results(pkmn, foe_battler, foe_results)
    return 0 unless foe_results
    return 0 if foe_results[:skip_scoring] || foe_results[:skipped_reason]

    if foe_results[:reserve_candidates].empty?
      if pkmn.moves.any? { |m| m.status_move? && reserve_status_move_succeeds?(@user.index, pkmn, foe_battler, m.id) }
        PBDebug.log_score_change(0, "#{pkmn.name} vs #{foe_battler.name}: no damaging moves, but can act with status")
        return 0
      end
      PBDebug.log_score_change(-50, "#{pkmn.name} vs #{foe_battler.name}: dies before using a status move")
      return -50
    end

    best_result = foe_results[:best_result]
    died_on_entry = best_result.nil? || (best_result.user_fainted && !best_result.user_succeeded)
    if died_on_entry
      PBDebug.log_score_change(-50, "#{pkmn.name} vs #{foe_battler.name}: dies on entry")
      return -50
    end

    # --- Extract HP data from simulation turn log ---
    first_turn = best_result.turn_log&.first
    entry_hp = first_turn ? first_turn[:user_hp_before] : pkmn.hp
    entry_hp_pct = entry_hp.to_f / [pkmn.totalhp, 1].max
    foe_start_hp = first_turn ? first_turn[:target_hp_before] : foe_battler.hp
    voluntary = foe_results[:voluntary_switch]

    # How much HP we're "spending" by sending this pkmn in (relative to its max)
    hp_invested_pct = pkmn.hp.to_f / [pkmn.totalhp, 1].max

    # --- Switch-in fragility penalty (voluntary switches only) ---
    # Heavy free-turn damage makes the switch-in risky
    # Penalty scales from 0 at <=30% damage taken up to 25 at ~100%.
    # This makes fragile switch-ins score lower than bulky alternatives,
    # so they're only chosen when nothing healthier is available.
    fragility_penalty = 0
    if voluntary
      switch_in_dmg_pct = (pkmn.hp - entry_hp).to_f / [pkmn.totalhp, 1].max
      if switch_in_dmg_pct > 0.30
        fragility_penalty = ((switch_in_dmg_pct - 0.30) * 35).round.clamp(0, 40)
        PBDebug.log_score_change(-fragility_penalty,
          "#{pkmn.name} vs #{foe_battler.name}: risky entry (took #{(switch_in_dmg_pct * 100).round}% on switch-in, #{(entry_hp_pct * 100).round}% HP remaining)")
      end
    end

    if best_result.user_wins?
      u_turns = best_result.target_ko_turn || 999
      f_turns = best_result.user_ko_turn || 999
      turn_adv = f_turns - u_turns
      bonus = 5 + [turn_adv * 5, 10].min
      bonus += 10 if best_result.user_can_ohko?
      hp_pct = best_result.user_hp.to_f / [pkmn.totalhp, 1].max
      bonus = hp_pct >= 0.25 ? bonus + (hp_pct * 10).round : bonus - ((1 - hp_pct) * 10).round
      bonus -= fragility_penalty
      PBDebug.log_score_change(bonus + fragility_penalty, "#{pkmn.name} vs #{foe_battler.name}: wins (KO turn #{u_turns}, #{(hp_pct * 100).round}% remaining)")
      return bonus

    elsif best_result.target_wins?
      # --- Trade-value-aware loss scoring ---
      dmg_dealt_pct = 0.0
      if best_result.target_hp && foe_battler.totalhp > 0
        dmg_dealt = foe_start_hp - best_result.target_hp
        dmg_dealt_pct = dmg_dealt.to_f / foe_battler.totalhp
      end
      trade_ratio = hp_invested_pct > 0 ? dmg_dealt_pct / hp_invested_pct : 0.0
      f_turns = best_result.user_ko_turn || 999

      if trade_ratio >= 1.0
        # Excellent trade: dealt more %HP to foe than we had
        penalty = (5 - [f_turns - 1, 3].min).clamp(0, 5)
      elsif trade_ratio >= 0.6
        # Decent trade
        penalty = (15 - (trade_ratio * 15).round).clamp(5, 15)
        penalty -= [f_turns - 2, 2].min if f_turns > 2
      else
        # Bad trade
        penalty = 15
        penalty += best_result.target_can_ohko? ? [15 - (trade_ratio * 20).round, 0].max : 0
        penalty += ((1.0 - trade_ratio) * 10).round
        penalty -= f_turns * 2 if f_turns > 2
        penalty = penalty.clamp(15, 40)
      end

      penalty += fragility_penalty
      PBDebug.log_score_change(-penalty,
        "#{pkmn.name} vs #{foe_battler.name}: loses (KO'd turn #{f_turns}, dealt #{(dmg_dealt_pct * 100).round}%, trade ratio #{(trade_ratio * 100).round}%)")
      return -penalty

    else
      # --- No KO: net HP trade (signed) ---
      dmg_dealt_pct = 0.0
      hp_lost_pct = 0.0
      if best_result.target_hp && foe_battler.totalhp > 0
        dmg_dealt = foe_start_hp - best_result.target_hp
        dmg_dealt_pct = dmg_dealt.to_f / foe_battler.totalhp
      end
      if best_result.user_hp && pkmn.totalhp > 0
        hp_lost = pkmn.hp - best_result.user_hp
        hp_lost_pct = hp_lost.to_f / pkmn.totalhp
      end
      net_trade = dmg_dealt_pct - hp_lost_pct
      bonus = (net_trade * 15).round.clamp(-10, 10) - fragility_penalty
      PBDebug.log_score_change(bonus + fragility_penalty,
        "#{pkmn.name} vs #{foe_battler.name}: no KO (dealt #{(dmg_dealt_pct * 100).round}%, lost #{(hp_lost_pct * 100).round}%)")
      return bonus
    end
  end

  def side_hazard_clear_bonus(side)
    bonus = 0
    bonus += 20 if side.effects[PBEffects::StealthRock]
    bonus += 12 * side.effects[PBEffects::Spikes]
    bonus += 10 * side.effects[PBEffects::ToxicSpikes]
    bonus += 12 if side.effects[PBEffects::StickyWeb]
    bonus
  end

  def reserve_has_followup_switch_option?(idxBattler, reserve_party_index)
    @battle.eachInTeamFromBattlerIndex(idxBattler) do |_pkmn, i|
      next if i == reserve_party_index
      return true if @battle.pbCanSwitchIn?(idxBattler, i)
    end
    false
  end

  def reserve_slow_pivot_bonus(idxBattler, pkmn, foe_battler, pre_switch, voluntary_switch: @battle.command_phase)
    return 0 unless voluntary_switch

    party = @battle.pbParty(idxBattler)
    reserve_party_index = party.index(pkmn)
    return 0 unless reserve_party_index
    return 0 unless reserve_has_followup_switch_option?(idxBattler, reserve_party_index)

    pivot_moves = pkmn.moves.select do |m|
      m.is_a?(Pokemon::Move) && SLOW_PIVOT_FUNCTION_CODES.include?(safe_function_code(m))
    end
    return 0 if pivot_moves.empty?

    cached_foe_results = replacement_1v1_result_for_foe(idxBattler, pkmn, foe_battler)
    foe_vs_reserve = cached_foe_results ? cached_foe_results[:foe_vs_reserve] :
      best_damage_move_with_switch(foe_battler.index, idxBattler, pre_switch)
    foe_vs_reserve_action = foe_vs_reserve ? simulation_action_for_move_data(foe_vs_reserve) : nil
    return 0 unless foe_vs_reserve_action

    foe_vs_current = if cached_foe_results
      cached_foe_results[:foe_vs_current]
    elsif !@user.fainted?
      best_damage_move(foe_battler, @user)
    end
    foe_vs_current_action = foe_vs_current ? simulation_action_for_move_data(foe_vs_current) : foe_vs_reserve_action

    best_bonus = 0
    sim = nil

    pivot_moves.each do |move|
      damaging_result = cached_foe_results&.dig(:damaging_move_results)&.find do |move_result|
        move_result[:move_id] == move.id
      end
      result = damaging_result ? damaging_result[:result] : nil
      if !result
        sim ||= create_switched_sim(
          pre_switch,
          voluntary_switch: true,
          target_index: foe_battler.index,
          foe_move_id: foe_vs_current_action
        )
        result = simulate_battle(
          idxBattler, foe_battler.index,
          [move.id], [foe_vs_reserve_action],
          sim: sim, max_turns: 1
        )
      end
      next unless result.terminated_by_switch &&
                  result.switch_type == :live_switch &&
                  result.switch_battler_index == idxBattler
      next unless result.user_succeeded && !result.user_fainted
      next unless result.target_got_action

      hp_pct = result.user_hp.to_f / [pkmn.totalhp, 1].max
      move_data = GameData::Move.get(move.id)
      damaging_pivot = move_data&.category != 2
      bonus = 8 + (damaging_pivot ? 2 : 0) + (hp_pct * 5).round
      if bonus > best_bonus
        best_bonus = bonus
        PBDebug.log_ai("[slow_pivot] #{pkmn.name} can slow pivot with #{move.name} vs #{foe_battler.name} (+#{bonus})")
      end
    end

    best_bonus
  end
end

Battle::AI::Handlers::ScoreReplacement.add(:entry_hazards,
  proc { |idxBattler, pkmn, score, battle, ai|
    prev_score = score
    entry_hazard_damage = ai.calculate_entry_hazard_damage(pkmn, idxBattler & 1)
    if entry_hazard_damage >= pkmn.hp
      score -= 50   # pkmn will just faint
    end
    PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: entry hazard damage #{entry_hazard_damage}")
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:toxics_spikes_and_sticky_web,
  proc { |idxBattler, pkmn, score, battle, ai|
    if !pkmn.hasItem?(:HEAVYDUTYBOOTS) && !ai.pokemon_airborne?(pkmn)
      # Toxic Spikes
      if ai.user.pbOwnSide.effects[PBEffects::ToxicSpikes] > 0
        if ai.pokemon_can_be_poisoned?(pkmn)
          score -= 10
        elsif pkmn.types.include?(:POISON)
          score += 10
        end
      end
    end
    next score
  }
)

#===============================================================================
# 1v1 Matchup Evaluation via Battle Simulation
# Simulates the reserve switching in and fighting each foe.
# - Voluntary switch (command phase): foe gets a free attack during switch-in
# - Faint replacement / pivot (attack phase): entry effects only, no free hit
#===============================================================================
Battle::AI::Handlers::ScoreReplacement.add(:one_v_one_matchup,
  proc { |idxBattler, pkmn, score, battle, ai|
    cached_results = ai.replacement_1v1_results(idxBattler, pkmn)
    next score if !cached_results || cached_results.empty?

    ai.each_foe_battler(ai.user.side) do |b, _i|
      score += ai.score_replacement_1v1_results(pkmn, b, cached_results[b.index])
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:slow_pivot_followup,
  proc { |idxBattler, pkmn, score, battle, ai|
    party = battle.pbParty(idxBattler)
    party_index = party.index(pkmn)
    next score unless party_index

    pre_switch = { idxBattler => party_index }

    ai.each_foe_battler(ai.user.side) do |b, _i|
      voluntary_switch = battle.command_phase || (!b.movedThisRound? && b.turnCount > 0)
      slow_pivot_bonus = ai.reserve_slow_pivot_bonus(
        idxBattler, pkmn, b, pre_switch, voluntary_switch: voluntary_switch
      )
      next if slow_pivot_bonus <= 0

      score += slow_pivot_bonus
      PBDebug.log_score_change(slow_pivot_bonus, "#{pkmn.name} vs #{b.name}: safe slow pivot option")
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:hazard_clearing,
  proc { |idxBattler, pkmn, score, battle, ai|
    own_side = ai.user.pbOwnSide
    hazard_bonus = ai.side_hazard_clear_bonus(own_side)
    next score if hazard_bonus <= 0

    if battle.pbAbleNonActiveCount(idxBattler & 1) == 0
      hazard_bonus = (hazard_bonus * 0.5).round
    end
    next score if hazard_bonus <= 0

    clear_moves = pkmn.moves.select do |m|
      m.is_a?(Pokemon::Move) && Battle::AI::HAZARD_CLEAR_FUNCTION_CODES.include?(ai.safe_function_code(m))
    end
    next score if clear_moves.empty?

    cached_results = ai.replacement_1v1_results(idxBattler, pkmn)
    next score if !cached_results || cached_results.empty?

    best_bonus = 0
    clear_moves.each do |m|
      move_survives = cached_results.any? do |foe_index, foe_results|
        if m.status_move?
          ai.reserve_status_move_succeeds?(idxBattler, pkmn, battle.battlers[foe_index], m.id)
        else
          ai.replacement_move_survives?(foe_results, m.id)
        end
      end
      next unless move_survives

      bonus = hazard_bonus
      bonus += 3 if !m.status_move?
      if ai.safe_function_code(m) == "LowerTargetEvasion1RemoveSideEffects"
        foe_has_hazards = false
        ai.each_foe_battler(ai.user.side) do |b, _i|
          if ai.side_hazard_clear_bonus(b.pbOwnSide) > 0
            foe_has_hazards = true
            break
          end
        end
        bonus -= 8 if foe_has_hazards
      end
      next if bonus <= best_bonus

      best_bonus = bonus
      PBDebug.log_ai("[hazard_clear] #{pkmn.name} values #{m.name} for hazard removal (+#{bonus})")
    end

    if best_bonus > 0
      score += best_bonus
      PBDebug.log_score_change(best_bonus, "#{pkmn.name}: can clear entry hazards")
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:wish_healing,
  proc { |idxBattler, pkmn, score, battle, ai|
    position = battle.positions[idxBattler]
    if position.effects[PBEffects::Wish] > 0
      amt = position.effects[PBEffects::WishAmount]
      if pkmn.totalhp - pkmn.hp > amt * 2 / 3
        score += 20 * [pkmn.totalhp - pkmn.hp, amt].min / pkmn.totalhp
      end
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:perish_song_fading,
  proc { |idxBattler, pkmn, score, battle, ai|
    score += 20 if ai.user.effects[PBEffects::PerishSong] == 1
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:utility_switch_in,
  proc { |idxBattler, pkmn, score, battle, ai|
    foe_total_boosts = 0
    foe_has_screens = false
    foe_has_status_moves = false
    foe_has_boosted_target = false
    foe_has_physical_target = false

    ai.each_foe_battler(ai.user.side) do |b, _i|
      foe_positive_boosts = ai.total_positive_boosts(b)
      foe_total_boosts += foe_positive_boosts
      foe_has_boosted_target ||= foe_positive_boosts >= 2
      foe_side = b.pbOwnSide
      foe_has_screens = true if foe_side.effects[PBEffects::Reflect] > 0 ||
                                 foe_side.effects[PBEffects::LightScreen] > 0 ||
                                 foe_side.effects[PBEffects::AuroraVeil] > 0
      status_count = 0
      ai.known_foe_moves(b).each { |m| status_count += 1 if m.statusMove? }
      foe_has_status_moves = true if status_count >= 2

      visible_moves = ai.known_foe_moves(b)
      has_physical = visible_moves.any? { |m| m.physicalMove? }
      foe_has_physical_target ||= has_physical && !b.has_active_ability?(:GUTS)
    end

    succeeds_move = proc { |m_id|
      s_val = true
      ai.each_foe_battler(ai.user.side) do |fb, _|
        if !ai.reserve_status_move_succeeds?(idxBattler, pkmn, fb, m_id)
          s_val = false
          break
        end
      end
      s_val
    }

    pkmn.moves.each do |m|
      next unless m.status_move?
      next unless succeeds_move.call(m.id)

      case m.function_code
      when "BurnTarget"
        next unless foe_has_physical_target
        score += 12
        PBDebug.log_score_change(12, "Utility: #{m.name} vs physical foe")
        break
      when "ParalyzeTarget", "ParalyzeTargetIfNotTypeImmune"
        bonus = 8
        bonus += 4 if foe_has_boosted_target
        score += bonus
        PBDebug.log_score_change(bonus, "Utility: #{m.name}")
        break
      when "PoisonTarget", "BadPoisonTarget"
        bonus = 8
        bonus += 4 if foe_has_boosted_target
        score += bonus
        PBDebug.log_score_change(bonus, "Utility: #{m.name}")
        break
      end
    end

    # Unaware vs boosted foe
    if foe_total_boosts >= 2 && pkmn.hasAbility?(:UNAWARE)
      bonus = 25 + (foe_total_boosts * 3)
      score += bonus
      PBDebug.log_score_change(bonus, "Utility: Unaware vs +#{foe_total_boosts} boosts")
    end

    # Haze / Clear Smog vs boosted foe
    if foe_total_boosts >= 2
      pkmn.moves.each do |m|
        if ["ResetAllBattlersStatStages", "ResetTargetStatStages"].include?(m.function_code)
          next unless succeeds_move.call(m.id)
          bonus = 20 + (foe_total_boosts * 2)
          score += bonus
          PBDebug.log_score_change(bonus, "Utility: #{m.name} vs +#{foe_total_boosts} boosts")
          break
        end
      end
    end

    # Whirlwind / Roar / Dragon Tail vs boosted foe
    if foe_total_boosts >= 2
      pkmn.moves.each do |m|
        if ["SwitchOutTargetStatusMove", "SwitchOutTargetDamagingMove"].include?(m.function_code)
          next unless succeeds_move.call(m.id)
          bonus = 20 + (foe_total_boosts * 2)
          ai.each_foe_battler(ai.user.side) do |b, _|
            foe_side = b.pbOwnSide
            bonus += 5 if foe_side.effects[PBEffects::StealthRock]
            bonus += 3 * foe_side.effects[PBEffects::Spikes]
            break
          end
          score += bonus
          PBDebug.log_score_change(bonus, "Utility: #{m.name} (phaze) vs +#{foe_total_boosts} boosts")
          break
        end
      end
    end

    # Taunt/Encore vs status-heavy foe
    if foe_has_status_moves
      pkmn.moves.each do |m|
        if m.function_code == "DisableTargetStatusMoves" || m.function_code == "DisableTargetUsingDifferentMove"
          next unless succeeds_move.call(m.id)
          score += 10
          PBDebug.log_score_change(10, "Utility: Taunt vs status-heavy foe")
          break
        end
      end
    end

    # Brick Break vs screens
    if foe_has_screens
      pkmn.moves.each do |m|
        if m.function_code == "RemoveScreens"
          next unless succeeds_move.call(m.id)
          score += 10
          PBDebug.log_score_change(10, "Utility: Brick Break vs screens")
          break
        end
      end
    end

    #start own screen
    pkmn.moves.each do |m|
      if ["StartWeakenDamageAgainstUserSideIfHail", "StartWeakenPhysicalDamageAgainstUserSide", "StartWeakenSpecialDamageAgainstUserSide"].include?(m.function_code)
        next unless succeeds_move.call(m.id)
        score += 10
        PBDebug.log_score_change(10, "Utility: #{m.name} to set up screens")
        break
      end
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:intimidate_switch_in,
  proc { |idxBattler, pkmn, score, battle, ai|
    next score unless pkmn.hasAbility?(:INTIMIDATE)
    ai.each_foe_battler(ai.user.side) do |b, _i|
      next if b.has_active_ability?(Battle::AI::INTIMIDATE_IMMUNE)
      next if battle.moldBreaker
      next if b.stages[:ATTACK] <= -6
      phys_count = 0
      ai.known_foe_moves(b).each do |m|
        next unless m&.damagingMove?
        phys_count += 1 if m.physicalMove?
      end
      next if phys_count == 0
      phys_ratio = phys_count.to_f / 4
      bonus = (10 * phys_ratio).round
      bonus = (bonus * 0.5).round if b.stages[:ATTACK] < 0
      if bonus > 0
        score += bonus
        PBDebug.log_score_change(bonus, "#{pkmn.name}: Intimidate vs #{b.name} (#{phys_count} phys moves)")
      end
    end
    next score
  }
)
