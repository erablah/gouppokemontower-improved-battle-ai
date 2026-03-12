#===============================================================================
# [AI_Improved.rb] - Safe Move-Scoring AI for Pokémon Essentials v21.1
# - DBK / Doubles / Raid compatible
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

  # Fix: Struggle is blocked by Choice lock during the attack phase because
  # pbTryUseMove calls pbCanChooseMove?, which rejects any move that isn't the
  # Choice-locked move. Struggle should always be usable.
  alias _tower_struggle_pbCanChooseMove pbCanChooseMove?
  def pbCanChooseMove?(move, commandPhase, showMessages = true, specialUsage = false)
    return true if move.is_a?(Battle::Move::Struggle)
    return _tower_struggle_pbCanChooseMove(move, commandPhase, showMessages, specialUsage)
  end
end

class Battle::AI
  MOVE_FAIL_SCORE = -999
  REPLACEMENT_THRESHOLD_NORMAL = 120
  REPLACEMENT_THRESHOLD_TERRIBLE_MOVES = 60

  #---------------------------------------------------------------------------
  # [Helper] Convert effectiveness multiplier to float
  #---------------------------------------------------------------------------
  def pbGetEffectivenessMult(effectiveness_id)
    return effectiveness_id.to_f / 100.0
  end


  # Override: replace -1 sentinel with MOVE_FAIL_SCORE for failed moves,
  # so negative penalty scores aren't confused with move failures.
  def pbGetMoveScoreAgainstTarget
    if @trainer.has_skill_flag?("PredictMoveFailure") && pbPredictMoveFailureAgainstTarget
      PBDebug.log("     move will not affect #{@target.name}")
      PBDebug.log_score_change(MOVE_FAIL_SCORE - MOVE_BASE_SCORE, "move will fail")
      return MOVE_FAIL_SCORE
    end
    score = MOVE_BASE_SCORE
    if @trainer.has_skill_flag?("ScoreMoves")
      old_score = score
      score = Battle::AI::Handlers.apply_move_effect_against_target_score(@move.function_code,
         MOVE_BASE_SCORE, @move, @user, @target, self, @battle)
      PBDebug.log_score_change(score - old_score, "function code modifier (against target)")
      score = Battle::AI::Handlers.apply_general_move_against_target_score_modifiers(
        score, @move, @user, @target, self, @battle)
    end
    target_data = @move.pbTarget(@user.battler)
    if pbShouldInvertScore?(target_data)
      if score == MOVE_USELESS_SCORE
        PBDebug.log("     move is useless against #{@target.name}")
        return MOVE_FAIL_SCORE
      end
      old_score = score
      score = ((1.85 * MOVE_BASE_SCORE) - score).to_i
      PBDebug.log_score_change(score - old_score, "score inverted (move targets ally but can target foe)")
    end
    return score
  end

  # Override: scale stat-change scores by additional effect chance for damaging
  # moves with < 100% effect probability (e.g. Moonblast's 30% SpA drop).
  alias_method :orig_get_score_for_target_stat_drop, :get_score_for_target_stat_drop
  def get_score_for_target_stat_drop(score, target, stat_changes, whole_effect = true,
                                     fixed_change = false, ignore_contrary = false)
    result = orig_get_score_for_target_stat_drop(score, target, stat_changes, whole_effect, fixed_change, ignore_contrary)
    if @move.damagingMove? && @move.move.addlEffect > 0 && @move.move.addlEffect < 100
      delta = result - score
      if delta != 0
        chance = @move.move.addlEffect
        chance = [chance * 2, 100].min if @user.has_active_ability?(:SERENEGRACE)
        scaled_delta = (delta * chance / 100.0).round
        PBDebug.log("     [additional effect scaling] stat drop: #{delta} * #{chance}% = #{scaled_delta}")
        result = score + scaled_delta
      end
    end
    return result
  end

  alias_method :orig_get_score_for_target_stat_raise, :get_score_for_target_stat_raise
  def get_score_for_target_stat_raise(score, target, stat_changes, whole_effect = true,
                                      fixed_change = false, ignore_contrary = false)
    result = orig_get_score_for_target_stat_raise(score, target, stat_changes, whole_effect, fixed_change, ignore_contrary)
    if @move.damagingMove? && @move.move.addlEffect > 0 && @move.move.addlEffect < 100
      delta = result - score
      if delta != 0
        chance = @move.move.addlEffect
        chance = [chance * 2, 100].min if @user.has_active_ability?(:SERENEGRACE)
        scaled_delta = (delta * chance / 100.0).round
        PBDebug.log("     [additional effect scaling] stat raise: #{delta} * #{chance}% = #{scaled_delta}")
        result = score + scaled_delta
      end
    end
    return result
  end

  # Override: remove the core engine's score = 0 clamp (line 284) so negative
  # scores from penalties are preserved, letting the AI pick the least-bad move.
  def pbGetMoveScore(targets = nil)
    score = MOVE_BASE_SCORE
    if targets
      score = 0
      affected_targets = 0
      orig_move = @move.move
      targets.each do |target|
        set_up_move_check(orig_move)
        set_up_move_check_target(target)
        t_score = pbGetMoveScoreAgainstTarget
        next if t_score <= MOVE_FAIL_SCORE
        score += t_score
        affected_targets += 1
      end
      if affected_targets == 0
        score = (@trainer.has_skill_flag?("PredictMoveFailure")) ? MOVE_USELESS_SCORE : MOVE_BASE_SCORE
      end
      if affected_targets == 0 && @trainer.has_skill_flag?("PredictMoveFailure")
        if !@move.move.worksWithNoTargets?
          PBDebug.log_score_change(MOVE_FAIL_SCORE - MOVE_BASE_SCORE, "move will fail")
          return MOVE_FAIL_SCORE
        end
      else
        score /= affected_targets if affected_targets > 1
        if @trainer.has_skill_flag?("PreferMultiTargetMoves") && affected_targets > 1
          old_score = score
          score += (affected_targets - 1) * 10
          PBDebug.log_score_change(score - old_score, "affects multiple battlers")
        end
      end
    end
    if @trainer.has_skill_flag?("ScoreMoves")
      old_score = score
      score = Battle::AI::Handlers.apply_move_effect_score(@move.function_code,
         score, @move, @user, self, @battle)
      PBDebug.log_score_change(score - old_score, "function code modifier (generic)")
      score = Battle::AI::Handlers.apply_general_move_score_modifiers(
        score, @move, @user, self, @battle)
    end
    return score.to_i
  end

  # override: only one tera available per team.
  alias wants_to_terastallize_original wants_to_terastallize?
  def wants_to_terastallize?
        return @user.get_total_tera_score >= 0
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

  # override stat drop generic
  def get_target_stat_drop_score_generic(score, target, stat_changes, desire_mult = 1)
    return score
  end

  #override choose move - remove turn count limit
  def pbChooseMove(choices)
    user_battler = @user.battler
    max_score = choices.map { |c| c[1] }.max || 0
    if @trainer.high_skill? && @user.can_switch_lax?
      badMoves = false
      if max_score < MOVE_BASE_SCORE - 20
        badMoves = true
      end
      if badMoves
        move_scores = choices.map { |c| "#{c[4].name}=#{c[1]}" }.join(", ")
        PBDebug.log_ai("#{@user.name} wants to switch due to terrible moves [#{move_scores}]")
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

    threshold = max_score - 20
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
    # Clear damage cache — game state may have changed since move scoring
    @_ai_dmg_cache = {}
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

    # Clear damage cache — game state may have changed since move scoring
    # (faints, pivots, stat changes, field effects, or different Pokémon at same index)
    @_ai_dmg_cache = {}

    # Get all possible replacement Pokémon
    party = @battle.pbParty(idxBattler)
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
    # Double KO: all opposing battlers are fainted, so we don't know what the
    # player will send in — pick randomly instead of scoring against a fainted foe.
    if forced_switch
      all_foes_fainted = true
      @battle.allOtherSideBattlers(idxBattler).each { |b| all_foes_fainted = false if !b.fainted? }
      if all_foes_fainted
        chosen = reserves.sample
        PBDebug.log_ai("=> double KO: randomly choosing #{party[chosen[0]].name}")
        return chosen[0]
      end
    end
    # Rate each possible replacement Pokémon
    reserves.each_with_index do |reserve, i|
      reserves[i][1] = rate_replacement_pokemon(idxBattler, party[reserve[0]], reserve[1], terrible_moves)
      PBDebug.log_ai("pokemon #{party[reserve[0]].name} has switch score #{reserves[i][1]}")
    end
    reserves.sort! { |a, b| b[1] <=> a[1] }   # Sort from highest to lowest rated
    threshold = terrible_moves ? REPLACEMENT_THRESHOLD_TERRIBLE_MOVES : REPLACEMENT_THRESHOLD_NORMAL
    if reserves[0][1] < threshold
      if forced_switch
        # Must switch (faint/pivot) — just pick the highest-scored reserve
        PBDebug.log_ai("=> forced switch: sacking #{party[reserves[0][0]].name} (best score #{reserves[0][1]})")
        return reserves[0][0]
      end
      PBDebug.log_ai("=> staying in: all reserves scored < #{threshold} (best: #{reserves[0][1]}), not switching")
      return -1
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
# AIBattler compatibility patch (prevent NoMethodError)
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

  # Override defensive Tera scoring to increase type matchup weights
  alias defensive_tera_score_original get_defensive_tera_score
  def get_defensive_tera_score(score, type, contact)
    # Run original for status/field/weather bonuses
    score = defensive_tera_score_original(score, type, contact)
    # Add extra defensive type matchup scoring on top
    @ai.each_foe_battler(@side) do |b, i|
      b.battler.eachMove do |move|
        next if !move.damagingMove?
        move_type = move.pbCalcType(b.battler)
        if @ai.battle.pbCanTerastallize?(b.index)
          if ["CategoryDependsOnHigherDamageTera",
              "TerapagosCategoryDependsOnHigherDamage"].include?(move.function_code)
            move_type = b.battler.tera_type
          end
        end
        next if @ai.pokemon_can_absorb_move?(self, move, move_type)
        effectiveness = self.effectiveness_of_type_against_single_battler_type(move_type, type, b)
        if Effectiveness.super_effective?(effectiveness)
          score -= 10
        elsif Effectiveness.not_very_effective?(effectiveness)
          score += 10
        elsif Effectiveness.ineffective?(effectiveness)
          score += 20
        end
      end
    end
    return score
  end
end
