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
# [REWRITE] Multi-Move Prediction for Foe Damage
# Evaluate worst-case predicted damage.
#===============================================================================
Battle::AI::Handlers::ScoreReplacement.add(:foe_predicted_damage,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    prev_score = score
    ai.each_foe_battler(ai.user.side) do |b, i|
      # Determine scenario:
      #   Scenario 1: Command phase, foe has NOT acted yet — hit is imminent
      #   Scenario 2: Command phase, foe HAS acted — safe this turn
      #   Scenario 3: Faint replacement (not command phase) — foe gets fresh turn
      faint_replacement = !battle.command_phase
      foe_already_acted = battle.command_phase && b.battler.movedThisRound?

      # Collect all known damaging moves (filtered by fog of war)
      known_damaging = ai.known_foe_moves(b).select { |m| m&.damagingMove? }
      next if known_damaging.empty?

      # Evaluate worst-case damage across all known damaging moves vs replacement
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

      # Speed check (used by all scenarios)
      pkmn_faster = false
      if worst_move_priority <= 0
        pkmn_lagging = LAGGING_TAIL_ITEMS.include?(pkmn.item_id)
        foe_lagging  = LAGGING_TAIL_ITEMS.include?(b.battler.item_id) && b.battler.itemActive?
        if pkmn_lagging && !foe_lagging
          pkmn_faster = false
        elsif foe_lagging && !pkmn_lagging
          pkmn_faster = true
        else
          foe_speed = b.rough_stat(:SPEED)
          eff_speed = pkmn.speed
          if ai.user.pbOwnSide.effects[PBEffects::StickyWeb] &&
             !pkmn.hasItem?(:HEAVYDUTYBOOTS) && !ai.pokemon_airborne?(pkmn)
            eff_speed = (eff_speed * 2 / 3.0).to_i
          end
          pkmn_faster = eff_speed > foe_speed
        end
      end

      # --- Scenario 1: First-hit prediction logic ---
      scenario_1 = battle.command_phase && !foe_already_acted && !ai.user.battler.fainted?
      if scenario_1
        # Get foe's worst move vs current battler
        foe_vs_current = ai.damage_moves(b, ai.user)
        best_vs_current = foe_vs_current.values.max_by { |md| md[:dmg] }

        if best_vs_current && best_vs_current[:dmg] > 0 && worst_move_id
          move_C_id = best_vs_current[:move].id   # worst move vs current
          move_R_id = worst_move_id                # worst move vs replacement

          if move_C_id == move_R_id
            # Same move is worst for both — no prediction needed
            first_hit_dmg = worst_damage + entry_hazard_damage
            first_hit_priority = worst_move_priority
            PBDebug.log_ai("  [Scenario1] #{pkmn.name} vs #{b.name}: same worst move (#{move_C_id}), first_hit=#{first_hit_dmg}")
          else
            # Different worst moves — compute prediction probability
            dmg_A = best_vs_current[:dmg]  # move_C damage to current
            # Look up move_R damage to current
            move_R_vs_current = foe_vs_current[move_R_id]
            dmg_B = move_R_vs_current ? move_R_vs_current[:dmg] : 0

            # chance = probability foe uses move_C (the one targeting current)
            # Higher when move_R does little damage to current (foe wouldn't pick it)
            # Uses cubic ratio so chance stays high until move_R is nearly as good
            ratio = dmg_B.to_f / [dmg_A, 1].max
            chance = 1.0 - 0.8 * (ratio ** 3)
            chance = [[chance, 0.2].max, 1.0].min

            # Get cached roll from matchup_summary
            summary = ai.matchup_summary
            roll = summary[:foes][b.index][:switch_prediction_roll]

            if roll < (chance * 100).to_i
              # Foe uses move_C (targeting current) — simulate on replacement
              sim_move = Battle::Move.from_pokemon_move(battle, Pokemon::Move.new(move_C_id))
              target = Battle::AI::AIBattler.new(ai, idxBattler)
              ai_move = Battle::AI::AIMove.new(ai)
              ai_move.set_up(sim_move)
              first_hit_dmg = ai_move.predicted_damage(user: b, target: target, target_pokemon: pkmn)
              first_hit_dmg += entry_hazard_damage
              first_hit_priority = sim_move.priority
              PBDebug.log_ai("  [Scenario1] #{pkmn.name} vs #{b.name}: predicted move_C=#{move_C_id} (chance=#{(chance*100).to_i}%, roll=#{roll}), first_hit=#{first_hit_dmg}")
            else
              # Foe predicted the switch — uses move_R (worst vs replacement)
              first_hit_dmg = worst_damage + entry_hazard_damage
              first_hit_priority = worst_move_priority
              PBDebug.log_ai("  [Scenario1] #{pkmn.name} vs #{b.name}: predicted move_R=#{move_R_id} (chance=#{(chance*100).to_i}%, roll=#{roll}), first_hit=#{first_hit_dmg}")
            end
          end

          subsequent_hit_dmg = worst_damage  # no hazards — already switched in
          dmg_priority = first_hit_priority

          # Evaluate OHKO/2HKO
          if first_hit_dmg >= pkmn.hp
            score -= 100
            PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: Scenario1 OHKO (first_hit=#{first_hit_dmg}/#{pkmn.hp}hp, foe_pending)")
          elsif first_hit_dmg + subsequent_hit_dmg >= pkmn.hp
            # 2HKO: If pkmn is faster, it gets to attack first on turn 2 — reduced penalty
            penalty = pkmn_faster ? 40 : 100
            spd_tag = pkmn_faster ? "faster" : "slower"
            score -= penalty
            PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: Scenario1 2HKO (first=#{first_hit_dmg}+subsequent=#{subsequent_hit_dmg}=#{first_hit_dmg+subsequent_hit_dmg}/#{pkmn.hp}hp, #{spd_tag})")
          else
            # Below 2HKO — ongoing threat bonus based on subsequent hit ratio
            dmg_ratio = (subsequent_hit_dmg / pkmn.hp.to_f) * 100
            base_boost = 20
            score += (base_boost * (100 - dmg_ratio) / 100).to_i
            PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: Scenario1 below 2HKO, subsequent #{dmg_ratio.to_i}% (first=#{first_hit_dmg}, sub=#{subsequent_hit_dmg})")
          end
          next  # done with this foe for Scenario 1
        end
        # Fallback: if damage_moves returned no data, fall through to standard logic
      end

      # --- Scenarios 2 & 3 (and Scenario 1 fallback): all hits use worst_damage ---
      worst_damage_with_hazards = worst_damage + entry_hazard_damage
      dmg_ratio = (worst_damage_with_hazards / pkmn.hp.to_f) * 100

      base_boost = 20

      if dmg_ratio >= 100
        # === OHKO ===
        # Scenario 2 & 3: Foe attacks next turn
        penalty = pkmn_faster ? 40 : 100
        score -= penalty
        spd_tag = pkmn_faster ? ", faster" : ", slower"
        spd_tag = ", priority" if worst_move_priority > 0
        scenario_tag = faint_replacement ? "faint_repl" : "foe_acted"
        PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: foe can OHKO (#{dmg_ratio.to_i}%#{spd_tag}, #{scenario_tag})")
      elsif dmg_ratio >= 50
        # === 2HKO ===
        # Scenario 2 & 3: Foe attacks next turn
        base = pkmn_faster ? 20 : 40
        penalty = (base * (dmg_ratio / 100.0)).to_i
        score -= penalty
        spd_tag = pkmn_faster ? ", faster" : ", slower"
        spd_tag = ", priority" if worst_move_priority > 0
        scenario_tag = faint_replacement ? "faint_repl" : "foe_acted"
        PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: foe can 2HKO (#{dmg_ratio.to_i}%#{spd_tag}, #{scenario_tag})")
      else
        score += (base_boost * (100 - dmg_ratio) / 100).to_i
        PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: foe cannot 2HKO, #{dmg_ratio.to_i}% < 50%")
      end
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:user_predicted_damage,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    # Add predicted damage of best pkmn's moves to score (if there is an opposing active battler)
    max_predicted_damage = 0
    max_foe_hp = 1  # tracks HP of the foe that takes the most damage (doubles-safe)
    best_move_name = ""
    pkmn.moves.each do |m|
      next if m.power == 0 || (m.pp == 0 && m.total_pp > 0)
      ai.each_foe_battler(ai.user.side) do |b, i|
        next if ai.pokemon_can_absorb_move?(b.pokemon, m, m.type)

        user = Battle::AI::AIBattler.new(ai, idxBattler)
        move = Battle::AI::AIMove.new(ai)
        simulated_move = Battle::Move.from_pokemon_move(battle, m)
        move.set_up(simulated_move)
        predicted_damage = move.predicted_damage(user: user, target: b, user_pokemon: pkmn)

        if predicted_damage > max_predicted_damage
          max_predicted_damage = predicted_damage
          max_foe_hp = [b.hp, 1].max
          best_move_name = m.name
        end
      end
    end
    # Scale linearly up to +30, capped at 150% of foe's current HP
    # No bonus until at least 40% HP ratio
    dmg_ratio = max_predicted_damage.to_f / max_foe_hp
    if dmg_ratio < 0.5
      bonus = 0
    else
      bonus = (30 * [dmg_ratio / 1.5, 1.0].min).round
    end
    bonus += 5 if dmg_ratio >= 1.0  # extra bonus if predicted OHKO
    PBDebug.log_score_change(bonus, "#{pkmn.name} best move: #{best_move_name}, dmg_ratio: #{(dmg_ratio * 100).round}% (#{max_predicted_damage}/#{max_foe_hp})")
    next score += bonus
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
    pkmn_lagging = LAGGING_TAIL_ITEMS.include?(pkmn.item_id)
    ai.each_foe_battler(ai.user.side) do |b, _i|
      foe_lagging = LAGGING_TAIL_ITEMS.include?(b.battler.item_id) && b.battler.itemActive?
      # Lagging Tail: holder always moves last
      if pkmn_lagging && !foe_lagging
        next  # pkmn can't outspeed
      elsif foe_lagging && !pkmn_lagging
        score += 8
        PBDebug.log_score_change(8, "#{pkmn.name}: outspeeds #{b.name} (foe has Lagging Tail).")
        break
      else
        foe_speed = b.rough_stat(:SPEED)
        eff_speed = pkmn.speed
        # Sticky Web: -1 Speed stage on switch-in for grounded Pokémon
        if ai.user.pbOwnSide.effects[PBEffects::StickyWeb] &&
           !pkmn.hasItem?(:HEAVYDUTYBOOTS) && !ai.pokemon_airborne?(pkmn)
          eff_speed = (eff_speed * 2 / 3.0).to_i
        end
        if eff_speed > foe_speed
          score += 8
          PBDebug.log_score_change(8, "#{pkmn.name}: outspeeds #{b.name} (#{eff_speed} vs #{foe_speed}).")
          break
        end
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

