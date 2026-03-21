#===============================================================================
# * Frugal Charm
#===============================================================================

class PokemonMartAdapter
  def getPrice(item, selling = false)
    if $game_temp.mart_prices && $game_temp.mart_prices[item]
      if selling
        return $game_temp.mart_prices[item][1] if $game_temp.mart_prices[item][1] >= 0
      elsif $game_temp.mart_prices[item][0] > 0
        return $game_temp.mart_prices[item][0]
      end
    end
    return ($player.activeCharm?(:FRUGALCHARM) ? (GameData::Item.get(item).sell_price * 1) : GameData::Item.get(item).sell_price ) if selling
    return ($player.activeCharm?(:FRUGALCHARM) ? (GameData::Item.get(item).price * 0.75).round : GameData::Item.get(item).price )
  end
end