#===============================================================================
# ScoreReplacement Handlers
# Simple handlers that work with raw Pokemon data.
#===============================================================================

Battle::AI::Handlers::ScoreReplacement.add(:entry_hazards,
  proc { |idxBattler, pkmn, score, battle, ai|
    prev_score = score
    entry_hazard_damage = ai.calculate_entry_hazard_damage(pkmn, idxBattler & 1)
    if entry_hazard_damage >= pkmn.hp
      score -= 50   # pkmn will just faint
    elsif entry_hazard_damage > 0
      score -= 50 * entry_hazard_damage / pkmn.hp
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
    # Find party index
    party = battle.pbParty(idxBattler)
    party_index = party.index(pkmn)
    next score unless party_index

    voluntary_switch = battle.command_phase
    pre_switch = { idxBattler => party_index }

    ai.each_foe_battler(ai.user.side) do |b, _i|
      # Foe's best move vs current battler (used on switch-in turn for voluntary switches)
      foe_vs_current = ai.best_damage_move_for_simulation(b, ai.user) unless ai.user.fainted?
      if voluntary_switch
        next unless foe_vs_current
      end
      foe_vs_current_action = foe_vs_current ? ai.simulation_action_for_move_data(foe_vs_current, ai.user) : nil

      # Foe's best move vs the reserve (actual damage via pre_switch sim)
      foe_vs_reserve = ai.best_damage_move_with_switch_for_simulation(b.index, idxBattler, pre_switch)
      foe_vs_reserve_action = foe_vs_reserve ? ai.simulation_action_for_move_data(foe_vs_reserve, pkmn) : foe_vs_current_action
      # Reserve's best damaging moves vs foe (top 2 by actual damage)
      reserve_dmg = ai.damage_moves_with_switch(idxBattler, b.index, pre_switch)
      reserve_dmg ||= {}
      reserve_candidates = ai.send(:_simulatable_damage_data, reserve_dmg, b).values.sort_by { |md| -md[:dmg] }.first(1)
      status_moves = pkmn.moves.select { |m| m.is_a?(Pokemon::Move) && m.power == 0 }

      # For forced switches, if we couldn't determine any foe move, skip
      next if !foe_vs_reserve_action || (reserve_candidates.empty? && status_moves.empty?)

      if reserve_candidates.empty?
        if status_moves.any? { |m| ai.reserve_status_move_survives?(idxBattler, pkmn, b, m.id) }
          PBDebug.log_score_change(0, "#{pkmn.name} vs #{b.name}: no damaging moves, but can act with status")
          next
        end
        score -= 50
        PBDebug.log_score_change(-50, "#{pkmn.name} vs #{b.name}: dies before using a status move")
        next
      end

      best_result = nil
      reserve_candidates.each do |md|
        if voluntary_switch
          PBDebug.log("scorereplacement)")
          # Turn 1: switch in, foe uses best move vs current battler
          # Turn 2+: reserve attacks, foe uses best move vs reserve
          sim = ai.create_switched_sim(
             pre_switch, 
             voluntary_switch: true, 
             target_index: b.index, 
             foe_move_id: foe_vs_current_action
          )
          result = ai.simulate_battle(
            idxBattler, b.index,
            [ai.simulation_action_for_move_data(md, b)], [foe_vs_reserve_action],
            sim: sim, max_turns: 5
          )
        else
          # Faint replacement or pivot: entry effects applied, no free hit
          sim = ai.create_switched_sim(pre_switch)
          result = ai.simulate_battle(
            idxBattler, b.index,
            [ai.simulation_action_for_move_data(md, b)], [foe_vs_reserve_action],
            sim: sim, max_turns: 5
          )
        end

        # Keep the best result (prefer wins, then higher remaining HP)
        if best_result.nil? || 
          (result.user_wins? && !best_result.user_wins?) ||
          (result.user_wins? && best_result.user_wins? && (result.user_hp || 0) > (best_result.user_hp || 0)) ||
          (!result.user_wins? && !best_result.user_wins? && (result.enemy_hp || 0) < (best_result.enemy_hp || 0))
            best_result = result
        end
      end

      # --- Scoring ---
      died_on_entry = best_result.nil? || (best_result.user_fainted && !best_result.user_succeeded)

      if died_on_entry 
        # Dies on entry (hazards or immediate OHKO)
        score -= 50
        PBDebug.log_score_change(-50, "#{pkmn.name} vs #{b.name}: dies on entry")
      elsif best_result.user_wins?
        u_turns = best_result.target_ko_turn || 999
        f_turns = best_result.user_ko_turn || 999
        turn_adv = f_turns - u_turns
        bonus = 5 + [turn_adv * 5, 10].min
        bonus += 10 if best_result.user_can_ohko?
        # Remaining HP bonus (healthier finish = better for later matchups)
        hp_pct = best_result.user_hp.to_f / [pkmn.totalhp, 1].max
        bonus += (hp_pct * 10).round
        score += bonus
        PBDebug.log_score_change(bonus, "#{pkmn.name} vs #{b.name}: wins (KO turn #{u_turns}, #{(hp_pct * 100).round}% remaining)")
      elsif best_result.target_wins?
        f_turns = best_result.user_ko_turn || 999
        penalty = 15
        penalty += 25 if best_result.target_can_ohko?
        # Less penalty if reserve dealt significant damage before losing
        if best_result.target_hp && b.totalhp > 0
          dmg_dealt_pct = 1.0 - (best_result.target_hp.to_f / b.totalhp)
          penalty -= (dmg_dealt_pct * 10).round
        end
        penalty = [penalty, 5].max
        score -= penalty
        PBDebug.log_score_change(-penalty, "#{pkmn.name} vs #{b.name}: loses (KO'd turn #{f_turns})")
      else
        if best_result.target_hp && b.totalhp > 0
          dmg_dealt_pct = 1.0 - (best_result.target_hp.to_f / b.totalhp)
          hp_pct = best_result.user_hp.to_f / [pkmn.totalhp, 1].max
          bonus = [dmg_dealt_pct - hp_pct, 0].max * 10
        end
        bonus = bonus ? bonus.round : 1
        score += bonus
        PBDebug.log_score_change(bonus, "#{pkmn.name} vs #{b.name}: no KO (survived #{f_turns} turns)")
      end
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

    ai.each_foe_battler(ai.user.side) do |b, i|
      GameData::Stat.each_battle do |s|
        foe_total_boosts += b.stages[s.id] if b.stages[s.id] > 0
      end
      foe_side = b.pbOwnSide
      foe_has_screens = true if foe_side.effects[PBEffects::Reflect] > 0 ||
                                 foe_side.effects[PBEffects::LightScreen] > 0 ||
                                 foe_side.effects[PBEffects::AuroraVeil] > 0
      status_count = 0
      ai.known_foe_moves(b).each { |m| status_count += 1 if m.statusMove? }
      foe_has_status_moves = true if status_count >= 2
    end

    survives_move = proc { |m_id|
      s_val = true
      ai.each_foe_battler(ai.user.side) do |fb, _|
        if !ai.reserve_status_move_survives?(idxBattler, pkmn, fb, m_id)
          s_val = false
          break
        end
      end
      s_val
    }

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
          next unless survives_move.call(m.id)
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
          next unless survives_move.call(m.id)
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

    # Taunt vs status-heavy foe
    if foe_has_status_moves
      pkmn.moves.each do |m|
        if m.function_code == "DisableTargetStatusMoves"
          next unless survives_move.call(m.id)
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
          next unless survives_move.call(m.id)
          score += 10
          PBDebug.log_score_change(10, "Utility: Brick Break vs screens")
          break
        end
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
