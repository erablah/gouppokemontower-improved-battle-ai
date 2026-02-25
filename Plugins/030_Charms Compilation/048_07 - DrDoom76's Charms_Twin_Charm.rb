#===============================================================================
# * Twin Charm / Coin Charm if you want to add pbReceiveCoins method to put random coins on the ground
#===============================================================================

def pbItemBall(item, quantity = 1)
  item = GameData::Item.get(item)
  return false if !item || quantity < 1
  event_name = $game_map.events[@event_id].name  # Use the event_id to get the event and its name
  if $player.activeCharm?(:TWINCHARM) && !item.is_important?
    quantity *= 2 if event_name[/hiddenitem/i]
  end
  itemname = (quantity > 1) ? item.portion_name_plural : item.portion_name
  pocket = item.pocket
  move = item.move
  if $bag.add(item, quantity)   # If item can be picked up
    meName = (item.is_key_item?) ? "Key item get" : "Item get"
    if item == :DNASPLICERS
      pbMessage("\\me[#{meName}]" + _INTL("You found \\c[1]{1}\\c[0]!", itemname) + "\\wtnp[40]")
    elsif item.is_machine?   # TM or HM
      if quantity > 1
        pbMessage("\\me[Machine get]" + _INTL("You found {1} \\c[1]{2} {3}\\c[0]!",
                                              quantity, itemname, GameData::Move.get(move).name) + "\\wtnp[70]")
      else
        pbMessage("\\me[Machine get]" + _INTL("You found \\c[1]{1} {2}\\c[0]!",
                                              itemname, GameData::Move.get(move).name) + "\\wtnp[70]")
      end
    elsif quantity > 1
      pbMessage("\\me[#{meName}]" + _INTL("You found {1} \\c[1]{2}\\c[0]!", quantity, itemname) + "\\wtnp[40]")
    elsif itemname.starts_with_vowel?
      pbMessage("\\me[#{meName}]" + _INTL("You found an \\c[1]{1}\\c[0]!", itemname) + "\\wtnp[40]")
    else
      pbMessage("\\me[#{meName}]" + _INTL("You found a \\c[1]{1}\\c[0]!", itemname) + "\\wtnp[40]")
    end
    pbMessage(_INTL("\\j[{1},을,를] 가방의 <icon=bagPocket{2}>\\c[1]{3}\\c[0] 주머니에 넣었다.",
                    itemname, pocket, PokemonBag.pocket_names[pocket - 1]))
    return true
  end
  # Can't add the item
  if item.is_machine?   # TM or HM
    if quantity > 1
      pbMessage(_INTL("You found {1} \\c[1]{2} {3}\\c[0]!", quantity, itemname, GameData::Move.get(move).name))
    else
      pbMessage(_INTL("You found \\c[1]{1} {2}\\c[0]!", itemname, GameData::Move.get(move).name))
    end
  elsif quantity > 1
    pbMessage(_INTL("You found {1} \\c[1]{2}\\c[0]!", quantity, itemname))
  elsif itemname.starts_with_vowel?
    pbMessage(_INTL("You found an \\c[1]{1}\\c[0]!", itemname))
  else
    pbMessage(_INTL("You found a \\c[1]{1}\\c[0]!", itemname))
  end
  pbMessage(_INTL("But your Bag is full..."))
  return false
end

#Finding Coins
def pbReceiveCoins(quantity)
  if $player.activeCharm?(:COINCHARM)
    quantity *= 3
  end
  $player.coins += quantity
  pbMessage(_INTL("You have received {1} coins!", quantity))
end