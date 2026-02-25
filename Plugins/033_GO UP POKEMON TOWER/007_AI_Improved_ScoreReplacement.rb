#===============================================================================
# ScoreReplacement Handlers
#===============================================================================

Battle::AI::Handlers::ScoreReplacement.add(:entry_hazards,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    entry_hazard_damage = ai.calculate_entry_hazard_damage(pkmn, idxBattler & 1)
    if entry_hazard_damage >= pkmn.hp
      score -= 50   # pkmn will just faint
    elsif entry_hazard_damage > 0
      score -= 50 * entry_hazard_damage / pkmn.hp
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:toxics_spikes_and_sticky_web,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    if !pkmn.hasItem?(:HEAVYDUTYBOOTS) && !ai.pokemon_airborne?(pkmn)
      # Toxic Spikes
      if ai.user.pbOwnSide.effects[PBEffects::ToxicSpikes] > 0
        score -= 20 if ai.pokemon_can_be_poisoned?(pkmn)
      end
      # Sticky Web
      if ai.user.pbOwnSide.effects[PBEffects::StickyWeb]
        score -= 15
      end
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:foe_predicted_damage,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    # Predict effectiveness of foe's last used move against pkmn
    ai.each_foe_battler(ai.user.side) do |b, i|
      next if !b.battler.lastMoveUsed
      move_data = GameData::Move.try_get(b.battler.lastMoveUsed)
      next if !move_data || move_data.status?

      user = Battle::AI::AIBattler.new(ai, idxBattler)
      move = Battle::AI::AIMove.new(ai)
      m = Battle::Move.from_pokemon_move(battle, Pokemon::Move.new(b.battler.lastMoveUsed))
      move.set_up(m)
      predicted_damage = move.predicted_damage(move: move, user: b, target: user)

      PBDebug.log("foe.lastMoveUsed: #{b.battler.lastMoveUsed}")
      PBDebug.log("#{pkmn.name} predicted_damage: #{predicted_damage}")

      half_hp = pkmn.hp.to_f / 2.0
      if predicted_damage >= half_hp
        score -= 100
      else
        penalty = (100.0 * (predicted_damage / half_hp)).round
        score -= penalty
      end
    end
    next score
  }
)

Battle::AI::Handlers::ScoreReplacement.add(:user_predicted_damage,
  proc { |idxBattler, pkmn, score, terrible_moves, battle, ai|
    # Add predicted damage of all pkmn's moves to score (if there is an opposing active battler)
    pkmn.moves.each do |m|
      next if m.power == 0 || (m.pp == 0 && m.total_pp > 0)
      ai.each_foe_battler(ai.user.side) do |b, i|
        next if ai.pokemon_can_absorb_move?(b.pokemon, m, m.type)

        user = Battle::AI::AIBattler.new(ai, idxBattler)
        move = Battle::AI::AIMove.new(ai)
        simulated_move = Battle::Move.from_pokemon_move(battle, m)
        move.set_up(simulated_move)
        predicted_damage = move.predicted_damage(move: move, user: user, target: b)
        PBDebug.log("#{pkmn.name} predicted_damage: #{predicted_damage}")
        
        score += predicted_damage / 10  
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
