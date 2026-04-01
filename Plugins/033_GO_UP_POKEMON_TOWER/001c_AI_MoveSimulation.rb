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
    end

    def user_wins?;       @target_fainted && !@user_fainted; end
    def target_wins?;     @user_fainted && !@target_fainted; end
    def user_can_ohko?;   @target_fainted && !@target_got_action; end
    def target_can_ohko?; @user_fainted && !@user_got_action; end
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
        # Skip priority cache for explicit sim
      else
        # Use cached damage from current battlers
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
        user_action = user_action_idx >= 0 ? user_actions[user_action_idx] : nil
        user_move = user.moves.find { |m| m.id == user_action }
        next unless user_move
        # Priority move KO interception (skip turn 1: test the actual move first)
        if turn > 1
          user_priority_moves.each do |pm|
            next unless pm[:dmg] >= target.hp
            pri_move = user.moves.find { |m| m.id == pm[:id] }
            if pri_move
              user_move = pri_move
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

        # Run attack phase first and snapshot action results before EOR faint
        # cleanup can reset move-tracking fields on battlers that acted.
        switch_triggered = catch(SIM_SWITCH_TRIGGERED) do
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
        user_acted = (user_action_turn == turn + turn_offset)
        target_acted = (target_action_turn == turn + turn_offset)
        user_failed = user_acted ? !user_succeeded_on_action : user.lastMoveFailed
        target_failed = target_acted ? !target_succeeded_on_action : target.lastMoveFailed

        unless switch_triggered
          switch_triggered = catch(SIM_SWITCH_TRIGGERED) do
            sim.pbEndOfRoundPhase
            tick_scene
            false
          end
          user = sim.battlers[user_index]
          target = sim.battlers[target_index]
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
  end

  #-----------------------------------------------------------------------------
  # Apply assumed form changes (Mega/Dynamax/Tera) to a sim battler after
  # switch-in. Only one mechanic applies per battler (mutually exclusive).
  #-----------------------------------------------------------------------------
  def apply_sim_form_changes(sim, battler_index)
    battler = sim.battlers[battler_index]
    return unless battler && battler.pokemon && !battler.fainted?
    # Mega Evolution
    if (sim.pbCanMegaEvolve?(battler_index) rescue false)
      battler.pokemon.makeMega
      battler.form_update(true)
      return
    end
    # Dynamax
    if (sim.pbCanDynamax?(battler_index) rescue false)
      battler.effects[PBEffects::Dynamax] = Settings::DYNAMAX_TURNS
      battler.makeDynamax
      battler.display_dynamax_moves
      return
    end
    # Tera for Terapagos / Ogerpon (form-changing tera species)
    if [:TERAPAGOS, :OGERPON].include?(battler.species) &&
       (sim.pbCanTerastallize?(battler_index) rescue false)
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
        foe_move_id = options[:foe_move_id]
        
        atk = sim.battlers[target_idx]
        foe_move = atk.moves.find { |m| m.id == foe_move_id }
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
