#===============================================================================
# * Safari Charm
#===============================================================================

# Safari Charm makes Safari allow 50% more steps, balls and catch rate. Also decreases flee rate of Pokemon.
# Gives 50% more balls and steps, and displays message about gaining more of each on exit, into the Safari Zone.
# **Since most of this is done within the event, this is the only way I could think to notify the player of the increase.
class SafariState
  def pbStart(ballcount)
    @start      = [$game_map.map_id, $game_player.x, $game_player.y, $game_player.direction]
    @ballcount  = ballcount
    @inProgress = true
    @steps      = Settings::SAFARI_STEPS
    if $player.activeCharm?(:SAFARICHARM)
      old_step_charm = @steps
      old_ball_charm = @ballcount
	  # Multiplies ball and steps by 1.5 (50%)
      @ballcount *= 1.5 if $player.activeCharm?(:SAFARICHARM)
      @steps     *= 1.5 if $player.activeCharm?(:SAFARICHARM)
      @ballcount  = @ballcount.to_i 
      @steps      = @steps.to_i 
      old_step_charm = @steps - old_step_charm
      old_ball_charm = @ballcount - old_ball_charm
      pbMessage(_INTL("You gained an extra {1} balls and {2} steps from the Safari Charm!", old_ball_charm, old_step_charm))
    end
  end
end
# Modifies just the information shown on the pause screen.
class PokemonPauseMenu
  def pbShowInfo
    safariStepsCharm = Settings::SAFARI_STEPS
    safariStepsCharm *= 1.5 if $player.activeCharm?(:SAFARICHARM)
    safariStepsCharm = safariStepsCharm.to_i
    __safari_pbShowInfo
    return if !pbInSafari?
    if Settings::SAFARI_STEPS <= 0
      @scene.pbShowInfo(_INTL("Balls: {1}", pbSafariState.ballcount))
    else
      @scene.pbShowInfo(_INTL("Steps: {1}/{2}\nBalls: {3}",
                              pbSafariState.steps, safariStepsCharm, pbSafariState.ballcount))
    end
  end
end
# Modifies catch rate when Safari Charm is active.
class SafariBattle
 def pbStartBattle
    begin
      pkmn = @party2[0]
      pbSetSeen(pkmn)
      @scene.pbStartBattle(self)
      pbDisplayPaused(_INTL("Wild {1} appeared!", pkmn.name))
      @scene.pbSafariStart
      weather_data = GameData::BattleWeather.try_get(@weather)
      @scene.pbCommonAnimation(weather_data.animation) if weather_data
      safariBall = GameData::Item.get(:SAFARIBALL).id
      catch_rate = pkmn.species_data.catch_rate
      catch_rate *= 1.5 if activeCharm?(:SAFARICHARM)
      catchFactor  = (catch_rate * 100) / 1275
      catchFactor  = [[catchFactor, 3].max, 20].min
      escapeFactor = (pbEscapeRate(catch_rate) * 100) / 1275
      escapeFactor = [[escapeFactor, 2].max, 20].min
      loop do
        cmd = @scene.pbSafariCommandMenu(0)
        case cmd
        when 0   # Ball
          if pbBoxesFull?
            pbDisplay(_INTL("The boxes are full! You can't catch any more Pokémon!"))
            next
          end
          @ballCount -= 1
          @scene.pbRefresh
          rare = (catchFactor * 1275) / 100
          if safariBall
            pbThrowPokeBall(1, safariBall, rare, true)
            if @caughtPokemon.length > 0
              pbRecordAndStoreCaughtPokemon
              @decision = 4
            end
          end
        when 1   # Bait
          pbDisplayBrief(_INTL("{1} threw some bait at the {2}!", self.pbPlayer.name, pkmn.name))
          @scene.pbThrowBait
          catchFactor  /= 2 if pbRandom(100) < 90   # Harder to catch
          escapeFactor /= 2                       # Less likely to escape
        when 2   # Rock
          pbDisplayBrief(_INTL("{1} threw a rock at the {2}!", self.pbPlayer.name, pkmn.name))
          @scene.pbThrowRock
          catchFactor  *= 2                       # Easier to catch
          escapeFactor *= 2 if pbRandom(100) < 90   # More likely to escape
        when 3   # Run
          pbSEPlay("Battle flee")
          pbDisplayPaused(_INTL("You got away safely!"))
          @decision = 3
        else
          next
        end
        catchFactor  = [[catchFactor, 3].max, 20].min
        escapeFactor = [[escapeFactor, 2].max, 20].min
        # End of round
        if @decision == 0
          if @ballCount <= 0
            pbSEPlay("Safari Zone end")
            pbDisplay(_INTL("PA: You have no Safari Balls left! Game over!"))
            @decision = 2
          elsif pbRandom(100) < 5 * escapeFactor
            pbSEPlay("Battle flee")
            pbDisplay(_INTL("{1} fled!", pkmn.name))
            @decision = 3
          elsif cmd == 1   # Bait
            pbDisplay(_INTL("{1} is eating!", pkmn.name))
          elsif cmd == 2   # Rock
            pbDisplay(_INTL("{1} is angry!", pkmn.name))
          else
            pbDisplay(_INTL("{1} is watching carefully!", pkmn.name))
          end
          # Weather continues
          weather_data = GameData::BattleWeather.try_get(@weather)
          @scene.pbCommonAnimation(weather_data.animation) if weather_data
        end
        break if @decision > 0
      end
      @scene.pbEndBattle(@decision)
    rescue BattleAbortedException
      @decision = 0
      @scene.pbEndBattle(@decision)
    end
    return @decision
  end
end