#===============================================================================
# * Trading Charm
#===============================================================================

# Trading Charm - Adds IV and has a chance to make trade shiny.
def pbStartTrade(pokemonIndex, newpoke, nickname, trainerName, trainerGender = 0)
  $stats.trade_count += 1
  tradingCharmIV = DrCharmConfig::TRADING_CHARM_IV
  myPokemon = $player.party[pokemonIndex]
  yourPokemon = nil
  resetmoves = true
  if newpoke.is_a?(Pokemon)
    newpoke.owner = Pokemon::Owner.new_foreign(trainerName, trainerGender)
    yourPokemon = newpoke
    resetmoves = false
  else
    species_data = GameData::Species.try_get(newpoke)
    raise _INTL("Species {1} does not exist.", newpoke) if !species_data
    yourPokemon = Pokemon.new(species_data.id, myPokemon.level)
    yourPokemon.owner = Pokemon::Owner.new_foreign(trainerName, trainerGender)
  end
  yourPokemon.name          = nickname
  yourPokemon.obtain_method = 2   # traded
  # While Trading Charm is active, will add Trading Charm IV setting to every IV stat.
  if $player.activeCharm?(:TRADINGCHARM)
    GameData::Stat.each_main do |s|
      stat_id = s.id
	  # Adds 5 IVs to each stat.
      yourPokemon.iv[stat_id] = [yourPokemon.iv[stat_id] + tradingCharmIV, 31].min if yourPokemon.iv[stat_id]
	  end
	# Adds a chance to receive a shiny pokemon from a trade. Default setting: 20 (%)
	  if rand(100) < DrCharmConfig::TRADING_CHARM_SHINY
		yourPokemon.shiny = true
	  end
   end
  yourPokemon.reset_moves if resetmoves
  yourPokemon.record_first_moves
  pbFadeOutInWithMusic do
    evo = PokemonTrade_Scene.new
    evo.pbStartScreen(myPokemon, yourPokemon, $player.name, trainerName)
    evo.pbTrade
    evo.pbEndScreen
  end
  $player.party[pokemonIndex] = yourPokemon
end