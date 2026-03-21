#===============================================================================
# * Gene Charm
#===============================================================================

def pbMaxIV(pkmn)
  if rand(1..100) <= LinCharmConfig::MAX_IV_PERC
    stats = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]
    value = rand(1..6)
    indexList = []
    indexList = (0..5).to_a.sample(value)
    for index in indexList do
      pkmn.iv[stats[index]] = 31
    end
    pkmn.calc_stats
  end
end