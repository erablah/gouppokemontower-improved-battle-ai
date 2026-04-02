#===============================================================================
# [AI_Improved_DamageMoves.rb] - Damage Caching, Damage Move Selection
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

    # Mirror the real move-use flow closely enough for moves whose damage setup
    # happens in pbOnStartUse (e.g. Tera Blast under simulated Terastallization).
    sim_move.calcType = sim_move.pbCalcType(sim_user)
    sim_move.pbOnStartUse(sim_user, [sim_target])

    # Move failure check: type immunity, ability immunity, etc.
    calc_type = sim_move.calcType
    type_mod = sim_move.pbCalcTypeMod(calc_type, sim_user, sim_target)
    return 0 if Effectiveness.ineffective?(type_mod)
    return 0 if sim_move.pbImmunityByAbility(sim_user, sim_target, false)
    return 0 if calc_type == :GROUND && sim_target.airborne? && !sim_move.hitsFlyingTargets?
    return 0 if sim_user.battle.pbWeather == :HeavyRain && calc_type == :FIRE
    return 0 if sim_user.battle.pbWeather == :HarshSun && calc_type == :WATER

    sim_target.damageState.reset
    sim_move.calcType = calc_type
    sim_target.damageState.typeMod = type_mod
    sim_move.pbCheckDamageAbsorption(sim_user, sim_target)

    sim_move.pbCalcDamage(sim_user, sim_target, 1)
    base_dmg = sim_target.damageState.calcDamage || 0

    hits = calc_multi_hit_count(sim_move, sim_user)
    if hits > 1
      if sim_move.is_a?(Battle::Move::HitThreeTimesPowersUpWithEachHit)
        base_dmg *= 6
      else
        base_dmg *= hits
      end
    end

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
      return 5 if sim_user.hasActiveItem?(:LOADEDDICE)
      return 3
    when Battle::Move::HitTwoToFiveTimesOrThreeForAshGreninja
      return 3 if sim_user.isSpecies?(:GRENINJA) && sim_user.form == 2
      return 5 if sim_user.hasActiveAbility?(:SKILLLINK)
      return 5 if sim_user.hasActiveItem?(:LOADEDDICE)
      return 3
    when Battle::Move::HitOncePerUserTeamMember
      count = 0
      sim_user.battle.eachInTeamFromBattlerIndex(sim_user.index) do |pkmn, _i|
        count += 1 if pkmn.able? && pkmn.status == :NONE
      end
      return [count, 1].max
    end
    return 1
  end

  #---------------------------------------------------------------------------
  # Returns the best move data {move:, dmg:} from damage_moves.
  #---------------------------------------------------------------------------
  def best_damage_move(attacker, defender)
    dmg_data = damage_moves(attacker, defender)
    _select_best_damage_move(dmg_data, attacker, defender)
  end

  #---------------------------------------------------------------------------
  # Scores a lethal move tie for best_damage_move/best_damage_move_with_switch.
  # Priority is weighted heavily; beneficial self-effects increase the odds,
  # while drawbacks like recharge/two-turn/self-drops decrease the odds.
  #---------------------------------------------------------------------------
  def _select_best_damage_move(dmg_data, attacker, target = nil)
    return nil if !dmg_data || dmg_data.empty?
    max_dmg = dmg_data.values.max_by { |md| md[:dmg] }[:dmg]
    lethal_moves = dmg_data.values.select { |md| md[:dmg] == max_dmg }
    lethal_threshold = nil
    if target && target.respond_to?(:hp)
      lethal_threshold = target.hp
      lethal_moves = dmg_data.values.select { |md| md[:dmg] >= lethal_threshold }
    end
    if lethal_moves.length > 1
      cached_selection = _cached_best_damage_move(dmg_data, lethal_threshold)
      return cached_selection if cached_selection
      lethal_moves.each do |md|
        md[:lethal_score] = _lethal_move_score(md[:move], attacker)
        md[:lethal_weight] = _lethal_move_weight(md[:lethal_score])
      end
      selected = _pick_weighted_lethal_move(lethal_moves)
      _cache_best_damage_move(dmg_data, lethal_threshold, selected)
      return selected
    end
    best = dmg_data.values.max_by { |md| md[:dmg] }
    best[:lethal_score] = _lethal_move_score(best[:move], attacker) if best
    return best
  end

  def _lethal_move_score(move, attacker)
    scored_move = _move_for_lethal_scoring(move, attacker)
    score = _move_priority(scored_move, attacker) * 100
    score -= 90 if scored_move.function_code == "AttackAndSkipNextTurn"
    score -= 70 if scored_move.respond_to?(:chargingTurnMove?) && scored_move.chargingTurnMove?
    score -= 20 if scored_move.respond_to?(:recoilMove?) && scored_move.recoilMove?
    score += 15 if scored_move.respond_to?(:healingMove?) && scored_move.healingMove? && scored_move.damagingMove?

    contrary = attacker && attacker.respond_to?(:hasActiveAbility?) && attacker.hasActiveAbility?(:CONTRARY)
    score += _lethal_stat_stage_score(scored_move, contrary)
    score
  end

  def _move_for_lethal_scoring(move, attacker)
    return move if move.is_a?(Battle::Move)
    battle = (attacker && attacker.respond_to?(:battle)) ? attacker.battle : @battle
    Battle::Move.from_pokemon_move(battle, move)
  rescue StandardError
    move
  end

  def _move_priority(move, attacker)
    return move.pbPriority(attacker) if attacker && move.respond_to?(:pbPriority)
    return move.priority if move.respond_to?(:priority)
    0
  end

  def _lethal_stat_stage_score(move, contrary)
    score = 0
    score += _sum_stat_stages(move.statUp) * (contrary ? -12 : 12) if move.respond_to?(:statUp) && move.statUp
    score += _sum_stat_stages(move.statDown) * (contrary ? 14 : -14) if move.respond_to?(:statDown) && move.statDown
    score
  end

  def _sum_stat_stages(stat_changes)
    total = 0
    stat_changes.each_with_index do |_stat, idx|
      next if idx.even?
      total += stat_changes[idx].to_i
    end
    total
  end

  def _lethal_move_weight(score)
    [1, 100 + score].max
  end

  def _pick_weighted_lethal_move(lethal_moves)
    total_weight = lethal_moves.sum { |md| md[:lethal_weight] || 1 }
    roll = @battle.pbRandom(total_weight)
    lethal_moves.each do |md|
      weight = md[:lethal_weight] || 1
      return md if roll < weight
      roll -= weight
    end
    lethal_moves.max_by { |md| [md[:lethal_weight] || 1, md[:dmg]] }
  end

  def _cached_best_damage_move(dmg_data, lethal_threshold)
    cache = dmg_data.instance_variable_get(:@_selected_best_moves)
    return nil unless cache
    cache[lethal_threshold]
  end

  def _cache_best_damage_move(dmg_data, lethal_threshold, selected)
    cache = dmg_data.instance_variable_get(:@_selected_best_moves)
    unless cache
      cache = {}
      dmg_data.instance_variable_set(:@_selected_best_moves, cache)
    end
    cache[lethal_threshold] = selected
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
    return nil unless fwd_key
    cache = (@_ai_dmg_cache ||= {})
    return cache[fwd_key] if cache.key?(fwd_key)

    PBDebug.log_ai("[damage_moves_with_switch] computing #{attacker_index} ↔ #{target_index} (turn #{@battle.turnCount})")
    sim = create_switched_sim(pre_switch)
    sim_a = sim.battlers[attacker_index]
    sim_b = sim.battlers[target_index]

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
    attacker = @battle.battlers[attacker_index]
    target = if pre_switch[target_index]
               @battle.pbParty(target_index)[pre_switch[target_index]]
             else
               @battle.battlers[target_index]
             end
    _select_best_damage_move(dmg_data, attacker, target)
  end
end
