#===============================================================================
# [AI_Improved.rb] - Safe Move-Scoring AI for Pokémon Essentials v21.1
# - Deluxe Battle Kit(DBK) / 더블 / 레이드 호환
#===============================================================================
class Battle::AI
  #---------------------------------------------------------------------------
  # [Helper] 효과 배율을 float로 변환
  #---------------------------------------------------------------------------
  def pbGetEffectivenessMult(effectiveness_id)
    return effectiveness_id.to_f / 100.0
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
        badMoves = true if pbAIRandom(100) < 80
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
    if $INTERNAL
      PBDebug.log_ai("Move choices for #{@user.name} with threshold: #{threshold}: ")
      choices.each_with_index do |c, i|
        chance = sprintf("%5.1f", (c[3] > 0) ? 100.0 * c[3] / total_score : 0)
        log_msg = "   * #{chance}% to use #{c[4].name}"
        log_msg += " (target #{c[2]})" if c[2] >= 0
        log_msg += ": score #{c[1]}"
        PBDebug.log(log_msg)
      end
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
        PBDebug.log("   => will use #{move_name} (target #{@battle.choices[user_battler.index][3]})")
      else
        PBDebug.log("   => will use #{move_name}")
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
      PBDebug.log("   => no good replacement Pokémon, will not switch after all")
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
      PBDebug.log("   => will use Baton Pass to switch out")
      return true
    elsif @battle.pbRegisterSwitch(@user.index, idxParty)
      PBDebug.log("   => will switch with #{@battle.pbParty(@user.index)[idxParty].name}")
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
      PBDebug.log("pokemon #{party[reserve[0]].name} has switch score #{reserves[i][1]}")
    end
    reserves.sort! { |a, b| b[1] <=> a[1] }   # Sort from highest to lowest rated
    # Don't bother choosing to switch if all replacements are poorly rated
    if @trainer.high_skill? && !forced_switch
      return -1 if reserves[0][1] < 100   # If best replacement rated at <100, don't switch
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
  def predicted_damage(move:, user:, target:)
    prev_user = @ai.user
    prev_target = @ai.target
    user_idx = prev_user.battler.index
    target_idx = prev_target.battler.index

    # Save the original battler objects (untouched)
    prev_user_battler = @ai.battle.battlers[user_idx]
    prev_target_battler = @ai.battle.battlers[target_idx]

    # Create fresh temporary battlers for the simulation slots
    temp_user_battler = Battle::Battler.new(@ai.battle, user_idx)
    temp_user_battler.pbInitialize(user.pokemon, 0)
    @ai.battle.battlers[user_idx] = temp_user_battler

    temp_target_battler = Battle::Battler.new(@ai.battle, target_idx)
    temp_target_battler.pbInitialize(target.pokemon, 0)
    @ai.battle.battlers[target_idx] = temp_target_battler

    @ai.instance_variable_set(:@user, user)
    @ai.instance_variable_set(:@target, target)

    begin
      return self.rough_damage
    ensure
      # Restore originals — they were never mutated
      @ai.battle.battlers[user_idx] = prev_user_battler
      @ai.battle.battlers[target_idx] = prev_target_battler
      @ai.instance_variable_set(:@user, prev_user)
      @ai.instance_variable_set(:@target, prev_target)
    end
  end
end
