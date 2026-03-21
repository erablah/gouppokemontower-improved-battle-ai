#===============================================================================
# * Heart Charm
#===============================================================================

class Battle::Battler
  def pbProcessTurn(choice, tryFlee = true)
    return false if fainted?
    # Wild roaming Pokémon always flee if possible
      if tryFlee && wild? &&
       @battle.rules["alwaysflee"] && @battle.pbCanRun?(@index) &&
       (!$player.activeCharm?(:HEARTCHARM) || (rand(100) < DrCharmConfig::HEART_CHARM_FLED))
      pbBeginTurn(choice)
      pbSEPlay("Battle flee")
      @battle.pbDisplay(_INTL("{1} fled from battle!", pbThis))
      @battle.decision = 3
      pbEndTurn(choice)
      return true
    end
    # Shift with the battler next to this one
    if choice[0] == :Shift
      idxOther = -1
      case @battle.pbSideSize(@index)
      when 2
        idxOther = (@index + 2) % 4
      when 3
        if @index != 2 && @index != 3   # If not in middle spot already
          idxOther = (@index.even?) ? 2 : 3
        end
      end
      if idxOther >= 0
        @battle.pbSwapBattlers(@index, idxOther)
        case @battle.pbSideSize(@index)
        when 2
          @battle.pbDisplay(_INTL("{1} moved across!", pbThis))
        when 3
          @battle.pbDisplay(_INTL("{1} moved to the center!", pbThis))
        end
      end
      pbBeginTurn(choice)
      pbCancelMoves
      @lastRoundMoved = @battle.turnCount   # Done something this round
      return true
    end
    # If this battler's action for this round wasn't "use a move"
    if choice[0] != :UseMove
      # Clean up effects that end at battler's turn
      pbBeginTurn(choice)
      pbEndTurn(choice)
      return false
    end
    # Use the move
    PBDebug.log("[Use move] #{pbThis} (#{@index}) used #{choice[2].name}")
    PBDebug.logonerr { pbUseMove(choice, choice[2] == @battle.struggle) }
    @battle.pbJudge
    # Update priority order
    @battle.pbCalculatePriority if Settings::RECALCULATE_TURN_ORDER_AFTER_SPEED_CHANGES
    return true
  end
end
  
  # Party Pokémon gain happiness from walking
EventHandlers.add(:on_player_step_taken, :gain_happiness,
  proc {
    $PokemonGlobal.happinessSteps = 0 if !$PokemonGlobal.happinessSteps
    $PokemonGlobal.happinessSteps += 1
    next if $PokemonGlobal.happinessSteps < 128
    $player.able_party.each do |pkmn|
      pkmn.changeHappiness("walking") if rand(2) == 0
      pkmn.changeHappiness("walking") if $player.activeCharm?(:HEARTCHARM)
    end
    $PokemonGlobal.happinessSteps = 0
  }
)