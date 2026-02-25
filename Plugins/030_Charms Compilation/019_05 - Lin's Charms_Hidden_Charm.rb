#===============================================================================
# * Hidden Charm
#===============================================================================

def pbHiddenAbility(pkmn)
  abils = pkmn.getAbilityList
  if abils.length < 2
    index = 2
  else
    index = rand(2..abils.length)
  end
  pkmn.ability_index = index if rand(1..100) <= LinCharmConfig::HIDDEN_ABILITY_PERC
end