#===============================================================================
# 4. GeneralItemScore Handlers
#===============================================================================

#===============================================================================
# ITEM AI SUPPORT – Ace-focused & Switch-aware Item Usage
#  - Does not modify DBK Improved Item AI directly
#  - Adjusts item usage scores to guide behavior
#===============================================================================

Battle::AI::Handlers::GeneralItemScore.add(
  :ai_improved_item_priority_control,
  proc { |score, item, idxPkmn, idxMove, ai, battle|

    user_ai  = ai.user
    battler = user_ai&.battler
    next score unless battler
    next score unless item

    party = battle.pbParty(battler.index)
    party_size = party.length
    pkmn = party[idxPkmn]

    # -------------------------------------------------------------------------
    # 2. Strongly discourage healing items when HP is healthy (green bar)
    # -------------------------------------------------------------------------
    hp_ratio = pkmn.hp.to_f / pkmn.totalhp
    is_healing_item = battle.pbItemHealsHP?(item)

    if hp_ratio > 0.6 && is_healing_item
      score -= 100
      PBDebug.log_score_change(
        -100,
        "ITEM AI: HP is healthy (>60%), healing discouraged."
      )
    end

    # -------------------------------------------------------------------------
    # 3. Scenario-based damage-threat check for active Pokémon
    #    Simulate a battle between foe and AI with AI healed to full HP.
    #    Uses sim results to decide if the item would be wasted.
    # -------------------------------------------------------------------------
    PBDebug.log_ai("[item_ai] idxPkmn=#{idxPkmn.inspect}, battler.pokemonIndex=#{battler.pokemonIndex}")
    if idxPkmn == battler.pokemonIndex
      summary = ai.matchup_summary
      worst_penalty = 0
      worst_reason = nil

      summary[:foes].each do |foe_idx, foe|
        foe_best_move = foe[:best_move]
        next unless foe_best_move
        user_best = foe[:move_results]&.keys&.first
        next unless user_best

        # Simulate: AI at full HP vs foe using best moves
        sim_result = ai.simulate_battle(
          battler.index, foe_idx,
          [user_best], [foe_best_move.id],
          max_turns: 10, heal_user_full: true
        )

        foe_outspeeds = foe[:effectively_outspeeds]
        PBDebug.log_ai("[item_ai] sim vs foe #{foe_idx}: user_fainted=#{sim_result.user_fainted}, target_fainted=#{sim_result.target_fainted}, foe_ohko=#{sim_result.target_can_ohko?}, foe_outspeeds=#{foe_outspeeds}")

        penalty = 0
        reason = nil

        if sim_result.target_can_ohko?
          # Foe OHKOs AI even from full HP — item is futile
          penalty = -200
          reason = "ITEM AI: Healing futile [OHKO from full] — foe KOs in 1 hit even at full HP."
        elsif sim_result.target_wins?
          if foe_outspeeds
            # Foe wins the 1v1 and outspeeds — item is wasted
            penalty = -150
            reason = "ITEM AI: Healing futile [foe wins 1v1 + outspeeds] — foe wins from full HP and acts first."
          elsif is_healing_item
            # Foe wins but AI is faster — healing is questionable
            penalty = -50
            reason = "ITEM AI: Healing questionable [foe wins 1v1 + slower] — foe wins from full HP but AI acts first."
          end
        end

        if penalty < worst_penalty
          worst_penalty = penalty
          worst_reason = reason
        end
      end

      if worst_penalty != 0
        score += worst_penalty
        PBDebug.log_score_change(worst_penalty, worst_reason)
        next score if worst_penalty <= -150
      end
    end

    can_switch = battle.pbCanChooseNonActive?(battler.index)

    # -------------------------------------------------------------------------
    # 5. Ace candidate evaluation
    # -------------------------------------------------------------------------
    ace_candidate = false

    if idxPkmn
      # Whether the Pokémon is in the late party slots
      is_late_party = (idxPkmn >= (party_size * 0.6).floor)

      # Whether the Pokémon has attacking moves
      has_attacks = false
      pkmn = party[idxPkmn]
      if pkmn && pkmn.moves
        damaging_moves = pkmn.moves.count do |m|
          m && GameData::Move.get(m.id).category != 2
        end
        has_attacks = (damaging_moves >= 2)
      end
      
      ace_candidate = is_late_party && has_attacks
    end

    # Discourage if not an ace candidate
    unless ace_candidate
      score -= 50
      PBDebug.log_score_change(
        -50,
        "ITEM AI: Non-ace Pokémon, item discouraged."
      )
    end

    # Boost if ace candidate
    if ace_candidate
      score += 30
      PBDebug.log_score_change(
        30,
        "ITEM AI: Ace Pokémon preservation priority."
      )
    end

    # -------------------------------------------------------------------------
    # 8. Cannot switch + critical HP → allow item use
    # -------------------------------------------------------------------------
    if !can_switch && battler.hp < battler.totalhp * 0.25
      score += 30
      PBDebug.log_score_change(
        30,
        "ITEM AI: Forced item (cannot switch, low HP)."
      )
    end

    next score
  }
)

