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

    if hp_ratio > 0.6
      score -= 100
      PBDebug.log_score_change(
        -100,
        "ITEM AI: HP is healthy (>60%), healing discouraged."
      )
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
      score -= 40
      PBDebug.log_score_change(
        -40,
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

