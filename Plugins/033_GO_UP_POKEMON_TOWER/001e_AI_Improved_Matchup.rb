#===============================================================================
# [AI_Improved_Matchup.rb] - Damage Caching, Matchup Analysis
# Uses actual battle simulation via deep copies.
#===============================================================================

class Battle::AI
  #---------------------------------------------------------------------------
  # Returns {move_id => {move: Battle::Move, dmg: int}}
  # Calculates damage for each of attacker's damaging moves against defender
  # using direct pbCalcDamage on a single sim copy (no full battle phases).
  # Also populates the reverse (defender→attacker) cache from the same sim.
  #---------------------------------------------------------------------------
  def damage_moves(attacker, defender)
    return {} if attacker.fainted? || defender.fainted?
    fwd_key = _dmg_cache_key(attacker, defender)
    cache = (@_ai_dmg_cache ||= {})
    return cache[fwd_key] if cache.key?(fwd_key)

    PBDebug.log_ai("[damage_moves] computing #{attacker.name} ↔ #{defender.name} (turn #{@battle.turnCount})")
    sim = create_battle_copy
    sim_a = sim.battlers[attacker.index]
    sim_b = sim.battlers[defender.index]

    # Forward: attacker → defender
    fwd = {}
    fwd_moves = (attacker.side != @user.side) ? known_foe_moves(attacker) : attacker.moves
    fwd_moves.each do |m|
      next unless m&.damagingMove?
      next unless attacker.pbCanChooseMove?(m, false, false)
      dmg = calc_move_damage(m, sim_a, sim_b, attacker, defender)
      pct_total = (100.0 * dmg / [1, defender.totalhp].max).round(1)
      pct_hp    = (100.0 * dmg / [1, defender.hp].max).round(1)
      PBDebug.log_ai("  #{attacker.name} #{m.name}: #{dmg} dmg (#{pct_total}% totalhp / #{pct_hp}% curhp)")
      fwd[m.id] = { move: m, dmg: dmg }
      tick_scene
    end
    cache[fwd_key] = fwd

    # Reverse: defender → attacker (reuse same sim)
    rev_key = _dmg_cache_key(defender, attacker)
    unless cache.key?(rev_key)
      rev = {}
      rev_moves = (defender.side != @user.side) ? known_foe_moves(defender) : defender.moves
      rev_moves.each do |m|
        next unless m&.damagingMove?
        next unless defender.pbCanChooseMove?(m, false, false)
        dmg = calc_move_damage(m, sim_b, sim_a, defender, attacker)
        pct_total = (100.0 * dmg / [1, attacker.totalhp].max).round(1)
        pct_hp    = (100.0 * dmg / [1, attacker.hp].max).round(1)
        PBDebug.log_ai("  #{defender.name} #{m.name}: #{dmg} dmg (#{pct_total}% totalhp / #{pct_hp}% curhp)")
        rev[m.id] = { move: m, dmg: dmg }
        tick_scene
      end
      cache[rev_key] = rev
    end

    fwd
  end

  #---------------------------------------------------------------------------
  # Builds the cache key for damage_moves. Extracted for reuse.
  #---------------------------------------------------------------------------
  def _dmg_cache_key(attacker, defender)
    mega = (@battle.pbRegisteredMegaEvolution?(attacker.index) rescue false)
    tera = (@battle.pbRegisteredTerastallize?(attacker.index) rescue false) || attacker.tera?
    def_tera = defender.tera?
    [attacker.index, defender.index, @battle.turnCount, mega, tera, def_tera,
     attacker.pokemon&.personalID, defender.pokemon&.personalID]
  end

  #---------------------------------------------------------------------------
  # Direct damage calculation for a single move on sim battlers.
  # Handles failure checks, multi-hit, Parental Bond, and fixed damage.
  # attacker_ai/defender_ai are retained for call-site compatibility.
  #---------------------------------------------------------------------------
  def calc_move_damage(move, sim_user, sim_target, attacker_ai = nil, defender_ai = nil)
    # Find the sim version of the move on the sim battler
    sim_move = sim_user.moves.find { |sm| sm.id == move.id }
    sim_move ||= move  # fallback to the original move object

    # Move failure check: type immunity, ability immunity, etc.
    calc_type = sim_move.pbCalcType(sim_user)
    type_mod = sim_move.pbCalcTypeMod(calc_type, sim_user, sim_target)
    # Type immunity
    return 0 if Effectiveness.ineffective?(type_mod)
    # Ability immunity
    return 0 if sim_move.pbImmunityByAbility(sim_user, sim_target, false)
    # Ground vs airborne
    return 0 if calc_type == :GROUND && sim_target.airborne? && !sim_move.hitsFlyingTargets?
    # Primal weather
    return 0 if sim_user.battle.pbWeather == :HeavyRain && calc_type == :FIRE
    return 0 if sim_user.battle.pbWeather == :HarshSun && calc_type == :WATER

    # Set up damage state for calculation
    sim_target.damageState.reset
    sim_move.calcType = calc_type
    sim_target.damageState.typeMod = type_mod
    sim_move.pbCheckDamageAbsorption(sim_user, sim_target)

    # Calculate damage
    sim_move.pbCalcDamage(sim_user, sim_target, 1)
    base_dmg = sim_target.damageState.calcDamage || 0

    # Multi-hit multiplier
    hits = calc_multi_hit_count(sim_move, sim_user)
    if hits > 1
      if sim_move.is_a?(Battle::Move::HitThreeTimesPowersUpWithEachHit)
        # Triple Kick/Triple Axel: damage escalates 1x + 2x + 3x = 6x base hit
        base_dmg *= 6
      else
        base_dmg *= hits
      end
    end

    # Parental Bond second hit (only if not already a multi-hit move)
    if hits <= 1 && sim_user.hasActiveAbility?(:PARENTALBOND) &&
       !(sim_move.respond_to?(:chargingTurnMove?) && sim_move.chargingTurnMove?)
      second_hit = (base_dmg * (Settings::MECHANICS_GENERATION >= 7 ? 0.25 : 0.5)).round
      base_dmg += second_hit
    end

    [base_dmg, 0].max
  end

  #---------------------------------------------------------------------------
  # Returns the expected number of hits for a multi-hit move.
  #---------------------------------------------------------------------------
  def calc_multi_hit_count(move, sim_user)
    return 1 unless move.multiHitMove?
    case move
    when Battle::Move::HitTwoTimes,
         Battle::Move::HitTwoTimesPoisonTarget,
         Battle::Move::HitTwoTimesFlinchTarget
      return 2
    when Battle::Move::HitThreeTimesPowersUpWithEachHit,
         Battle::Move::HitThreeTimesAlwaysCriticalHit
      return 3
    when Battle::Move::HitTwoToFiveTimes,
         Battle::Move::HitTwoToFiveTimesRaiseUserSpd1LowerUserDef1
      return 5 if sim_user.hasActiveAbility?(:SKILLLINK)
      return 5 if sim_user.hasActiveItem?(:LOADEDDICE)  # 4-5 hits, use 5
      return 3  # Expected value of 2-5 distribution ≈ 3.1
    when Battle::Move::HitTwoToFiveTimesOrThreeForAshGreninja
      return 3 if sim_user.isSpecies?(:GRENINJA) && sim_user.form == 2
      return 5 if sim_user.hasActiveAbility?(:SKILLLINK)
      return 5 if sim_user.hasActiveItem?(:LOADEDDICE)
      return 3
    when Battle::Move::HitOncePerUserTeamMember
      # Beat Up: count eligible party members
      count = 0
      sim_user.battle.eachInTeamFromBattlerIndex(sim_user.index) do |pkmn, _i|
        count += 1 if pkmn.able? && pkmn.status == :NONE
      end
      return [count, 1].max
    end
    # Fallback: try pbNumHits if available
    return 1
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
  # Creates ONE switched sim, then uses direct pbCalcDamage per move.
  # Also populates the reverse (target→attacker) cache from the same sim.
  # Returns {move_id => {move:, dmg:}}
  #---------------------------------------------------------------------------
  def damage_moves_with_switch(attacker_index, target_index, pre_switch)
    fwd_key = _dmg_switch_cache_key(attacker_index, target_index, pre_switch)
    return nil unless fwd_key  # nil means a required pkmn was missing
    cache = (@_ai_dmg_cache ||= {})
    return cache[fwd_key] if cache.key?(fwd_key)

    PBDebug.log_ai("[damage_moves_with_switch] computing #{attacker_index} ↔ #{target_index} (turn #{@battle.turnCount})")
    sim = create_switched_sim(pre_switch)
    sim_a = sim.battlers[attacker_index]
    sim_b = sim.battlers[target_index]

    # Forward: attacker → target
    # Use sim battler's moves for switched-in battlers (form changes like
    # Dynamax alter the moveset; sim already has the correct Battle::Move objects)
    fwd = {}
    fwd_moves = pre_switch[attacker_index] ? sim_a.moves : _switch_move_source(attacker_index, pre_switch)
    fwd_moves.each do |m|
      is_damaging = m.is_a?(Pokemon::Move) ? GameData::Move.get(m.id).damaging? : m.damagingMove?
      next unless is_damaging
      dmg = calc_move_damage(m, sim_a, sim_b)
      fwd[m.id] = { move: m, dmg: dmg }
      tick_scene
    end
    cache[fwd_key] = fwd

    # Reverse: target → attacker (reuse same sim)
    rev_key = _dmg_switch_cache_key(target_index, attacker_index, pre_switch)
    if rev_key && !cache.key?(rev_key)
      rev = {}
      rev_moves = pre_switch[target_index] ? sim_b.moves : _switch_move_source(target_index, pre_switch)
      rev_moves.each do |m|
        is_damaging = m.is_a?(Pokemon::Move) ? GameData::Move.get(m.id).damaging? : m.damagingMove?
        next unless is_damaging
        dmg = calc_move_damage(m, sim_b, sim_a)
        rev[m.id] = { move: m, dmg: dmg }
        tick_scene
      end
      cache[rev_key] = rev
    end

    fwd
  end

  #---------------------------------------------------------------------------
  # Builds the cache key for damage_moves_with_switch.
  # Returns nil if a required party member is missing.
  #---------------------------------------------------------------------------
  def _dmg_switch_cache_key(attacker_index, target_index, pre_switch)
    if pre_switch[attacker_index]
      pkmn = @battle.pbParty(attacker_index)[pre_switch[attacker_index]]
      return nil unless pkmn
      atk_id = pkmn.personalID
    else
      atk_id = @battle.battlers[attacker_index].pokemon&.personalID
    end
    if pre_switch[target_index]
      tgt_pkmn = @battle.pbParty(target_index)[pre_switch[target_index]]
      return nil unless tgt_pkmn
      tgt_id = tgt_pkmn.personalID
    else
      tgt_id = @battle.battlers[target_index].pokemon&.personalID
    end
    [:dmg_switch, attacker_index, target_index, @battle.turnCount, atk_id, tgt_id]
  end

  #---------------------------------------------------------------------------
  # Returns the move list for a battler in a switch context.
  #---------------------------------------------------------------------------
  def _switch_move_source(battler_index, pre_switch)
    if pre_switch[battler_index]
      pkmn = @battle.pbParty(battler_index)[pre_switch[battler_index]]
      pkmn.moves.compact
    else
      ai = @battlers[battler_index]
      (ai.side != @user.side) ? known_foe_moves(ai) : ai.moves.compact
    end
  end

  #---------------------------------------------------------------------------
  # Returns the best move data {move:, dmg:} from damage_moves_with_switch.
  #---------------------------------------------------------------------------
  def best_damage_move_with_switch(attacker_index, target_index, pre_switch)
    dmg_data = damage_moves_with_switch(attacker_index, target_index, pre_switch)
    return nil unless dmg_data
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

        status_survival = {}
        foe_best_dmg = foe_best&.dig(:dmg) || 0
        foe_action_id = nil
        
        if foe_best_dmg >= @user.hp
          lethal_moves = damage_moves(b, @user).values.select { |d| d[:dmg] >= @user.hp }
          foe_lethal_move = lethal_moves.max_by { |d| d[:move].priority }&.dig(:move)
          foe_action_id = foe_lethal_move.id if foe_lethal_move
        else
          foe_action_id = foe_best_move.id if foe_best_move
        end

        foe_actions = foe_action_id ? [foe_action_id] : []
        @user.moves.each do |m|
          next if m.damagingMove?
          res = simulate_battle(
            @user.index, b.index,
            [m.id], foe_actions,
            max_turns: 1
          )
          # A status move is successful if it was used and did NOT fail
          status_survival[m.id] = res.user_succeeded
          tick_scene
        end

        foe_entry = {
          best_dmg:      foe_best_dmg,
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
          status_survival: status_survival
        }
        foe_entry[:switch_prediction_roll] = pbAIRandom(100)
        summary[:foes][b.index] = foe_entry
        summary[:max_foe_dmg] = [summary[:max_foe_dmg], foe_best_dmg].max
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

  #---------------------------------------------------------------------------
  # [NEW] Lazy per-move status survival check for reserve switch-ins.
  # Only simulates the specific move requested, caching individual results.
  #---------------------------------------------------------------------------
  def status_move_survival_with_switch(attacker_index, target_index, pre_switch, foe_lethal_move_id, foe_vs_current_id, m_id)
    if pre_switch[attacker_index]
      pkmn = @battle.pbParty(attacker_index)[pre_switch[attacker_index]]
      return false unless pkmn
      atk_id = pkmn.personalID
    else
      atk_id = @battle.battlers[attacker_index].pokemon&.personalID
    end

    tgt_id = pre_switch[target_index] ? @battle.pbParty(target_index)[pre_switch[target_index]].personalID : @battle.battlers[target_index].pokemon&.personalID

    key = [:status_switch, attacker_index, target_index, @battle.turnCount, atk_id, tgt_id, foe_lethal_move_id, foe_vs_current_id, m_id]
    (@_ai_dmg_cache ||= {})[key] ||= begin
      voluntary_switch = @battle.command_phase
      party_index = pre_switch[attacker_index]

      PBDebug.log("status move survival)")
      if voluntary_switch && party_index
        sim = create_switched_sim(
           pre_switch,
           voluntary_switch: true,
           target_index: target_index,
           foe_move_id: foe_vs_current_id
        )
      else
        sim = create_switched_sim(pre_switch)
      end
      sim_foe_actions = foe_lethal_move_id ? [foe_lethal_move_id] : []
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

    best_damage = best_damage_move_with_switch(target_battler.index, idxBattler, pre_switch)

    # foe_dmg_hash = damage_moves_with_switch(target_battler.index, idxBattler, pre_switch)
    # lethal_moves = foe_dmg_hash.values.select { |d| d[:dmg] >= pkmn.hp }
    return true unless best_damage

    # foe_lethal_move = lethal_moves.max_by { |d| d[:move].priority }&.dig(:move)
    # return true unless foe_lethal_move

    foe_vs_current = best_damage_move(target_battler, @user) unless @user.fainted?
    foe_vs_current_id = foe_vs_current ? foe_vs_current[:move].id : best_damage.id

    status_move_survival_with_switch(
      idxBattler, target_battler.index, pre_switch,
      best_damage.id, foe_vs_current_id, m_id
    ) == true
  end

end
