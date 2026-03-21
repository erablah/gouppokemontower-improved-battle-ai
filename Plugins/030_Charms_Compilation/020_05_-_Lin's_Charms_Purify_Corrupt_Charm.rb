#===============================================================================
# * Purify Charm / Corrupt Charm
#===============================================================================

class Pokemon
  def change_heart_gauge(method, multiplier = 1)
    return if $player.activeCharm?(:CORRUPTCHARM)
    return if !shadowPokemon?
    heart_amounts = {
      # [sending into battle, call to, walking 256 steps, using scent]
      :HARDY   => [110, 300, 100,  90],
      :LONELY  => [ 70, 330, 100, 130],
      :BRAVE   => [130, 270,  90,  80],
      :ADAMANT => [110, 270, 110,  80],
      :NAUGHTY => [120, 270, 110,  70],
      :BOLD    => [110, 270,  90, 100],
      :DOCILE  => [100, 360,  80, 120],
      :RELAXED => [ 90, 270, 110, 100],
      :IMPISH  => [120, 300, 100,  80],
      :LAX     => [100, 270,  90, 110],
      :TIMID   => [ 70, 330, 110, 120],
      :HASTY   => [130, 300,  70, 100],
      :SERIOUS => [100, 330, 110,  90],
      :JOLLY   => [120, 300,  90,  90],
      :NAIVE   => [100, 300, 120,  80],
      :MODEST  => [ 70, 300, 120, 110],
      :MILD    => [ 80, 270, 100, 120],
      :QUIET   => [100, 300, 100, 100],
      :BASHFUL => [ 80, 300,  90, 130],
      :RASH    => [ 90, 300,  90, 120],
      :CALM    => [ 80, 300, 110, 110],
      :GENTLE  => [ 70, 300, 130, 100],
      :SASSY   => [130, 240, 100,  70],
      :CAREFUL => [ 90, 300, 100, 110],
      :QUIRKY  => [130, 270,  80,  90]
    }
    amt = 100
    case method
    when "battle"
      amt = (heart_amounts[@nature]) ? heart_amounts[@nature][0] : 100
    when "call"
      amt = (heart_amounts[@nature]) ? heart_amounts[@nature][1] : 300
    when "walking"
      amt = (heart_amounts[@nature]) ? heart_amounts[@nature][2] : 100
    when "scent"
      amt = (heart_amounts[@nature]) ? heart_amounts[@nature][3] : 100
      amt *= multiplier
    else
      raise _INTL("Unknown heart gauge-changing method: {1}", method.to_s)
    end
    amt *= 1.5 if $player.activeCharm?(:PURECHARM)
    adjustHeart(-amt)
  end
end

#===============================================================================
# * Corrupt Charm
#===============================================================================

def pbCorruptCharm
  $player.able_party.each do |pkmn|
    next if pkmn.shadowPokemon?
    pkmn.makeShadow if rand(100) <= 20
  end
end

EventHandlers.add(:on_player_step_taken, :corrupt_charm,
  proc {
    pbCorruptCharm if $player.activeCharm?(:CORRUPTCHARM)
  }
)

module Battle::CatchAndStoreMixin
  #=============================================================================
  # Throw a Poké Ball
  #=============================================================================
  def pbThrowPokeBall(idxBattler, ball, catch_rate = nil, showPlayer = false)
    # Determine which Pokémon you're throwing the Poké Ball at
    battler = nil
    if opposes?(idxBattler)
      battler = @battlers[idxBattler]
    else
      battler = @battlers[idxBattler].pbDirectOpposing(true)
    end
    battler = battler.allAllies[0] if battler.fainted?
    # Messages
    itemName = GameData::Item.get(ball).name
    if battler.fainted?
      if itemName.starts_with_vowel?
        pbDisplay(_INTL("{1} threw an {2}!", pbPlayer.name, itemName))
      else
        pbDisplay(_INTL("{1} threw a {2}!", pbPlayer.name, itemName))
      end
      pbDisplay(_INTL("But there was no target..."))
      return
    end
    if itemName.starts_with_vowel?
      pbDisplayBrief(_INTL("{1} threw an {2}!", pbPlayer.name, itemName))
    else
      pbDisplayBrief(_INTL("{1} threw a {2}!", pbPlayer.name, itemName))
    end
    # Animation of opposing trainer blocking Poké Balls (unless it's a Snag Ball
    # at a Shadow Pokémon)
    if trainerBattle? && !(GameData::Item.get(ball).is_snag_ball? && battler.shadowPokemon?)
      @scene.pbThrowAndDeflect(ball, 1)
      pbDisplay(_INTL("The Trainer blocked your Poké Ball! Don't be a thief!"))
      return
    end
    # Calculate the number of shakes (4=capture)
    pkmn = battler.pokemon
    @criticalCapture = false
    numShakes = pbCaptureCalc(pkmn, battler, catch_rate, ball)
    PBDebug.log("[Threw Poké Ball] #{itemName}, #{numShakes} shakes (4=capture)")
    # Animation of Ball throw, absorb, shake and capture/burst out
    @scene.pbThrow(ball, numShakes, @criticalCapture, battler.index, showPlayer)
    # Outcome message
    case numShakes
    when 0
      pbDisplay(_INTL("Oh no! The Pokémon broke free!"))
      Battle::PokeBallEffects.onFailCatch(ball, self, battler)
    when 1
      pbDisplay(_INTL("Aww! It appeared to be caught!"))
      Battle::PokeBallEffects.onFailCatch(ball, self, battler)
    when 2
      pbDisplay(_INTL("Aargh! Almost had it!"))
      Battle::PokeBallEffects.onFailCatch(ball, self, battler)
    when 3
      pbDisplay(_INTL("Gah! It was so close, too!"))
      Battle::PokeBallEffects.onFailCatch(ball, self, battler)
    when 4
      pbDisplayBrief(_INTL("Gotcha! {1} was caught!", pkmn.name))
      @scene.pbThrowSuccess   # Play capture success jingle
      pbRemoveFromParty(battler.index, battler.pokemonIndex)
      # Gain Exp
      if Settings::GAIN_EXP_FOR_CAPTURE
        battler.captured = true
        pbGainExp
        battler.captured = false
      end
      battler.pbReset
      if pbAllFainted?(battler.index)
        @decision = (trainerBattle?) ? 1 : 4   # Battle ended by win/capture
      end
      # Modify the Pokémon's properties because of the capture
      if GameData::Item.get(ball).is_snag_ball?
        pkmn.owner = Pokemon::Owner.new_from_trainer(pbPlayer)
      end
      Battle::PokeBallEffects.onCatch(ball, self, pkmn)
      pkmn.poke_ball = ball
      pkmn.makeUnmega if pkmn.mega?
      pkmn.makeUnprimal
      pkmn.makeShadow if $player.activeCharm?(:CORRUPTCHARM)
      pkmn.update_shadow_moves if pkmn.shadowPokemon?
      pkmn.record_first_moves
      # Reset form
      pkmn.forced_form = nil if MultipleForms.hasFunction?(pkmn.species, "getForm")
      @peer.pbOnLeavingBattle(self, pkmn, true, true)
      # Make the Poké Ball and data box disappear
      @scene.pbHideCaptureBall(idxBattler)
      # Save the Pokémon for storage at the end of battle
      @caughtPokemon.push(pkmn)
    end
    if numShakes != 4
      @first_poke_ball = ball if !@poke_ball_failed
      @poke_ball_failed = true
    end
  end
end