#===============================================================================
# Battle Simulation: Run actual battle phases on deep copies.
#===============================================================================

class Battle::AI
  #=============================================================================
  # SimulationResult: Output from battle simulation.
  #=============================================================================
  class SimulationResult
    attr_accessor :turns, :turn_log
    attr_accessor :user_fainted, :target_fainted
    attr_accessor :user_hp, :target_hp
    attr_accessor :user_ko_turn, :target_ko_turn
    attr_accessor :user_got_action, :target_got_action
    attr_accessor :user_succeeded, :target_succeeded
    attr_accessor :terminated_by_switch, :switch_type, :switch_battler_index

    def initialize
      @turns = 0
      @turn_log = []
      @user_fainted = false
      @target_fainted = false
      @user_ko_turn = nil
      @target_ko_turn = nil
      @user_got_action = false
      @target_got_action = false
      @user_succeeded  = false
      @target_succeeded = false
      @terminated_by_switch = false
      @switch_type = nil
      @switch_battler_index = nil
    end

    def user_wins?;       @target_fainted && !@user_fainted; end
    def target_wins?;     @user_fainted && !@target_fainted; end
    def user_can_ohko?;   @target_fainted && !@target_got_action; end
    def target_can_ohko?; @user_fainted && !@user_got_action; end
  end

  def resolve_sim_action_move(battler, action)
    return nil unless battler

    if action.is_a?(Hash)
      base_id = action[:move_id]
      return nil unless base_id
      move = battler.moves.find { |m| m.id == base_id }
      if !move && battler.respond_to?(:baseMoves) && !battler.baseMoves.empty?
        battler.baseMoves.each_with_index do |base_move, idx|
          next if !base_move || base_move.id != base_id
          move = battler.moves[idx] || base_move
          break
        end
      end
      return nil unless move
      return move unless action[:zmove]

      move_idx = battler.moves.index(move) || 0
      return move.convert_zmove(battler, battler.battle, move_idx, true)
    end

    return nil unless action.is_a?(Symbol)
    move = battler.moves.find { |m| m.id == action }
    return move if move

    action_data = GameData::Move.try_get(action)
    if action_data&.zMove?
      item_data = GameData::Item.try_get(battler.item_id) if battler.respond_to?(:item_id)
      pkmn =
        if battler.respond_to?(:visiblePokemon)
          battler.visiblePokemon
        else
          battler.pokemon
        end
      battler.moves.each_with_index do |base_move, idx|
        next if !base_move
        if item_data && pkmn && base_move.get_compatible_zmove(item_data, pkmn) == action
          zmove = base_move.make_zmove(action, battler.battle)
          zmove.specialUseZMove = true if zmove.respond_to?(:specialUseZMove=)
          return zmove
        end
        zmove = base_move.convert_zmove(battler, battler.battle, idx, true)
        return zmove if zmove&.id == action
      end
      if battler.respond_to?(:baseMoves) && !battler.baseMoves.empty?
        battler.baseMoves.each_with_index do |base_move, idx|
          next if !base_move
          if item_data && pkmn && base_move.get_compatible_zmove(item_data, pkmn) == action
            zmove = base_move.make_zmove(action, battler.battle)
            zmove.specialUseZMove = true if zmove.respond_to?(:specialUseZMove=)
            return zmove
          end
          zmove = base_move.convert_zmove(battler, battler.battle, idx, true)
          return zmove if zmove&.id == action
        end
      end
    end

    if battler.respond_to?(:baseMoves) && !battler.baseMoves.empty?
      battler.baseMoves.each_with_index do |base_move, idx|
        next if !base_move
        next if base_move.id != action
        return battler.moves[idx]
      end
    end

    return nil if !action_data || !action_data.dynamaxMove?
    dynahash = GameData::Move.get_generic_dynamax_moves
    battler.moves.each do |candidate|
      next if !candidate
      next if candidate.get_compatible_dynamax_move(battler, dynahash) != action
      PBDebug.log_ai("[AI SIM] Resolved reverted Dynamax move #{action} to base move #{candidate.id} for #{battler.pbThis}")
      return candidate
    end
    nil
  end

  #-----------------------------------------------------------------------------
  # Simulate a full battle with action sequences.
  #
  # user_index, target_index: battler indices
  # user_actions, target_actions: Arrays of actions, each action is either:
  #   - Symbol (move ID)       → use that move
  #   - [:switch, party_index] → switch to that party member
  # options:
  #   :max_turns (default 10)
  #   :pre_switch - Hash { battler_index => party_index }
  #     Applies switch-in effects (hazards, Intimidate, weather, etc.)
  #     before the turn loop starts, without giving the opponent an action.
  #     Used for faint replacements and pivot switch-ins.
  #-----------------------------------------------------------------------------
  def simulate_battle(user_index, target_index, user_actions, target_actions, options = {})
    max_turns = options.fetch(:max_turns, 10)
    heal_user_full = options.fetch(:heal_user_full, false)
    sim = options[:sim] || create_battle_copy
    result = SimulationResult.new

    # Heal user to full HP before simulation (used by item scoring)
    if heal_user_full
      sim_user = sim.battlers[user_index]
      sim_user.hp = sim_user.totalhp
    end

    # Pre-compute priority moves for KO interception.
    user_priority_moves = []
    target_priority_moves = []

    if max_turns > 1
      if options[:sim]
        if options[:pre_switch]
          pre_switch = options[:pre_switch]
          damage_moves_with_switch(user_index, target_index, pre_switch)&.each_value do |data|
            next unless data[:move].priority > 0
            user_priority_moves << { action: data[:action], dmg: data[:dmg], pri: data[:move].priority, zmove: data[:zmove] }
          end
          damage_moves_with_switch(target_index, user_index, pre_switch)&.each_value do |data|
            next unless data[:move].priority > 0
            target_priority_moves << { action: data[:action], dmg: data[:dmg], pri: data[:move].priority, zmove: data[:zmove] }
          end
        end
      else
        # Use cached damage from current battlers
        user_ai = @battlers[user_index]
        target_ai = @battlers[target_index]
        if user_ai && target_ai
          damage_moves(user_ai, target_ai).each do |_move_key, data|
            next unless data[:move].priority > 0
            user_priority_moves << { action: data[:action], dmg: data[:dmg], pri: data[:move].priority, zmove: data[:zmove] }
          end
          damage_moves(target_ai, user_ai).each do |_move_key, data|
            next unless data[:move].priority > 0
            target_priority_moves << { action: data[:action], dmg: data[:dmg], pri: data[:move].priority, zmove: data[:zmove] }
          end
        end
      end
    end

    user = sim.battlers[user_index]
    target = sim.battlers[target_index]
    # Offset sim turnCount above the real battle's turnCount so that
    # movedThisRound? (lastRoundMoved == turnCount) never collides with
    # leftover lastRoundMoved values from the real battle.
    turn_offset = @battle.turnCount + 1

      (1..max_turns).each do |turn|
        break if user.fainted? || target.fainted?

        result.turns = turn
        sim.instance_variable_set(:@turnCount, turn + turn_offset)
        stop_after_turn = false

        # --- Resolve user action ---
        # Clamp to last action instead of cycling, so switches happen only once
        user_action_idx = [turn - 1, user_actions.length - 1].min
        user_action = user_action_idx >= 0 ? user_actions[user_action_idx] : nil
        user_move = resolve_sim_action_move(user, user_action)
        next unless user_move
        stop_after_turn ||= user_move.respond_to?(:zMove?) && user_move.zMove?
        # Priority move KO interception.
        if turn > 1 || options[:sim]
          user_priority_moves.each do |pm|
            next unless pm[:dmg] >= target.hp
            pri_move = resolve_sim_action_move(user, pm[:action])
            if pri_move
              PBDebug.log_ai("[AI SIM] KO priority interception proc: #{user.pbThis} swaps #{user_move.name} -> #{pri_move.name} against #{target.pbThis} on turn #{turn} (predicted #{pm[:dmg]} >= #{target.hp} HP)")
              user_move = pri_move
              stop_after_turn ||= user_move.respond_to?(:zMove?) && user_move.zMove?
              break
            end
          end
        end
        if user.usingMultiTurnAttack?
          PBDebug.log_ai("AI SIM: User #{user.pbThis} locked into a multi-turn attack") if $DEBUG
        else
          user_move_idx = user.moves.index(user_move) || 0
          sim.choices[user_index] = [:UseMove, user_move_idx, user_move, target_index, 0]
        end

        # --- Resolve target action ---
        # Clamp to last action instead of cycling
        target_action_idx = target_actions.empty? ? nil : [turn - 1, target_actions.length - 1].min
        target_action = target_action_idx ? target_actions[target_action_idx] : nil
        if target.usingMultiTurnAttack?
          PBDebug.log_ai("AI SIM: Target #{target.pbThis} locked into a multi-turn attack") if $DEBUG
        elsif target_action.is_a?(Symbol)
          target_move = resolve_sim_action_move(target, target_action)
          if target_move
            stop_after_turn ||= target_move.respond_to?(:zMove?) && target_move.zMove?
            # Priority move KO interception
            target_priority_moves.each do |pm|
              next unless pm[:dmg] >= user.hp
              pri_move = resolve_sim_action_move(target, pm[:action])
              if pri_move
                PBDebug.log_ai("[AI SIM] KO priority interception proc: #{target.pbThis} swaps #{target_move.name} -> #{pri_move.name} against #{user.pbThis} on turn #{turn} (predicted #{pm[:dmg]} >= #{user.hp} HP)")
                target_move = pri_move
                stop_after_turn ||= target_move.respond_to?(:zMove?) && target_move.zMove?
                break
              end
            end
            target_move_idx = target.moves.index(target_move) || 0
            sim.choices[target_index] = [:UseMove, target_move_idx, target_move, user_index, 0]
          else
            sim.choices[target_index] = [:None]
          end
        else
          sim.choices[target_index] = [:None]
        end

        user_hp_before = user.hp
        target_hp_before = target.hp

        # Run attack phase first and snapshot action results before EOR faint
        # cleanup can reset move-tracking fields on battlers that acted.
        switch_event = catch(SIM_SWITCH_TRIGGERED) do
          sim.pbAttackPhase
          tick_scene
          false
        end

        # Update battler references after the attack phase (or abrupt switch throw)
        user = sim.battlers[user_index]
        target = sim.battlers[target_index]
        user_action_turn = user.instance_variable_get(:@_sim_action_turn)
        target_action_turn = target.instance_variable_get(:@_sim_action_turn)
        user_succeeded_on_action = user.instance_variable_get(:@_sim_action_succeeded)
        target_succeeded_on_action = target.instance_variable_get(:@_sim_action_succeeded)

        # Determine if each side got an action from attack-phase state, before a
        # later faint can call pbInitEffects(false) and wipe lastRoundMoved.
        user_acted = (user_action_turn == turn + turn_offset) || (user.lastRoundMoved == turn + turn_offset)
        target_acted = (target_action_turn == turn + turn_offset) || (target.lastRoundMoved == turn + turn_offset)
        user_failed = if user_acted
                        user_succeeded_on_action.nil? ? user.lastMoveFailed : !user_succeeded_on_action
                      else
                        user.lastMoveFailed
                      end
        target_failed = if target_acted
                          target_succeeded_on_action.nil? ? target.lastMoveFailed : !target_succeeded_on_action
                        else
                          target.lastMoveFailed
                        end

        unless switch_event
          switch_event = catch(SIM_SWITCH_TRIGGERED) do
            sim.pbEndOfRoundPhase
            tick_scene
            false
          end
          user = sim.battlers[user_index]
          target = sim.battlers[target_index]
        end

        if switch_event
          result.terminated_by_switch = true
          result.switch_type = switch_event[:reason]
          result.switch_battler_index = switch_event[:battler_index]
        end

        # Live self-switch moves like Baton Pass/U-turn throw out before
        # pbEndTurn can mark lastRoundMoved, so credit that battler here.
        if switch_event && switch_event[:reason] == :live_switch
          case switch_event[:battler_index]
          when user_index
            user_acted = true
            user_failed = false
          when target_index
            target_acted = true
            target_failed = false
          end
        end

        result.user_got_action ||= user_acted
        result.target_got_action ||= target_acted
        result.user_succeeded ||= (user_acted && !user_failed)
        result.target_succeeded ||= (target_acted && !target_failed)

        # Log results (recorded even if a switch interrupted the turn)
        result.turn_log << {
          turn: turn,
          user_hp_before: user_hp_before,
          target_hp_before: target_hp_before,
          user_hp_after: user.hp,
          target_hp_after: target.hp,
          user_acted: user_acted,
          user_succeeded: (user_acted && !user_failed),
          target_acted: target_acted,
          target_succeeded: (target_acted && !target_failed)
        }

        break if switch_event
        break if sim.decision > 0
        break if stop_after_turn
      end

    result.user_fainted = user.fainted?
    result.target_fainted = target.fainted?
    result.user_hp = user.hp
    result.target_hp = target.hp
    result.user_ko_turn = result.turns if user.fainted?
    result.target_ko_turn = result.turns if target.fainted?
    result
  end

  #-----------------------------------------------------------------------------
  # Apply assumed form changes (Mega/Dynamax/Tera) to a sim battler after
  # switch-in. Only one mechanic applies per battler (mutually exclusive).
  #-----------------------------------------------------------------------------
  def apply_sim_form_changes(sim, battler_index)
    battler = sim.battlers[battler_index]
    return unless battler && battler.pokemon && !battler.fainted?
    # Mega Evolution
    if sim.pbCanMegaEvolve?(battler_index)
      battler.pokemon.makeMega
      battler.form_update(true)
      return
    end
    # Dynamax
    if sim.pbCanDynamax?(battler_index)
      battler.effects[PBEffects::Dynamax] = Settings::DYNAMAX_TURNS
      battler.makeDynamax
      battler.display_dynamax_moves
      return
    end
    # Tera for Terapagos / Ogerpon (form-changing tera species)
    if [:TERAPAGOS, :OGERPON].include?(battler.species) &&
       sim.pbCanTerastallize?(battler_index)
      battler.pokemon.terastallized = true
      battler.form_update(true)
    end
  end

  #-----------------------------------------------------------------------------
  # Create a battle sim with pre-switches + form changes applied.
  # If options[:voluntary_switch] is true, also simulates the rest of the 
  # turn where the opponent attacks the incoming battler.
  #-----------------------------------------------------------------------------
  def create_switched_sim(pre_switch, options = {})
    sim = create_battle_copy
    pre_switch.each do |battler_idx, party_idx|
      tick_scene
      sim.pbRecallAndReplace(battler_idx, party_idx)
      tick_scene
      sim.pbOnBattlerEnteringBattle(battler_idx)
      if options[:voluntary_switch] && options[:foe_move_id]
        # Simulate the foe hitting the incoming pokemon
        target_idx = options[:target_index]
        user_idx = pre_switch.keys.first
        foe_action = options[:foe_move_id]
        
        atk = sim.battlers[target_idx]
        foe_move = resolve_sim_action_move(atk, foe_action)
        if foe_move
          sim.choices[target_idx] = [:UseMove, atk.moves.index(foe_move) || 0, foe_move, user_idx, 0]
        else
          sim.choices[target_idx] = [:None]
        end
        sim.choices[user_idx] = [:None]
        
        sim.instance_variable_set(:@turnCount, @battle.turnCount + 1)
        catch(SIM_SWITCH_TRIGGERED) do
          sim.pbAttackPhase
          tick_scene
          sim.pbEndOfRoundPhase
          tick_scene
        end
      end
      
      apply_sim_form_changes(sim, battler_idx)
    end
    sim
  end
end
