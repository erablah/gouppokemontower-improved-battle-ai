#===============================================================================
# * Heritage Charm
#===============================================================================

def pbEggMove(pkmn)
  if rand(1..100) <= LinCharmConfig::EGG_MOVE_PERC
    pkmnMoves = []
    pkmn.moves.each { |m| pkmnMoves.push(m.id)}
    egg_moves = pkmn.species_data.get_egg_moves
    value = rand(LinCharmConfig::EGG_MOVE)
    movesList = egg_moves.to_a.sample(value)
    for moves in movesList do
      pkmn.learn_move(moves)
    end
  end
end