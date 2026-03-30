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

    def initialize
      @turns = 0
      @turn_log = []
      @user_fainted = false
      @target_fainted = false
      @user_ko_turn = nil
      @target_ko_turn = nil
      @user_got_action = false
      @target_got_action = false
    end

    def user_wins?;       @target_fainted && !@user_fainted; end
    def target_wins?;     @user_fainted && !@target_fainted; end
    def user_can_ohko?;   @target_ko_turn == 1; end
    def target_can_ohko?; @user_ko_turn == 1; end
    def user_can_2hko?;   @target_ko_turn && @target_ko_turn <= 2; end
    def target_can_2hko?; @user_ko_turn && @user_ko_turn <= 2; end
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
    pre_switch = options.fetch(:pre_switch, nil)
    sim = create_battle_copy
    result = SimulationResult.new

    # saved_debug = $DEBUG
    # $DEBUG = false

    # Apply pre-switches before the turn loop (no opponent action)
    if pre_switch
      pre_switch.each do |battler_idx, party_idx|
        sim.pbRecallAndReplace(battler_idx, party_idx)
        sim.pbOnBattlerEnteringBattle(battler_idx)
      end
    end

    # Pre-compute priority moves from cache for KO interception.
    # Skip when switches are involved — cached damage is for the original battlers.
    user_priority_moves = []
    target_priority_moves = []
    has_switches = pre_switch ||
                   user_actions.any? { |a| a.is_a?(Array) && a[0] == :switch } ||
                   target_actions.any? { |a| a.is_a?(Array) && a[0] == :switch }

    if max_turns > 1 && !has_switches
      user_ai = @battlers[user_index]
      target_ai = @battlers[target_index]
      if user_ai && target_ai
        damage_moves(user_ai, target_ai).each do |move_id, data|
          next unless data[:move].priority > 0
          user_priority_moves << { id: move_id, dmg: data[:dmg], pri: data[:move].priority }
        end
        damage_moves(target_ai, user_ai).each do |move_id, data|
          next unless data[:move].priority > 0
          target_priority_moves << { id: move_id, dmg: data[:dmg], pri: data[:move].priority }
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

        # --- Resolve user action ---
        # Clamp to last action instead of cycling, so switches happen only once
        user_action_idx = [turn - 1, user_actions.length - 1].min
        user_action = user_actions[user_action_idx]
        if user_action.is_a?(Array) && user_action[0] == :switch
          sim.choices[user_index] = [:SwitchOut, user_action[1], nil]
        else
          user_move = user.moves.find { |m| m.id == user_action }
          next unless user_move
          # Priority move KO interception
          user_priority_moves.each do |pm|
            next unless pm[:dmg] >= target.hp
            pri_move = user.moves.find { |m| m.id == pm[:id] }
            if pri_move
              user_move = pri_move
              break
            end
          end
          user_move_idx = user.moves.index(user_move) || 0
          sim.choices[user_index] = [:UseMove, user_move_idx, user_move, target_index, 0]
        end

        # --- Resolve target action ---
        # Clamp to last action instead of cycling
        target_action_idx = target_actions.empty? ? nil : [turn - 1, target_actions.length - 1].min
        target_action = target_action_idx ? target_actions[target_action_idx] : nil
        if target_action.is_a?(Array) && target_action[0] == :switch
          sim.choices[target_index] = [:SwitchOut, target_action[1], nil]
        elsif target_action.is_a?(Symbol)
          target_move = target.moves.find { |m| m.id == target_action }
          if target_move
            # Priority move KO interception
            target_priority_moves.each do |pm|
              next unless pm[:dmg] >= user.hp
              pri_move = target.moves.find { |m| m.id == pm[:id] }
              if pri_move
                target_move = pri_move
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

        # Run actual battle phases
        switch_triggered = catch(SIM_SWITCH_TRIGGERED) do
          sim.pbAttackPhase
          tick_scene
          sim.pbEndOfRoundPhase
          tick_scene
          false
        end

        # Update battler references after phases (or abrupt switch throw)
        user = sim.battlers[user_index]
        target = sim.battlers[target_index]

        # Determine if each side got action (check lastRoundMoved)
        user_acted = user.lastRoundMoved == turn + turn_offset
        target_acted = target.lastRoundMoved == turn + turn_offset
        result.user_got_action ||= user_acted
        result.target_got_action ||= target_acted

        # Log results (recorded even if a switch interrupted the turn)
        result.turn_log << {
          turn: turn,
          user_hp_before: user_hp_before,
          target_hp_before: target_hp_before,
          user_hp_after: user.hp,
          target_hp_after: target.hp,
          user_acted: user_acted,
          target_acted: target_acted
        }

        break if switch_triggered.nil?
        break if sim.decision > 0
      end

    result.user_fainted = user.fainted?
    result.target_fainted = target.fainted?
    result.user_hp = user.hp
    result.target_hp = target.hp
    result.user_ko_turn = result.turns if user.fainted?
    result.target_ko_turn = result.turns if target.fainted?
    result
  ensure
    # $DEBUG = saved_debug
  end

  #-----------------------------------------------------------------------------
  # Simulate a switch-in and return the new battler state.
  #-----------------------------------------------------------------------------
  def simulate_switch(battler_index, party_index)
    saved_debug = $DEBUG
    $DEBUG = false
    tick_scene
    sim = create_battle_copy
    sim.pbRecallAndReplace(battler_index, party_index)
    sim.pbOnBattlerEnteringBattle(battler_index)
    tick_scene
    sim.battlers[battler_index]
  ensure
    $DEBUG = saved_debug
  end
end
