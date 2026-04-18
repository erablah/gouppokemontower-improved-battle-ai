#===============================================================================
# [AI_Improved_Matchup.rb] - Matchup Analysis
#===============================================================================

class Battle::AI
  def status_move_succeeded_in_result?(result, target_index)
    result.user_succeeded ||
      (result.terminated_by_switch &&
       result.switch_type == :live_switch &&
       result.switch_battler_index == target_index &&
       !result.user_fainted)
  end

  def eager_current_status_move_success(target_battler, foe_action)
    status_survival = {}
    status_moves = @user.moves.select { |move| move&.statusMove? }
    return status_survival if status_moves.empty?

    foe_actions = foe_action ? [foe_action] : []
    status_moves.each do |move|
      result = simulate_battle(
        @user.index, target_battler.index,
        [move.id], foe_actions,
        max_turns: 1
      )
      status_survival[move.id] = {
        success: status_move_succeeded_in_result?(result, target_battler.index),
        result:  result
      }
    end
    status_survival
  end

  #---------------------------------------------------------------------------
  # Returns a cached summary of KO/speed data for all current battler pairs.
  #---------------------------------------------------------------------------
  def matchup_summary
    mega = @battle.pbRegisteredMegaEvolution?(@user.index) 
    tera = @battle.pbRegisteredTerastallize?(@user.index) || @user.tera?
    foe_ids = []
    each_foe_battler(@user.side) { |b, _| foe_ids << b.pokemon&.personalID }
    key = [@user.index, @battle.turnCount, mega, tera, @user.pokemon&.personalID, foe_ids]
    (@_matchup_cache ||= {})[key] ||= begin
      summary = { foes: {} }
      summary[:max_foe_dmg] = 0

      each_foe_battler(@user.side) do |b, _i|
        user_best = best_damage_move(@user, b)
        foe_best = best_damage_move(b, @user)

        foe_outspeeds = b.faster_than?(@user)
        foe_best_move = foe_best&.dig(:move)
        foe_has_priority = foe_best_move && foe_best_move.priority > 0
        foe_effectively_outspeeds = foe_outspeeds || foe_has_priority

        # Run 10-turn sim for each of user's damaging moves against foe's best
        move_results = {}
        move_results_by_id = {}
        if foe_best_move
          damage_moves(@user, b).each do |move_key, data|
            user_action = simulation_action_for_move_data(data)
            next unless user_action
            foe_action = simulation_action_for_move_data(foe_best)
            next unless foe_action
            result = simulate_battle(
              @user.index, b.index,
              [user_action], [foe_action],
              max_turns: 10
            )
            move_results[move_key] = result
            move_results_by_id[data[:move].id] = result
          end
        end
        sim_result = user_best ? move_results[user_best[:key]] : nil

        foe_best_dmg = foe_best&.dig(:dmg) || 0
        foe_action = nil
        
        if foe_best_dmg >= @user.hp
          lethal_moves = damage_moves(b, @user).values.select { |d| d[:dmg] >= @user.hp }
          foe_lethal_move = lethal_moves.max_by { |d| d[:move].priority }
          foe_action = simulation_action_for_move_data(foe_lethal_move) if foe_lethal_move
        else
          foe_action = simulation_action_for_move_data(foe_best) if foe_best_move
        end

        foe_entry = {
          best_dmg:      foe_best_dmg,
          best_move:     foe_best_move,
          effectively_outspeeds: foe_effectively_outspeeds,
          can_ohko:      sim_result&.target_can_ohko? || false,
          sim_result:    sim_result,
          move_results:  move_results,
          move_results_by_id: move_results_by_id,
          status_survival: eager_current_status_move_success(b, foe_action)
        }
        summary[:foes][b.index] = foe_entry
        summary[:max_foe_dmg] = [summary[:max_foe_dmg], foe_best_dmg].max
      end
      summary
    end
  end

  #---------------------------------------------------------------------------
  # Lazy per-move status success check for reserve switch-ins.
  #---------------------------------------------------------------------------
  def reserve_status_move_success(attacker_index, target_index, pre_switch, foe_vs_reserve_action, foe_vs_current_action, move_id)
    if pre_switch[attacker_index]
      pkmn = @battle.pbParty(attacker_index)[pre_switch[attacker_index]]
      return false unless pkmn
      atk_id = pkmn.personalID
    else
      atk_id = @battle.battlers[attacker_index].pokemon&.personalID
    end

    tgt_id = pre_switch[target_index] ? @battle.pbParty(target_index)[pre_switch[target_index]].personalID : @battle.battlers[target_index].pokemon&.personalID

    key = [:status_switch, attacker_index, target_index, @battle.turnCount, atk_id, tgt_id, foe_vs_reserve_action, foe_vs_current_action, move_id]
    (@_ai_dmg_cache ||= {})[key] ||= begin
      voluntary_switch = @battle.command_phase
      party_index = pre_switch[attacker_index]

      if voluntary_switch && party_index
        sim = create_switched_sim(
           pre_switch,
           voluntary_switch: true,
           target_index: target_index,
           foe_move_id: foe_vs_current_action
        )
      else
        sim = create_switched_sim(pre_switch)
      end
      sim_foe_actions = foe_vs_reserve_action ? [foe_vs_reserve_action] : []
      res = simulate_battle(
        attacker_index, target_index,
        [move_id], sim_foe_actions,
        sim: sim, max_turns: 1
      )
      {
        success: status_move_succeeded_in_result?(res, target_index),
        result:  res
      }
    end
  end

  def current_status_move_succeeds?(target_battler, m_id)
    summary = matchup_summary
    foe_entry = summary[:foes][target_battler.index]
    return false unless foe_entry

    cached = foe_entry[:status_survival][m_id]
    cached.is_a?(Hash) ? cached[:success] == true : cached == true
  end

  def current_status_move_sim_result(target_battler, m_id)
    summary = matchup_summary
    foe_entry = summary[:foes][target_battler.index]
    return nil unless foe_entry

    cached = foe_entry[:status_survival][m_id]
    cached.is_a?(Hash) ? cached[:result] : nil
  end

  #---------------------------------------------------------------------------
  # Exposes whether a specific reserve status move succeeds after its switch-in.
  #---------------------------------------------------------------------------
  def reserve_status_move_succeeds?(idxBattler, pkmn, target_battler, m_id)
    party_index = @battle.pbParty(idxBattler).index(pkmn)
    return true unless party_index

    replacement_1v1_results(idxBattler, pkmn)
    cached_foe_results = replacement_1v1_result_for_foe(idxBattler, pkmn, target_battler)
    return true unless cached_foe_results

    cached_entry = cached_foe_results&.dig(:status_move_survival, m_id)
    if cached_entry.is_a?(Hash)
      return cached_entry[:success] == true
    elsif !cached_entry.nil?
      return cached_entry == true
    end

    # Skip sim when foe damage is clearly non-threatening to the reserve
    pre_switch = { idxBattler => party_index }
    foe_vs_reserve_data = cached_foe_results[:foe_vs_reserve]
    foe_vs_reserve_dmg = foe_vs_reserve_data ? foe_vs_reserve_data[:dmg].to_i : 0
    voluntary = cached_foe_results[:voluntary_switch]
    total_threat = foe_vs_reserve_dmg
    if voluntary
      foe_vs_current_data = cached_foe_results[:foe_vs_current]
      if foe_vs_current_data
        # Look up foe's best-vs-current move's actual damage against the reserve (cache hit)
        foe_to_reserve = damage_moves_with_switch(target_battler.index, idxBattler, pre_switch)
        switch_in_dmg = foe_to_reserve&.dig(foe_vs_current_data[:key], :dmg).to_i
        total_threat += switch_in_dmg
      else
        total_threat += foe_vs_reserve_dmg
      end
    end
    if total_threat < pkmn.hp * 0.9
      PBDebug.log_ai("[status_skip] #{pkmn.name} clearly survives vs #{target_battler.name} (threat #{total_threat} < #{(pkmn.hp * 0.9).round} HP)")
      cached_foe_results[:status_move_survival][m_id] = { success: true, result: nil }
      return true
    end

    foe_vs_reserve = cached_foe_results[:foe_vs_reserve]
    foe_vs_reserve_action = foe_vs_reserve ? simulation_action_for_move_data(foe_vs_reserve) : nil
    foe_vs_current = cached_foe_results[:foe_vs_current]
    foe_vs_current_action = foe_vs_current ? simulation_action_for_move_data(foe_vs_current) : foe_vs_reserve_action
    status_result = reserve_status_move_success(
      idxBattler, target_battler.index, pre_switch, foe_vs_reserve_action, foe_vs_current_action, m_id
    )
    cached_foe_results[:status_move_survival][m_id] = status_result
    status_result.is_a?(Hash) ? status_result[:success] == true : status_result == true
  end

  def reserve_status_move_sim_result(idxBattler, pkmn, target_battler, m_id)
    party_index = @battle.pbParty(idxBattler).index(pkmn)
    return nil unless party_index

    replacement_1v1_results(idxBattler, pkmn)
    cached_foe_results = replacement_1v1_result_for_foe(idxBattler, pkmn, target_battler)
    return nil unless cached_foe_results

    cached_entry = cached_foe_results&.dig(:status_move_survival, m_id)
    if cached_entry.is_a?(Hash)
      return cached_entry[:result]
    end

    # Trigger the sim to populate cache
    reserve_status_move_succeeds?(idxBattler, pkmn, target_battler, m_id)
    cached_entry = cached_foe_results&.dig(:status_move_survival, m_id)
    cached_entry.is_a?(Hash) ? cached_entry[:result] : nil
  end

end
