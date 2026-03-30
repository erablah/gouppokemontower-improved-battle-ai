#===============================================================================
# [AI_Improved_Matchup.rb] - Damage Caching, Matchup Analysis
# Uses actual battle simulation via deep copies.
#===============================================================================

class Battle::AI
  #---------------------------------------------------------------------------
  # Returns {move_id => {move: Battle::Move, dmg: int}}
  # Simulates damage for each of attacker's damaging moves against defender.
  #---------------------------------------------------------------------------
  def damage_moves(attacker, defender)
    return {} if attacker.fainted? || defender.fainted?
    mega = (@battle.pbRegisteredMegaEvolution?(attacker.index) rescue false)
    tera = (@battle.pbRegisteredTerastallize?(attacker.index) rescue false) || attacker.tera?
    def_tera = defender.tera?
    key = [attacker.index, defender.index, @battle.turnCount, mega, tera, def_tera,
           attacker.pokemon&.personalID, defender.pokemon&.personalID]
    (@_ai_dmg_cache ||= {})[key] ||= begin
      PBDebug.log_ai("[damage_moves] computing #{attacker.name} → #{defender.name} (turn #{@battle.turnCount})")
      moves_by_id = {}
      moves_list = (attacker.side != @user.side) ? known_foe_moves(attacker) : attacker.moves
      moves_list.each do |m|
        next unless m&.damagingMove?
        next unless attacker.pbCanChooseMove?(m, false, false)
        # Use 1-turn simulation to get actual damage dealt
        result = simulate_battle(attacker.index, defender.index, [m.id], [], max_turns: 1)
        dmg = result.turn_log[0] ? result.turn_log[0][:target_hp_before] - result.turn_log[0][:target_hp_after] : 0
        dmg = [dmg, 0].max
        pct_total = (100.0 * dmg / [1, defender.totalhp].max).round(1)
        pct_hp    = (100.0 * dmg / [1, defender.hp].max).round(1)
        PBDebug.log_ai("  #{m.name}: #{dmg} dmg (#{pct_total}% totalhp / #{pct_hp}% curhp)")
        moves_by_id[m.id] = { move: m, dmg: dmg }
        tick_scene
      end
      moves_by_id
    end
  end

  #---------------------------------------------------------------------------
  # Returns the best move data {move:, dmg:} from damage_moves.
  #---------------------------------------------------------------------------
  def best_damage_move(attacker, defender)
    dmg_data = damage_moves(attacker, defender)
    dmg_data.values.max_by { |md| md[:dmg] }
  end

  #---------------------------------------------------------------------------
  # Compute damage for each of attacker's moves with a pre_switch applied.
  # pre_switch: { battler_index => party_index } — can be on either side.
  # If the attacker is being switched, iterates the switch-in's moves.
  # If the target is being switched, iterates the attacker's moves.
  # Returns {move_id => {move:, dmg:}}
  #---------------------------------------------------------------------------
  def damage_moves_with_switch(attacker_index, target_index, pre_switch)
    # Determine move source and cache IDs
    if pre_switch[attacker_index]
      pkmn = @battle.pbParty(attacker_index)[pre_switch[attacker_index]]
      return {} unless pkmn
      move_source = pkmn.moves
      atk_id = pkmn.personalID
    else
      attacker_ai = @battlers[attacker_index]
      move_source = (attacker_ai.side != @user.side) ? known_foe_moves(attacker_ai) : attacker_ai.moves
      atk_id = attacker_ai.pokemon&.personalID
    end

    if pre_switch[target_index]
      tgt_pkmn = @battle.pbParty(target_index)[pre_switch[target_index]]
      return {} unless tgt_pkmn
      tgt_id = tgt_pkmn.personalID
    else
      tgt_id = @battle.battlers[target_index].pokemon&.personalID
    end

    key = [:dmg_switch, attacker_index, target_index, @battle.turnCount, atk_id, tgt_id]
    (@_ai_dmg_cache ||= {})[key] ||= begin
      moves_by_id = {}
      move_source.each do |m|
        if m.is_a?(Pokemon::Move)
          next unless m.power > 0 && (m.pp > 0 || m.total_pp == 0)
        else
          next unless m&.damagingMove?
          next unless @battle.battlers[attacker_index].pbCanChooseMove?(m, false, false)
        end
        result = simulate_battle(attacker_index, target_index, [m.id], [], max_turns: 1, pre_switch: pre_switch)
        dmg = result.turn_log[0] ? result.turn_log[0][:target_hp_before] - result.turn_log[0][:target_hp_after] : 0
        moves_by_id[m.id] = { move: m, dmg: [dmg, 0].max }
        tick_scene
      end
      moves_by_id
    end
  end

  #---------------------------------------------------------------------------
  # Returns the best move data {move:, dmg:} from damage_moves_with_switch.
  #---------------------------------------------------------------------------
  def best_damage_move_with_switch(attacker_index, target_index, pre_switch)
    dmg_data = damage_moves_with_switch(attacker_index, target_index, pre_switch)
    dmg_data.values.max_by { |md| md[:dmg] }
  end

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
      user_speed = @user.rough_stat(:SPEED)
      summary[:user_speed] = user_speed
      summary[:foe_can_ohko] = false
      summary[:foe_can_ohko_and_outspeeds] = false
      summary[:user_can_ko_any] = false
      summary[:max_foe_dmg] = 0

      each_foe_battler(@user.side) do |b, _i|
        user_best = best_damage_move(@user, b)
        foe_best = best_damage_move(b, @user)

        foe_speed = b.rough_stat(:SPEED)
        foe_outspeeds = b.faster_than?(@user)
        foe_best_move = foe_best&.dig(:move)
        foe_has_priority = foe_best_move && foe_best_move.priority > 0
        foe_effectively_outspeeds = foe_outspeeds || foe_has_priority

        # Run 10-turn sim for each of user's damaging moves against foe's best
        move_results = {}
        if foe_best_move
          damage_moves(@user, b).each do |move_id, _data|
            move_results[move_id] = simulate_battle(
              @user.index, b.index,
              [move_id], [foe_best_move.id],
              max_turns: 10
            )
            tick_scene
          end
        end
        sim_result = user_best ? move_results[user_best[:move].id] : nil

        foe_entry = {
          best_dmg:      foe_best&.dig(:dmg) || 0,
          best_move:     foe_best_move,
          best_priority: foe_best_move ? foe_best_move.priority : 0,
          user_best_dmg: user_best&.dig(:dmg) || 0,
          speed:         foe_speed,
          outspeeds:     foe_outspeeds,
          effectively_outspeeds: foe_effectively_outspeeds,
          can_ohko:      sim_result&.target_can_ohko? || false,
          foe_hp:        b.hp,
          foe_totalhp:   b.totalhp,
          sim_result:    sim_result,
          move_results:  move_results,
        }
        foe_entry[:switch_prediction_roll] = pbAIRandom(100)
        summary[:foes][b.index] = foe_entry
        summary[:max_foe_dmg] = [summary[:max_foe_dmg], foe_entry[:best_dmg]].max
        summary[:foe_can_ohko] = true if foe_entry[:can_ohko]
        summary[:foe_can_ohko_and_outspeeds] = true if foe_entry[:can_ohko] && foe_effectively_outspeeds
        summary[:user_can_ko_any] = true if sim_result&.user_can_ohko?
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
end
