#===============================================================================
# [AI_Improved.rb] - Safe Move-Scoring AI for Pokémon Essentials v21.1
# - Deluxe Battle Kit(DBK) / 더블 / 레이드 호환
#===============================================================================

#-------------------------------------------------------------------------------
# Fog of War: track any battler that uses a move so the AI knows they've acted
#-------------------------------------------------------------------------------
class Battle::Battler
  alias _tower_fog_pbProcessTurn pbProcessTurn
  def pbProcessTurn(choice, tryFlee = true)
    ret = _tower_fog_pbProcessTurn(choice, tryFlee)
    if choice[0] == :UseMove && self.pokemon
      acted = @battle.instance_variable_get(:@_foe_acted_ids) || {}
      acted[self.pokemon.personalID] = true
      @battle.instance_variable_set(:@_foe_acted_ids, acted)
    end
    ret
  end
end

class Battle::AI
  MOVE_FAIL_SCORE = -999

  #---------------------------------------------------------------------------
  # [Helper] 효과 배율을 float로 변환
  #---------------------------------------------------------------------------
  def pbGetEffectivenessMult(effectiveness_id)
    return effectiveness_id.to_f / 100.0
  end

  # Override: clamp score to at least 0 so negative scores from penalties
  # don't get treated as move failure (-1) by the core engine.
  alias pbGetMoveScoreAgainstTarget_original pbGetMoveScoreAgainstTarget
  def pbGetMoveScoreAgainstTarget
    result = pbGetMoveScoreAgainstTarget_original
    return result if result == -1   # Actual move failure, keep as-is
    return [result, 0].max
  end

  def safe_function_code(move)
    return nil if !move || !move.respond_to?(:function_code)
    return move.function_code
  end

  def safe_types(obj)
    return [] if !obj
    return obj.pbTypes(true) if obj.respond_to?(:pbTypes)
    return obj.types if obj.respond_to?(:types)
    return []
  end

   # override stat raise generic 
  def get_target_stat_raise_score_generic(score, target, stat_changes, desire_mult = 1)
    return score
  end

  #override choose move - remove turn count limit
  def pbChooseMove(choices)
    user_battler = @user.battler
    max_score = 0
    choices.each { |c| max_score = c[1] if max_score < c[1] }
    if @trainer.high_skill? && @user.can_switch_lax?
      badMoves = false
      if max_score < MOVE_BASE_SCORE
        badMoves = true if pbAIRandom(max_score) < 80
      end
      if badMoves
        PBDebug.log_ai("#{@user.name} wants to switch due to terrible moves")
        if pbChooseToSwitchOut(true)
          @battle.pbUnregisterMegaEvolution(@user.index)
          return
        end
        PBDebug.log_ai("#{@user.name} won't switch after all")
      end
    end

    if choices.length == 0
      @battle.pbAutoChooseMove(user_battler.index)
      PBDebug.log_ai("#{@user.name} will auto-use a move or Struggle")
      return
    end

    threshold = max_score - (20 * move_score_threshold.to_f).floor
    choices.each { |c| c[3] = [c[1] - threshold, 0].max }
    total_score = choices.sum { |c| c[3] }
    PBDebug.log_ai("Move choices for #{@user.name} with threshold: #{threshold}: ")
    choices.each_with_index do |c, i|
      chance = sprintf("%5.1f", (c[3] > 0) ? 100.0 * c[3] / total_score : 0)
      log_msg = "   * #{chance}% to use #{c[4].name}"
      log_msg += " (target #{c[2]})" if c[2] >= 0
      log_msg += ": score #{c[1]}"
      PBDebug.log_ai(log_msg)
    end
    randNum = pbAIRandom(total_score)
    choices.each do |c|
      randNum -= c[3]
      next if randNum >= 0
      pbRegisterEnemySpecialActionFromMove(user_battler, c[4])
      @battle.pbRegisterMove(user_battler.index, c[0], false)
      @battle.pbRegisterTarget(user_battler.index, c[2]) if c[2] && c[2] >= 0
      break
    end
    if @battle.choices[user_battler.index][2]
      move_name = @battle.choices[user_battler.index][2].name
      if @battle.choices[user_battler.index][3] >= 0
        PBDebug.log_ai("=> will use #{move_name} (target #{@battle.choices[user_battler.index][3]})")
      else
        PBDebug.log_ai("=> will use #{move_name}")
      end
    end
  end

  #override pbChooseToSwitchOut
  def pbChooseToSwitchOut(terrible_moves = false)
    return false if !@battle.canSwitch   # Battle rule
    return false if @user.wild?
    return false if !@battle.pbCanSwitchOut?(@user.index)
    # Don't switch if all foes are unable to do anything, e.g. resting after
    # Hyper Beam, will Truant (i.e. free turn)
    if @trainer.high_skill? && !terrible_moves
      foe_can_act = false
      each_foe_battler(@user.side) do |b, i|
        next if !b.can_attack?
        foe_can_act = true
        break
      end
      return false if !foe_can_act
    end
    # Various calculations to decide whether to switch
    if terrible_moves
      PBDebug.log_ai("#{@user.name} is being forced to switch out")
    else
      return false if !@trainer.has_skill_flag?("ConsiderSwitching")
      reserves = get_non_active_party_pokemon(@user.index)
      return false if reserves.empty?
      should_switch = Battle::AI::Handlers.should_switch?(@user, reserves, self, @battle)
      if should_switch && @trainer.medium_skill?
        should_switch = false if Battle::AI::Handlers.should_not_switch?(@user, reserves, self, @battle)
      end
      return false if !should_switch
    end
    # Want to switch; find the best replacement Pokémon
    idxParty = choose_best_replacement_pokemon(@user.index, false, terrible_moves)
    if idxParty < 0   # No good replacement Pokémon found
      PBDebug.log_ai("   => no good replacement Pokémon, will not switch after all")
      return false
    end
    # Prefer using Baton Pass instead of switching
    baton_pass = -1
    @user.battler.eachMoveWithIndex do |m, i|
      next if m.function_code != "SwitchOutUserPassOnEffects"   # Baton Pass
      next if !@battle.pbCanChooseMove?(@user.index, i, false)
      baton_pass = i
      break
    end
    if baton_pass >= 0 && @battle.pbRegisterMove(@user.index, baton_pass, false)
      PBDebug.log_ai("=> will use Baton Pass to switch out")
      return true
    elsif @battle.pbRegisterSwitch(@user.index, idxParty)
      PBDebug.log_ai("=> will switch with #{@battle.pbParty(@user.index)[idxParty].name}")
      return true
    end
    return false
  end

  def choose_best_replacement_pokemon(idxBattler, forced_switch = false, terrible_moves = false)
    # forced_switch: Passed as true explicitly by the battle engine when a Pokémon faints or uses a pivoting move (e.g., U-turn, Parting Shot).
    # terrible_moves: Passed as true during the AI's action phase if its current moveset has no good options.
    
    # Get all possible replacement Pokémon
    party = @battle.pbParty(idxBattler)
    idxPartyStart, idxPartyEnd = @battle.pbTeamIndexRangeFromBattlerIndex(idxBattler)
    reserves = []
    party.each_with_index do |_pkmn, i|
      next if !@battle.pbCanSwitchIn?(idxBattler, i)
      if !terrible_moves && !forced_switch   # Choosing an action for the round
        ally_will_switch_with_i = false
        @battle.allSameSideBattlers(idxBattler).each do |b|
          next if @battle.choices[b.index][0] != :SwitchOut || @battle.choices[b.index][1] != i
          ally_will_switch_with_i = true
          break
        end
        next if ally_will_switch_with_i
      end

      reserves.push([i, 100])
      break if @trainer.has_skill_flag?("UsePokemonInOrder") && reserves.length > 0
    end
    return -1 if reserves.length == 0
    # Rate each possible replacement Pokémon
    reserves.each_with_index do |reserve, i|
      reserves[i][1] = rate_replacement_pokemon(idxBattler, party[reserve[0]], reserve[1], terrible_moves)
      PBDebug.log_ai("pokemon #{party[reserve[0]].name} has switch score #{reserves[i][1]}")
    end
    reserves.sort! { |a, b| b[1] <=> a[1] }   # Sort from highest to lowest rated
    # When all replacements are poorly rated, decide whether to sack
    if @trainer.high_skill? && reserves[0][1] < 60
      if forced_switch
        # Must switch (faint/pivot) — just pick the highest-scored reserve
        PBDebug.log_ai("=> forced switch: sacking #{party[reserves[0][0]].name} (best score #{reserves[0][1]})")
        return reserves[0][0]
      end
      # Voluntary switch: rate the current active Pokémon with the same system
      # and compare — sack whichever is least valuable
      active_pkmn = @battle.battlers[idxBattler].pokemon
      active_score = rate_replacement_pokemon(idxBattler, active_pkmn, 100, terrible_moves)
      PBDebug.log_ai("=> sack evaluation: active #{active_pkmn.name} score=#{active_score}, best reserve #{party[reserves[0][0]].name} score=#{reserves[0][1]}")
      # Find the worst-scored reserve (the one we'd sack)
      worst_reserve = reserves.last
      best_reserve = reserves[0]
      if worst_reserve[1] < active_score && best_reserve[1] > active_score
        # A reserve is worse than the active mon and there is an alternative better than active mon — switch to sack it
        PBDebug.log_ai("=> sacking reserve #{party[worst_reserve[0]].name} (score #{worst_reserve[1]} < active #{active_score})")
        return worst_reserve[0]
      else
        # Active mon is the worst or equal — stay in, let it be the sack
        PBDebug.log_ai("=> staying in: #{active_pkmn.name} is the sack (score #{active_score})")
        return -1
      end
    end
    # Return the party index of the best rated replacement Pokémon
    return reserves[0][0]
  end

  #override
  def rate_replacement_pokemon(idxBattler, pkmn, score, terrible_moves = false)
    # The actual calculations are deferred to handlers
    score = Battle::AI::Handlers.score_replacement(idxBattler, pkmn, score, terrible_moves, @battle, self)
    return score.to_i
  end

  # Returns {move_id => {move: Battle::Move, dmg: int}}
  # Computes predicted_damage for each of attacker's damaging moves against defender, cached per turn.
  # - attacker/defender are AIBattler instances (attacker.index and defender.index are Integers)
  # - keyed by move ID (symbol) for O(1) lookup of a specific move's damage
  # - cache key uses battler indexes; both directions stored separately (e.g. [0,1] != [1,0])
  def damage_moves(attacker, defender)
    key = [attacker.index, defender.index, @battle.turnCount]
    (@_ai_dmg_cache ||= {})[key] ||= begin
      PBDebug.log_ai("[damage_moves] computing #{attacker.name} → #{defender.name} (turn #{@battle.turnCount})")
      moves_by_id = {}
      moves_list = (attacker.side != @user.side) ? known_foe_moves(attacker) : attacker.battler.moves
      moves_list.each do |m|
        next unless m&.damagingMove?
        sim = Battle::AI::AIMove.new(self)
        sim.set_up(m)
        dmg = sim.predicted_damage(user: attacker, target: defender) || 0
        pct_total = (100.0 * dmg / [1, defender.battler.totalhp].max).round(1)
        pct_hp    = (100.0 * dmg / [1, defender.hp].max).round(1)
        PBDebug.log_ai("  #{m.name}: #{dmg} dmg (#{pct_total}% totalhp / #{pct_hp}% curhp)")
        moves_by_id[m.id] = { move: m, dmg: dmg }
      end
      moves_by_id
    end
  end

  #---------------------------------------------------------------------------
  # Fog of War: returns the list of moves the AI "knows" about for a foe.
  # If the foe has never acted, one non-STAB move may be hidden (50% chance).
  # Result is cached per [battler.index, turnCount] for consistency.
  #---------------------------------------------------------------------------
  def known_foe_moves(foe_ai_battler)
    cache_key = [foe_ai_battler.index, @battle.turnCount]
    (@_known_foe_moves_cache ||= {})[cache_key] ||= begin
      all_moves = foe_ai_battler.battler.moves.compact
      acted_ids = @battle.instance_variable_get(:@_foe_acted_ids) || {}
      pkmn = foe_ai_battler.battler.pokemon

      if pkmn && acted_ids[pkmn.personalID]
        # Foe has acted before — full knowledge
        all_moves
      else
        # Foe has never acted — protect best STAB moves, maybe hide one other
        foe_types = foe_ai_battler.battler.pbTypes(true)
        # For each type, find the highest-power STAB move
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
end

module Battle::AI::Handlers
  ScoreReplacement = HandlerHash.new

  def self.score_replacement(idxBattler, pkmn, score, terrible_moves, battle, user_ai)
    ScoreReplacement.each do |id, score_proc|
      new_score = score_proc.call(idxBattler, pkmn, score, terrible_moves, battle, user_ai)
      score = new_score if new_score
    end
    return score
  end
end

#===============================================================================
# [CRITICAL FIX] AIBattler 호환성 패치 (NoMethodError 방지)
#===============================================================================
class Battle::AI::AIBattler
  def unstoppableAbility?(ability_id)
    return self.battler.unstoppableAbility?(ability_id) if self.battler.respond_to?(:unstoppableAbility?)
    return false
  end

  def isRaidBoss?
    return self.battler.isRaidBoss? if self.battler.respond_to?(:isRaidBoss?)
    return false
  end
end

class Battle::AI::AIMove
  PRIMAL_WEATHERS = [:HarshSun, :HeavyRain, :StrongWinds].freeze

  alias rough_damage_original rough_damage

  def rough_damage
    case self.rough_type
    when :WATER then return 1 if @ai.battle.pbWeather == :HarshSun
    when :FIRE  then return 1 if @ai.battle.pbWeather == :HeavyRain
    end
    return rough_damage_original
  end

  def simulated_field_weather(switch_in_pkmn, current)
    return current unless switch_in_pkmn
    new_w = current
    if switch_in_pkmn.isSpecies?(:KYOGRE) && switch_in_pkmn.hasItem?(:BLUEORB)
      new_w = :HeavyRain
    elsif switch_in_pkmn.isSpecies?(:GROUDON) && switch_in_pkmn.hasItem?(:REDORB)
      new_w = :HarshSun
    else
      new_w = case switch_in_pkmn.ability_id
      when :DROUGHT, :ORICHALCUMPULSE then :Sun
      when :DRIZZLE                   then :Rain
      when :SANDSTREAM                then :Sandstorm
      when :SNOWWARNING               then :Hail
      when :DESOLATELAND              then :HarshSun
      when :PRIMORDIALSEA             then :HeavyRain
      when :DELTASTREAM               then :StrongWinds
      else return current
      end
    end
    # StrongWinds cannot be replaced by HarshSun or HeavyRain
    return current if current == :StrongWinds && new_w != :StrongWinds
    # Primal weather can only be replaced by another primal weather
    return current if PRIMAL_WEATHERS.include?(current) && !PRIMAL_WEATHERS.include?(new_w)
    return new_w
  end

  def simulated_field_terrain(switch_in_pkmn, current)
    return current unless switch_in_pkmn
    case switch_in_pkmn.ability_id
    when :ELECTRICSURGE, :HADRONENGINE then :Electric
    when :GRASSYSURGE                  then :Grassy
    when :MISTYSURGE                   then :Misty
    when :PSYCHICSURGE                 then :Psychic
    else current
    end
  end

  def predicted_damage(user:, target:, user_pokemon: nil, target_pokemon: nil)
    prev_user   = @ai.user
    prev_target = @ai.target
    user_idx    = user.index
    target_idx  = target.index

    prev_user_battler = nil
    if user_pokemon
      prev_user_battler = @ai.battle.battlers[user_idx]
      temp = Battle::Battler.new(@ai.battle, user_idx)
      temp.pbInitialize(user_pokemon, 0)
      @ai.battle.battlers[user_idx] = temp
    end

    prev_target_battler = nil
    if target_pokemon
      prev_target_battler = @ai.battle.battlers[target_idx]
      temp = Battle::Battler.new(@ai.battle, target_idx)
      temp.pbInitialize(target_pokemon, 0)
      @ai.battle.battlers[target_idx] = temp
    end

    @ai.instance_variable_set(:@user, user)
    @ai.instance_variable_set(:@target, target)
    user.refresh_battler
    target.refresh_battler

    switch_in_pkmn = user_pokemon || target_pokemon
    orig_weather   = @ai.battle.field.weather
    orig_terrain   = @ai.battle.field.terrain

    begin
      @ai.battle.field.instance_variable_set(:@weather, simulated_field_weather(switch_in_pkmn, orig_weather))
      @ai.battle.field.instance_variable_set(:@terrain, simulated_field_terrain(switch_in_pkmn, orig_terrain))

      calc_type          = self.rough_type
      eff_user_battler   = @ai.battle.battlers[user_idx]
      eff_target_battler = @ai.battle.battlers[target_idx]

      # Psychic Terrain blocks priority moves from hitting grounded targets
      if @move.priority > 0 && @ai.battle.field.terrain == :Psychic &&
         eff_target_battler.affectedByTerrain?
        return 0
      end

      # Ground immunity: airborne? covers Flying, Levitate, Air Balloon, Gravity,
      # and on live battlers also MagnetRise, Telekinesis, SmackDown, Ingrain.
      if calc_type == :GROUND && eff_target_battler.airborne? && !@move.hitsFlyingTargets?
        return 0
      end

      # MoveImmunity abilities: Flash Fire, Volt Absorb, Water Absorb, Dry Skin,
      # Lightning Rod, Motor Drive, Storm Drain, Sap Sipper, Soundproof, Bulletproof,
      # Wonder Guard, Good as Gold, Wind Rider, Well-Baked Body, Earth Eater, etc.
      if eff_target_battler.abilityActive? && !@ai.battle.moldBreaker
        if Battle::AbilityEffects.triggerMoveImmunity(
             eff_target_battler.ability, eff_user_battler, eff_target_battler,
             @move, calc_type, @ai.battle, false)
          return 0
        end
      end

      return self.rough_damage
    ensure
      @ai.battle.field.instance_variable_set(:@weather, orig_weather)
      @ai.battle.field.instance_variable_set(:@terrain, orig_terrain)
      @ai.battle.battlers[user_idx]   = prev_user_battler   if prev_user_battler
      @ai.battle.battlers[target_idx] = prev_target_battler if prev_target_battler
      @ai.instance_variable_set(:@user, prev_user)
      @ai.instance_variable_set(:@target, prev_target)
      user.refresh_battler
      target.refresh_battler
      prev_user&.refresh_battler
      prev_target&.refresh_battler
    end
  end
end
