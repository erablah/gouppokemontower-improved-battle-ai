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
    #    Items execute BEFORE moves, so: AI heals → foe attacks (this turn)
    #    Next turn: whoever is faster acts first
    # -------------------------------------------------------------------------
    PBDebug.log_ai("[item_ai] idxPkmn=#{idxPkmn.inspect}, battler.pokemonIndex=#{battler.pokemonIndex}")
    if idxPkmn == battler.pokemonIndex
      max_foe_dmg = 0
      foe_outspeeds = false
      user_speed = user_ai.rough_stat(:SPEED)
      ai.each_foe_battler(user_ai.side) do |b, _i|
        foe_moves = ai.damage_moves(b, user_ai).values
        best_move = foe_moves.max_by { |md| md[:dmg] }
        dmg = best_move ? best_move[:dmg] : 0
        if dmg > max_foe_dmg
          max_foe_dmg = dmg
          # Re-evaluate speed based on the worst-case foe
          foe_speed = b.rough_stat(:SPEED)
          PBDebug.log_ai("[item_ai] foe #{b.name}: max_dmg=#{dmg}, foe_speed=#{foe_speed}, user_speed=#{user_speed}")
          foe_outspeeds = foe_speed > user_speed
          # Priority on the threatening move overrides speed
          if best_move && best_move[:move].priority > 0
            foe_outspeeds = true
            PBDebug.log_ai("[item_ai] foe #{b.name} best move has priority — treating as outspeeds")
          end
        end
      end

      dmg_ratio = max_foe_dmg.to_f / pkmn.totalhp
      PBDebug.log_ai("[item_ai] max_foe_dmg=#{max_foe_dmg}, totalhp=#{pkmn.totalhp}, dmg%=#{(dmg_ratio * 100).to_i}%, foe_outspeeds=#{foe_outspeeds}")

      # Sturdy at full HP survives any single OHKO → downgrade to 2HKO scenario
      has_sturdy = user_ai.has_active_ability?(:STURDY) && pkmn.hp == pkmn.totalhp
      PBDebug.log_ai("[item_ai] Sturdy active at full HP: #{has_sturdy}") if has_sturdy

      if dmg_ratio >= 1.0 && !has_sturdy
        # --- Scenario 1: OHKO from full (no Sturdy) ---
        # AI heals to full → foe OHKOs this same turn → item wasted
        # Speed is irrelevant: items execute before moves, but foe still attacks this turn
        score -= 200
        PBDebug.log_score_change(-200, "ITEM AI: Healing futile [OHKO] — foe deals #{(dmg_ratio * 100).to_i}% per hit, item wasted regardless of speed.")
        next score
      elsif dmg_ratio >= 0.5
        # --- Scenario 2: 2HKO from full (or OHKO with Sturdy) ---
        if foe_outspeeds
          # 2a: Foe outspeeds or has priority
          # AI heals → foe hits (~50%+) → next turn foe goes first → KO
          # All items are wasted
          score -= 150
          PBDebug.log_score_change(-150, "ITEM AI: Healing futile [2HKO+outsped] — foe deals #{(dmg_ratio * 100).to_i}% and outspeeds, item wasted.")
          next score
        elsif is_healing_item
          # 2b: AI is faster, healing items only
          # Healing is questionable since foe still chunks ~50%+ per hit,
          # but AI gets to act first next turn (attack/switch/heal again)
          score -= 50
          PBDebug.log_score_change(-50, "ITEM AI: Healing questionable [2HKO+faster] — foe deals #{(dmg_ratio * 100).to_i}% but AI acts first next turn.")
        end
        # Non-healing items (stat boosters, status cures) in 2b: no penalty
      end
      # Scenario 3: Below 2HKO — no damage-threat penalty
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

