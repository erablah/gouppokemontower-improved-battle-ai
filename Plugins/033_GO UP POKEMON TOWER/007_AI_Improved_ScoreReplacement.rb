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
      # Check whether this foe has already acted this turn
      foe_already_acted = b.battler.movedThisRound?

      # Collect all known damaging moves (filtered by fog of war)
      known_damaging = ai.known_foe_moves(b).select { |m| m&.damagingMove? }
      next if known_damaging.empty?

      # Evaluate worst-case damage across all known damaging moves
      worst_damage = 0
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
          worst_move_priority = sim_move.priority
        end
      end

      worst_damage += ai.calculate_entry_hazard_damage(pkmn, idxBattler & 1)
      dmg_ratio = (worst_damage / pkmn.hp.to_f) * 100

      base_boost = 20
      # If the foe hasn't acted yet, they can still attack the switch-in → higher penalty
      # If the foe already acted, the switch-in is safe this turn → lower penalty
      base_penalty = foe_already_acted ? 40 : 100

      # Speed-aware penalty reduction
      # Priority moves bypass speed — no reduction if foe's best move has priority
      pkmn_faster = false
      if worst_move_priority <= 0
        foe_speed = b.rough_stat(:SPEED)
        eff_speed = pkmn.speed
        # Sticky Web: -1 Speed stage on switch-in for grounded Pokémon
        if ai.user.pbOwnSide.effects[PBEffects::StickyWeb] &&
           !pkmn.hasItem?(:HEAVYDUTYBOOTS) && !ai.pokemon_airborne?(pkmn)
          eff_speed = (eff_speed * 2 / 3.0).to_i
        end
        pkmn_faster = eff_speed > foe_speed
      end

      if dmg_ratio >= 100
        # OHKO — full penalty, reduced if pkmn is faster (gets to act first)
        penalty = base_penalty
        if pkmn_faster
          penalty = (base_penalty * 0.8).to_i
        end
        score -= penalty
        spd_tag = pkmn_faster ? ", but im faster" : "im slower"
        spd_tag = ", priority" if worst_move_priority > 0
        PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: foe can OHKO (#{dmg_ratio}% >= 100%#{spd_tag})")
      elsif dmg_ratio >= 50
        # 2HKO — reduced penalty; further reduced if pkmn is faster
        # If pkmn is faster, the switch-in moves first next turn before
        # the foe's second hit, so penalty is softened
        if pkmn_faster
          penalty = (base_penalty * 0.5 * (dmg_ratio / 100.0)).to_i
        else
          penalty = base_penalty
        end
        score -= penalty
        spd_tag = pkmn_faster ? ", but im faster" : "im slower"
        spd_tag = ", with priority" if worst_move_priority > 0
        PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: foe can 2HKO (#{dmg_ratio}%#{spd_tag})")
      else
        score += (base_boost * (100 - dmg_ratio) / 100).to_i
        PBDebug.log_score_change(score - prev_score, "#{pkmn.name}: foe cannot 2HKO, +#{dmg_ratio}% < 50%")
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
    ai.each_foe_battler(ai.user.side) do |b, _i|
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
    next score
  }
)

#===============================================================================
# [NEW] Tank foe's best move: prefer replacements that take less damage from
# the foe's strongest move against the current battler
#===============================================================================
Battle::AI::Handlers::ScoreReplacement.add(:tank_foe_best_move,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    # Skip when current battler is fainted — no baseline to compare against
    next score if ai.user.battler.fainted?
    ai.each_foe_battler(ai.user.side) do |b, _i|
      # Find the foe's strongest move against the current active battler
      best_vs_current = ai.damage_moves(b, ai.user).values.max_by { |md| md[:dmg] }
      next unless best_vs_current
      next if best_vs_current[:dmg] <= 0

      current_dmg = best_vs_current[:dmg]
      best_move_id = best_vs_current[:move].id

      # Simulate that same move against the replacement candidate
      sim_move = Battle::Move.from_pokemon_move(battle, Pokemon::Move.new(best_move_id))
      target   = Battle::AI::AIBattler.new(ai, idxBattler)
      ai_move  = Battle::AI::AIMove.new(ai)
      ai_move.set_up(sim_move)
      replacement_dmg = ai_move.predicted_damage(user: b, target: target, target_pokemon: pkmn)

      # Bonus if replacement takes less damage than the current battler
      if replacement_dmg < current_dmg
        ratio = 1.0 - (replacement_dmg.to_f / current_dmg.to_f)
        bonus = (20 * ratio).round
        if bonus > 0
          score += bonus
          PBDebug.log_score_change(bonus,
            "#{pkmn.name}: tanks #{b.name}'s best move better " \
            "(#{replacement_dmg} vs #{current_dmg} on current).")
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

