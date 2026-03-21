#===============================================================================
# ScoreReplacement Handlers
#===============================================================================

Battle::AI::Handlers::ScoreReplacement.add(:entry_hazards,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
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
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
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
# 1v1 Matchup Evaluation
# Computes both foe's worst-case damage vs reserve AND reserve's best damage
# vs foe, then scores via one_v_one_result.
# Scenario 1 (pending first hit) is handled separately due to asymmetric
# first-hit prediction; scenarios 2 & 3 use the standard 1v1 method.
#===============================================================================
Battle::AI::Handlers::ScoreReplacement.add(:one_v_one_matchup,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    prev_score = score
    ai.each_foe_battler(ai.user.side) do |b, i|
      # Determine scenario:
      #   Scenario 1: Command phase, foe has NOT acted yet — hit is imminent
      #   Scenario 2: Command phase, foe HAS acted — safe this turn
      #   Scenario 3: Faint replacement (not command phase) — foe gets fresh turn
      faint_replacement = !battle.command_phase
      foe_already_acted = battle.command_phase && b.battler.movedThisRound?

      # --- Foe's worst-case damage vs reserve ---
      known_damaging = ai.known_foe_moves(b).select { |m| m&.damagingMove? && b.battler.pbCanChooseMove?(m, false, false) }
      next if known_damaging.empty?

      worst_damage = 0
      worst_move_id = nil
      worst_move_priority = 0
      known_damaging.each do |m|
        PBDebug.log_ai("move_id: #{m.id}")
        sim_move = Battle::Move.from_pokemon_move(battle, Pokemon::Move.new(m.id))
        target = Battle::AI::AIBattler.new(ai, idxBattler)
        move = Battle::AI::AIMove.new(ai)
        move.set_up(sim_move)
        predicted_damage = move.predicted_damage(user: b, target: target, target_pokemon: pkmn)
        if predicted_damage > worst_damage
          worst_damage = predicted_damage
          worst_move_id = m.id
          worst_move_priority = sim_move.priority
        end
      end

      entry_hazard_damage = ai.calculate_entry_hazard_damage(pkmn, idxBattler & 1)

      # --- Reserve's best damage vs foe ---
      best_user_damage = 0
      best_move_name = ""
      best_move_priority = 0
      pkmn.moves.each do |m|
        next if m.power == 0 || (m.pp == 0 && m.total_pp > 0)
        next if ai.pokemon_can_absorb_move?(b.pokemon, m, m.type)
        user = Battle::AI::AIBattler.new(ai, idxBattler)
        move = Battle::AI::AIMove.new(ai)
        simulated_move = Battle::Move.from_pokemon_move(battle, m)
        move.set_up(simulated_move)
        predicted_damage = move.predicted_damage(user: user, target: b, user_pokemon: pkmn)
        if predicted_damage > best_user_damage
          best_user_damage = predicted_damage
          best_move_name = m.name
          best_move_priority = simulated_move.priority
        end
      end

      # --- Per-turn item effects (Leftovers/Black Sludge/Life Orb) ---
      user_heal = 0
      user_self_dmg = 0
      if pkmn.hasItem?(:LEFTOVERS) ||
         (pkmn.hasItem?(:BLACKSLUDGE) && pkmn.types.include?(:POISON))
        user_heal = (pkmn.totalhp / 16.0).floor
      end
      if pkmn.hasItem?(:LIFEORB) && !pkmn.hasAbility?(:MAGICGUARD)
        user_self_dmg = (pkmn.totalhp / 10.0).floor
      end

      foe_heal = 0
      foe_self_dmg = 0
      if b.has_active_item?(:LEFTOVERS) ||
         (b.has_active_item?(:BLACKSLUDGE) && b.has_type?(:POISON))
        foe_heal = (b.totalhp / 16.0).floor
      end
      if b.has_active_item?(:LIFEORB) && !b.has_active_ability?(:MAGICGUARD)
        foe_self_dmg = (b.totalhp / 10.0).floor
      end

      # Priority bracket comparison: reserve's best move vs foe's worst move
      if best_move_priority > worst_move_priority
        pkmn_faster = true
      elsif worst_move_priority > best_move_priority
        pkmn_faster = false
      else
        pkmn_faster = ai.reserve_outspeeds_foe?(pkmn, b)
      end

      # --- Scenario 1: First-hit prediction logic ---
      # Asymmetric first hit (first_hit_dmg ≠ subsequent_hit_dmg) due to move
      # prediction, so one_v_one_result doesn't apply to the first hit.
      scenario_1 = battle.command_phase && !foe_already_acted && !ai.user.battler.fainted?
      if scenario_1
        foe_vs_current = ai.damage_moves(b, ai.user)
        best_vs_current = foe_vs_current.values.max_by { |md| md[:dmg] }

        if best_vs_current && best_vs_current[:dmg] > 0 && worst_move_id
          move_C_id = best_vs_current[:move].id   # worst move vs current
          move_R_id = worst_move_id                # worst move vs replacement

          if move_C_id == move_R_id
            first_hit_dmg = worst_damage + entry_hazard_damage
            PBDebug.log_ai("  [Scenario1] #{pkmn.name} vs #{b.name}: same worst move (#{move_C_id}), first_hit=#{first_hit_dmg}")
          else
            dmg_A = best_vs_current[:dmg]
            move_R_vs_current = foe_vs_current[move_R_id]
            dmg_B = move_R_vs_current ? move_R_vs_current[:dmg] : 0

            ratio = dmg_B.to_f / [dmg_A, 1].max
            chance = 1.0 - 0.8 * (ratio ** 3)
            chance = [[chance, 0.2].max, 1.0].min

            summary = ai.matchup_summary
            roll = summary[:foes][b.index][:switch_prediction_roll]

            if roll < (chance * 100).to_i
              sim_move = Battle::Move.from_pokemon_move(battle, Pokemon::Move.new(move_C_id))
              target = Battle::AI::AIBattler.new(ai, idxBattler)
              ai_move = Battle::AI::AIMove.new(ai)
              ai_move.set_up(sim_move)
              first_hit_dmg = ai_move.predicted_damage(user: b, target: target, target_pokemon: pkmn)
              first_hit_dmg += entry_hazard_damage
              PBDebug.log_ai("  [Scenario1] #{pkmn.name} vs #{b.name}: predicted move_C=#{move_C_id} (chance=#{(chance*100).to_i}%, roll=#{roll}), first_hit=#{first_hit_dmg}")
            else
              first_hit_dmg = worst_damage + entry_hazard_damage
              PBDebug.log_ai("  [Scenario1] #{pkmn.name} vs #{b.name}: predicted move_R=#{move_R_id} (chance=#{(chance*100).to_i}%, roll=#{roll}), first_hit=#{first_hit_dmg}")
            end
          end

          remaining_hp = pkmn.hp - first_hit_dmg

          if remaining_hp <= 0
            # Reserve dies on entry — only extreme score in the system
            score -= 100
            PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: Scenario1 instant death (first_hit=#{first_hit_dmg}/#{pkmn.hp}hp)")
          else
            # 1v1 from remaining HP (subsequent turns use worst_damage, no hazards)
            result = ai.one_v_one_result(
              user_dmg: best_user_damage, foe_dmg: worst_damage,
              user_hp: remaining_hp, foe_hp: b.hp, user_outspeeds: pkmn_faster,
              user_heal_per_turn: user_heal, user_self_dmg_per_turn: user_self_dmg,
              foe_heal_per_turn: foe_heal, foe_self_dmg_per_turn: foe_self_dmg
            )
            turn_advantage = result[:f_turns] - result[:u_turns]
            user_dmg_ratio = best_user_damage.to_f / [b.hp, 1].max
            foe_dmg_ratio  = result[:dmg_ratio]

            if result[:user_wins]
              bonus = 5 + [turn_advantage * 5, 10].min + [user_dmg_ratio * 10, 10].min.to_i
              score += bonus
              PBDebug.log_score_change(bonus, "#{pkmn.name}: Scenario1 wins 1v1 (turns=#{result[:u_turns]}v#{result[:f_turns]}, user_dmg=#{best_user_damage}/#{b.hp}hp, remaining_hp=#{remaining_hp}/#{pkmn.hp})")
            else
              penalty = [foe_dmg_ratio * 25, 25].min.to_i
              penalty += 25 if result[:foe_can_ohko] && !pkmn_faster
              score -= penalty
              spd_tag = pkmn_faster ? "faster" : "slower"
              PBDebug.log_score_change(-penalty, "#{pkmn.name}: Scenario1 loses 1v1 (foe_dmg=#{worst_damage}/#{remaining_hp}hp, #{spd_tag}, remaining_hp=#{remaining_hp}/#{pkmn.hp})")
            end
          end
          next  # done with this foe for Scenario 1
        end
        # Fallback: if damage_moves returned no data, fall through to standard logic
      end

      # --- Scenarios 2 & 3 (and Scenario 1 fallback): 1v1 evaluation ---
      worst_damage_with_hazards = worst_damage + entry_hazard_damage
      result = ai.one_v_one_result(
        user_dmg: best_user_damage, foe_dmg: worst_damage_with_hazards,
        user_hp: pkmn.hp, foe_hp: b.hp, user_outspeeds: pkmn_faster,
        user_heal_per_turn: user_heal, user_self_dmg_per_turn: user_self_dmg,
        foe_heal_per_turn: foe_heal, foe_self_dmg_per_turn: foe_self_dmg
      )

      spd_tag = pkmn_faster ? "faster" : "slower"
      scenario_tag = faint_replacement ? "faint_repl" : "foe_acted"
      turn_advantage = result[:f_turns] - result[:u_turns]
      user_dmg_ratio = best_user_damage.to_f / [b.hp, 1].max
      foe_dmg_ratio  = result[:dmg_ratio]

      if result[:user_wins]
        bonus = 5 + [turn_advantage * 5, 10].min + [user_dmg_ratio * 10, 10].min.to_i
        score += bonus
        PBDebug.log_score_change(bonus, "#{pkmn.name}: wins 1v1 (turns=#{result[:u_turns]}v#{result[:f_turns]}, user_dmg=#{best_user_damage}/#{b.hp}hp, #{spd_tag}, #{scenario_tag})")
      else
        penalty = [foe_dmg_ratio * 25, 25].min.to_i
        penalty += 25 if result[:foe_can_ohko] && !pkmn_faster
        score -= penalty
        PBDebug.log_score_change(-penalty, "#{pkmn.name}: loses 1v1 (foe_dmg=#{worst_damage_with_hazards}/#{pkmn.hp}hp, #{spd_tag}, #{scenario_tag})")
      end
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:wish_healing,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    # Prefer if pkmn has lower HP and its position will be healed by Wish
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
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    # Prefer if user is about to faint from Perish Song
    score += 20 if ai.user.effects[PBEffects::PerishSong] == 1
    next score
  }
)

#===============================================================================
# [NEW] Utility Switch-In: Prefer Pokémon with situationally useful moves/abilities
# A strong player switches into utility Pokémon that can answer the current threat.
#===============================================================================
Battle::AI::Handlers::ScoreReplacement.add(:utility_switch_in,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    # Check foe's current state
    foe_total_boosts = 0
    foe_has_screens = false
    foe_has_status_moves = false

    ai.each_foe_battler(ai.user.side) do |b, i|
      # Count foe stat boosts
      GameData::Stat.each_battle do |s|
        foe_total_boosts += b.stages[s.id] if b.stages[s.id] > 0
      end
      # Check screens on foe's side
      foe_side = b.pbOwnSide
      foe_has_screens = true if foe_side.effects[PBEffects::Reflect] > 0 ||
                                 foe_side.effects[PBEffects::LightScreen] > 0 ||
                                 foe_side.effects[PBEffects::AuroraVeil] > 0
      # Check if foe relies on status moves
      status_count = 0
      ai.known_foe_moves(b).each { |m| status_count += 1 if m.statusMove? }
      foe_has_status_moves = true if status_count >= 2
    end

    # --- Unaware vs boosted foe ---
    if foe_total_boosts >= 2 && pkmn.hasAbility?(:UNAWARE)
      bonus = 25 + (foe_total_boosts * 3)
      score += bonus
      PBDebug.log_score_change(bonus, "Utility: Unaware vs +#{foe_total_boosts} boosts")
    end

    # --- Haze / Clear Smog vs boosted foe ---
    if foe_total_boosts >= 2
      pkmn.moves.each do |m|
        if ["ResetAllBattlersStatStages", "ResetTargetStatStages"].include?(m.function_code)
          bonus = 20 + (foe_total_boosts * 2)
          score += bonus
          PBDebug.log_score_change(bonus, "Utility: #{m.name} vs +#{foe_total_boosts} boosts")
          break
        end
      end
    end

    # --- Whirlwind / Roar / Dragon Tail vs boosted foe ---
    if foe_total_boosts >= 2
      pkmn.moves.each do |m|
        if ["SwitchOutTargetStatusMove", "SwitchOutTargetDamagingMove"].include?(m.function_code)
          bonus = 20 + (foe_total_boosts * 2)
          # Extra synergy if hazards are up on foe's side
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

    # --- Taunt vs status-heavy foe ---
    if foe_has_status_moves
      pkmn.moves.each do |m|
        if m.function_code == "DisableTargetStatusMoves"
          score += 10
          PBDebug.log_score_change(10, "Utility: Taunt vs status-heavy foe")
          break
        end
      end
    end

    # --- Brick Break vs screens/substitute ---
    if foe_has_screens
      pkmn.moves.each do |m|
        if m.function_code == "RemoveScreens"
          bonus = foe_has_screens ? 10 : 5
          score += bonus
          PBDebug.log_score_change(bonus, "Utility: Brick Break vs screens")
          break
        end
      end
    end

    next score
  }
)

#===============================================================================
# [NEW] Status Moves Value: Reward Pokémon with useful status moves vs current foe
# E.g. Thunder Wave vs fast sweeper, Will-O-Wisp vs physical attacker
#===============================================================================
Battle::AI::Handlers::ScoreReplacement.add(:status_moves_value,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    # Create a temporary battler for the reserve so ability checks work (e.g. Corrosion)
    temp_user = Battle::Battler.new(battle, idxBattler)
    temp_user.pbInitialize(pkmn, 0)

    ai.each_foe_battler(ai.user.side) do |b, i|
      foe_speed = b.rough_stat(:SPEED)
      foe_is_physical = b.check_for_move { |m| m.physicalMove? }

      pkmn.moves.each do |m|
        next unless m.status_move?
        next if m.pp == 0 && m.total_pp > 0

        case m.function_code
        when "ParalyzeTarget"
          # Thunder Wave vs fast sweeper
          if foe_speed >= 100 && b.battler.pbCanParalyze?(temp_user, false)
            score += 8
            PBDebug.log_score_change(8, "Status value: #{m.name} vs fast foe (spd=#{foe_speed})")
          end
        when "BurnTarget"
          # Will-O-Wisp vs physical attacker
          if foe_is_physical && b.battler.pbCanBurn?(temp_user, false)
            score += 8
            PBDebug.log_score_change(8, "Status value: #{m.name} vs physical foe")
          end
        when "PoisonTarget", "BadPoisonTarget"
          # Toxic vs bulky foe
          if b.hp >= b.totalhp * 0.7 && b.battler.pbCanPoison?(temp_user, false)
            score += 5
            PBDebug.log_score_change(5, "Status value: #{m.name} vs healthy foe")
          end
        end
      end
    end
    next score
  }
)

#===============================================================================
# [NEW] Speed advantage: prefer replacement that outspeeds the foe
#===============================================================================
Battle::AI::Handlers::ScoreReplacement.add(:speed_advantage,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    ai.each_foe_battler(ai.user.side) do |b, _i|
      if ai.reserve_outspeeds_foe?(pkmn, b)
        score += 8
        PBDebug.log_score_change(8, "#{pkmn.name}: outspeeds #{b.name}.")
        break
      end
    end
    next score
  }
)

#===============================================================================
# [NEW] Intimidate Switch-In: Boost for switching in a Pokémon with Intimidate
# when the foe relies on physical attacks. Kept conservative to avoid
# over-valuing Intimidate against mixed or special attackers.
#===============================================================================
Battle::AI::Handlers::ScoreReplacement.add(:intimidate_switch_in,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    next score unless pkmn.hasAbility?(:INTIMIDATE)
    ai.each_foe_battler(ai.user.side) do |b, _i|
      # Skip if foe is immune to Intimidate
      next if b.battler.hasActiveAbility?(Battle::AI::AIMove::INTIMIDATE_IMMUNE)
      next if battle.moldBreaker
      # Skip if foe's Attack is already at -6
      next if b.stages[:ATTACK] <= -6
      # Count physical vs special damaging moves
      phys_count = 0
      spec_count = 0
      ai.known_foe_moves(b).each do |m|
        next unless m&.damagingMove?
        phys_count += 1 if m.physicalMove?
        spec_count += 1 if m.specialMove?
      end
      next if phys_count == 0
      # Bonus scales with how physical the foe is (max +12 for pure physical)
      phys_ratio = phys_count.to_f / (phys_count + spec_count)
      bonus = (12 * phys_ratio).round
      # Smaller bonus if foe already has lowered Attack
      bonus = (bonus * 0.5).round if b.stages[:ATTACK] < 0
      if bonus > 0
        score += bonus
        PBDebug.log_score_change(bonus, "#{pkmn.name}: Intimidate vs #{b.name} (#{phys_count} phys moves)")
      end
    end
    next score
  }
)

