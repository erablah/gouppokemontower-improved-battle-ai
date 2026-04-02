#===============================================================================
# [AI_Improved_Matchup.rb] - Matchup Analysis
#===============================================================================

class Battle::AI

  #---------------------------------------------------------------------------
  # Returns a cached summary of KO/speed data for all current battler pairs.
  #---------------------------------------------------------------------------
  def matchup_summary
    mega = (@battle.pbRegisteredMegaEvolution?(@user.index) rescue false)
    tera = (@battle.pbRegisteredTerastallize?(@user.index) rescue false) || @user.tera?
    foe_ids = []
    each_foe_battler(@user.side) { |b, _| foe_ids << b.pokemon&.personalID }
    key = [@user.index, @battle.turnCount, mega, tera, @user.pokemon&.personalID, foe_ids]
    (@_matchup_cache ||= {})[key] ||= begin
      summary = { foes: {} }
      summary[:max_foe_dmg] = 0

      each_foe_battler(@user.side) do |b, _i|
        user_best = best_damage_move_for_simulation(@user, b)
        foe_best = best_damage_move_for_simulation(b, @user)

        foe_outspeeds = b.faster_than?(@user)
        foe_best_move = foe_best&.dig(:move)
        foe_has_priority = foe_best_move && foe_best_move.priority > 0
        foe_effectively_outspeeds = foe_outspeeds || foe_has_priority

        # Run 10-turn sim for each of user's damaging moves against foe's best
        move_results = {}
        move_results_by_id = {}
        if foe_best_move
          damage_moves(@user, b).each do |move_key, data|
            user_action = simulation_action_for_move_data(data, b)
            next unless user_action
            foe_action = simulation_action_for_move_data(foe_best, @user)
            next unless foe_action
            result = simulate_battle(
              @user.index, b.index,
              [user_action], [foe_action],
              max_turns: 10
            )
            move_results[move_key] = result
            move_results_by_id[data[:move].id] = result
            tick_scene
          end
        end
        sim_result = user_best ? move_results[user_best[:key]] : nil

        status_survival = {}
        foe_best_dmg = foe_best&.dig(:dmg) || 0
        foe_action = nil
        
        if foe_best_dmg >= @user.hp
          lethal_moves = damage_moves(b, @user).values.select { |d| d[:dmg] >= @user.hp }
          foe_lethal_move = lethal_moves.max_by { |d| d[:move].priority }
          foe_action = simulation_action_for_move_data(foe_lethal_move, @user) if foe_lethal_move
        else
          foe_action = simulation_action_for_move_data(foe_best, @user) if foe_best_move
        end

        foe_actions = foe_action ? [foe_action] : []
        @user.moves.each do |m|
          next if m.damagingMove?
          res = simulate_battle(
            @user.index, b.index,
            [m.id], foe_actions,
            max_turns: 1
          )
          # A foe pivoting out before the user acts is not a mechanical failure
          # of the user's status move, just an interrupted line the sim doesn't
          # continue modeling.
          status_survival[m.id] =
            res.user_succeeded ||
            (res.terminated_by_switch &&
             res.switch_type == :live_switch &&
             res.switch_battler_index == b.index &&
             !res.user_fainted)
          tick_scene
        end

        foe_entry = {
          best_dmg:      foe_best_dmg,
          best_move:     foe_best_move,
          effectively_outspeeds: foe_effectively_outspeeds,
          can_ohko:      sim_result&.target_can_ohko? || false,
          sim_result:    sim_result,
          move_results:  move_results,
          move_results_by_id: move_results_by_id,
          status_survival: status_survival
        }
        summary[:foes][b.index] = foe_entry
        summary[:max_foe_dmg] = [summary[:max_foe_dmg], foe_best_dmg].max
      end
      summary
    end
  end

  #---------------------------------------------------------------------------
  # Fog of War: returns the list of moves the AI "knows" about for a foe.
  # If the foe has never acted, one non-STAB move may be hidden (50% chance).
  #---------------------------------------------------------------------------
  def known_foe_moves(foe_ai_battler)
    cache_key = [foe_ai_battler.index, @battle.turnCount, foe_ai_battler.pokemon&.personalID]
    (@_known_foe_moves_cache ||= {})[cache_key] ||= begin
      all_moves = foe_ai_battler.moves.compact
      acted_ids = @battle.instance_variable_get(:@_foe_acted_ids) || {}
      pkmn = foe_ai_battler.pokemon

      if pkmn && acted_ids[pkmn.personalID]
        all_moves
      else
        foe_types = foe_ai_battler.pbTypes(true)
        protected_moves = []
        foe_types.each do |t|
          best = all_moves.select { |m| m.type == t && m.damagingMove? }
                          .max_by { |m| m.power }
          protected_moves << best if best
        end

        remaining = all_moves - protected_moves
        if remaining.length > 0 && pbAIRandom(100) < 50
          hide = remaining[pbAIRandom(remaining.length)]
          result = all_moves - [hide]
          PBDebug.log_ai("[known_foe_moves] Hiding #{hide.name} from #{foe_ai_battler.name} (never acted)")
          result
        else
          all_moves
        end
      end
    end
  end

  #---------------------------------------------------------------------------
  # [NEW] Lazy per-move status survival check for reserve switch-ins.
  # Only simulates the specific move requested, caching individual results.
  #---------------------------------------------------------------------------
  def status_move_survival_with_switch(attacker_index, target_index, pre_switch, foe_lethal_action, foe_vs_current_action, m_id)
    if pre_switch[attacker_index]
      pkmn = @battle.pbParty(attacker_index)[pre_switch[attacker_index]]
      return false unless pkmn
      atk_id = pkmn.personalID
    else
      atk_id = @battle.battlers[attacker_index].pokemon&.personalID
    end

    tgt_id = pre_switch[target_index] ? @battle.pbParty(target_index)[pre_switch[target_index]].personalID : @battle.battlers[target_index].pokemon&.personalID

    key = [:status_switch, attacker_index, target_index, @battle.turnCount, atk_id, tgt_id, foe_lethal_action, foe_vs_current_action, m_id]
    (@_ai_dmg_cache ||= {})[key] ||= begin
      voluntary_switch = @battle.command_phase
      party_index = pre_switch[attacker_index]

      PBDebug.log("status move survival)")
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
      sim_foe_actions = foe_lethal_action ? [foe_lethal_action] : []
      res = simulate_battle(
        attacker_index, target_index,
        [m_id], sim_foe_actions,
        sim: sim, max_turns: 1
      )
      tick_scene
      res.user_succeeded
    end
  end

  #---------------------------------------------------------------------------
  # [NEW] Exposes whether a specific reserve status move survives its switch-in
  #---------------------------------------------------------------------------
  def reserve_status_move_survives?(idxBattler, pkmn, target_battler, m_id)
    party_index = @battle.pbParty(idxBattler).index(pkmn)
    return true unless party_index

    pre_switch = { idxBattler => party_index }

    best_damage = best_damage_move_with_switch_for_simulation(target_battler.index, idxBattler, pre_switch)

    # foe_dmg_hash = damage_moves_with_switch(target_battler.index, idxBattler, pre_switch)
    # lethal_moves = foe_dmg_hash.values.select { |d| d[:dmg] >= pkmn.hp }
    return true unless best_damage

    # foe_lethal_move = lethal_moves.max_by { |d| d[:move].priority }&.dig(:move)
    # return true unless foe_lethal_move

    foe_vs_current = best_damage_move_for_simulation(target_battler, @user) unless @user.fainted?
    foe_vs_current_action = foe_vs_current ? simulation_action_for_move_data(foe_vs_current, @user) : simulation_action_for_move_data(best_damage, pkmn)

    status_move_survival_with_switch(
      idxBattler, target_battler.index, pre_switch,
      simulation_action_for_move_data(best_damage, pkmn), foe_vs_current_action, m_id
    ) == true
  end

end
