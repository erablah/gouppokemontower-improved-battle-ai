#===============================================================================
# * Crafting Charm
#===============================================================================
# * Requires Item Crafter UI Plus or Simple item crafting system
#===============================================================================

# The Crafting Charm is made for the two most popular Item Crafting Plugins.
# It will work with either Item Crafter UI Plus or Simple Item Crafting System.
# DO NOT USE BOTH.

class ItemCraft_Scene
	 if PluginManager.installed?("Item Crafting UI Plus")
	   def pbCraftItem(stock)
		index = 0
		volume = 1
		@stock = stock
		@switching = false
		refreshNumbers(index,volume)
		pbRedrawItem(index,volume)
		pbFadeInAndShow(@sprites) { pbUpdate }
		loop do
		  Graphics.update
		  Input.update
		  pbUpdate
		  if Input.trigger?(Input::RIGHT)
			if index < @stock.length-1
			  pbPlayCursorSE
			  hideIcons(index)
			  volume = 1
			  index += 1
			  @switching = true
			  pbRedrawItem(index,volume)
			end
		  end
		  if Input.trigger?(Input::LEFT)
			if index > 0
			  pbPlayCursorSE
			  hideIcons(index)
			  volume = 1
			  index -= 1
			  @switching = true
			  pbRedrawItem(index,volume)
			end
		  end
		  if Input.trigger?(Input::UP)
			if volume < 99
			  pbPlayCursorSE
			  volume += 1
			  refreshNumbers(index,volume)
			elsif volume == 99
			  pbPlayCursorSE
			  volume = 1
			  refreshNumbers(index,volume)
			end
		  end
		  if Input.trigger?(Input::DOWN)
			if volume > 1
			  pbPlayCursorSE
			  volume -= 1
			  refreshNumbers(index,volume)
			elsif volume == 1
			  pbPlayCursorSE
			  volume = 99
			  refreshNumbers(index,volume)
			end
		  end
		  if Input.trigger?(Input::USE)
			recipe_data = GameData::Recipe.get(@stock[index])
			item = GameData::Item.get(recipe_data.item)
			itemname = (volume>1) ? item.name_plural : item.name
			pocket = item.pocket
			if pbConfirmMessage(_INTL("Would you like to craft {1} {2}?",volume*recipe_data.yield,itemname)) { pbUpdate }
			  if canCraft?(index,volume)
				added = 0
				quantity = (volume*recipe_data.yield)
				quantity += 1 if $player.activeCharm?(:CRAFTINGCHARM)
				quantity.times do
				  break if !@adapter.addItem(item)
				  added += 1
				end
				if added == quantity
				  pbSEPlay("Pkmn move learnt")
				  removeIngredients(index,volume)
				  if $player.activeCharm?(:CRAFTINGCHARM)
					pbMessage(_INTL("The Crafting Charm has added an extra item to the yield!"))
				  end    
				  pbMessage(_INTL("You put {1} {2} away\\nin the <icon=bagPocket{3}>\\c[1]{4} Pocket\\c[0].",
					quantity,itemname,pocket,PokemonBag.pocket_names()[pocket - 1])) { pbUpdate }
				  refreshNumbers(index,volume)
				else
				  added.times do
					if !@adapter.removeItem(item)
					  raise _INTL("Failed to delete stored items")
					end
				  end
				  pbPlayBuzzerSE
				  pbMessage(_INTL("Too bad...\nThe Bag is full...")) { pbUpdate }
				end
			  else
				pbPlayBuzzerSE
				pbMessage(_INTL("You lack the necessary ingredients.")) { pbUpdate }
			  end
			end
		  end
		  if Input.trigger?(Input::BACK)
			pbPlayCloseMenuSE
			break
		  end
		end
	  end
	  
	  def removeIngredients(index,volume)
		ingredients = GameData::Recipe.get(@stock[index]).ingredients
		ingredients.length.times do |i|
		  ingredient = ingredients[i][0]
		  cost = ingredients[i][1]
			# Check if Crafting Charm is active and reduce the ingredient cost
		  if $player.activeCharm?(:CRAFTINGCHARM)
			cost = [cost - 1, 1].max
			pbMessage(_INTL("The Crafting Charm caused fewer materials to be used!"))
		  end
		  if ingredient.is_a?(Symbol)
			(volume*cost).times { @adapter.removeItem(ingredient) }
		  else
			valid_items = []
			GameData::Item.each do |item|
			  next if !item.has_flag?(ingredient)
			  valid_items.push([item.id, item.price])
			end
			valid_items = valid_items.sort_by.with_index {|x,i| [x[1],i] }
			(volume*cost).times do
			  valid_items.each do |item|
				next unless @adapter.getQuantity(item[0])>0
				@adapter.removeItem(item[0])
				break
			  end
			end
		  end
		end
	  end

		
		elsif if PluginManager.installed?("Item Crafting UI")
	  def pbCraftItem(stock)
		index = 0
		volume = 1
		@stock = stock
		@switching = false
		refreshNumbers(index,volume)
		pbRedrawItem(index,volume)
		pbFadeInAndShow(@sprites) { pbUpdate }
		loop do
		  Graphics.update
		  Input.update
		  pbUpdate
		  if Input.trigger?(Input::RIGHT)
			if index < @stock.length-1
			  pbPlayCursorSE
			  hideIcons(index)
			  volume = 1
			  index += 1
			  @switching = true
			  pbRedrawItem(index,volume)
			end
		  end
		  if Input.trigger?(Input::LEFT)
			if index > 0
			  pbPlayCursorSE
			  hideIcons(index)
			  volume = 1
			  index -= 1
			  @switching = true
			  pbRedrawItem(index,volume)
			end
		  end
		  if Input.trigger?(Input::UP)
			if volume < 99
			  pbPlayCursorSE
			  volume += 1
			  refreshNumbers(index,volume)
			elsif volume == 99
			  pbPlayCursorSE
			  volume = 1
			  refreshNumbers(index,volume)
			end
		  end
		  if Input.trigger?(Input::DOWN)
			if volume > 1
			  pbPlayCursorSE
			  volume -= 1
			  refreshNumbers(index,volume)
			elsif volume == 1
			  pbPlayCursorSE
			  volume = 99
			  refreshNumbers(index,volume)
			end
		  end
		  if Input.trigger?(Input::USE)
			item = GameData::Item.get(@stock[index][0])
			itemname = (volume>1) ? item.name_plural : item.name
			pocket = item.pocket
			if pbConfirmMessage(_INTL("Would you like to craft {1} {2}?",volume,itemname))
			  if canCraft?(index,volume)
				if $bag.can_add?(item,volume)
				 if $player.activeCharm?(:CRAFTINGCHARM)
				   old_vol = volume
				   volume += 1
				   pbMessage(_INTL("The Crafting Charm has added an extra {1} to the yield!", itemname))
				 end
				  $bag.add(item,volume)
				  pbSEPlay("Pkmn move learnt")
				  removeIngredients(index,volume)
				  pbMessage(_INTL("You put the {1} away\\nin the <icon=bagPocket{2}>\\c[1]{3} Pocket\\c[0].",
					itemname,pocket,PokemonBag.pocket_names()[pocket - 1]))
					volume = old_vol
				  refreshNumbers(index,volume)
				else
				  pbPlayBuzzerSE
				  pbMessage(_INTL("Too bad...\nThe Bag is full..."))
				end
			  else
				pbPlayBuzzerSE
				pbMessage(_INTL("You lack the necessary ingredients."))
			  end
			end
		  end
		  if Input.trigger?(Input::BACK)
			pbPlayCloseMenuSE
			break
		  end
		end
	  end
	  
		  def removeIngredients(index,volume)
			for i in 0...@stock[index][1].length/2
			  item = @stock[index][1][2*i]
			  cost = @stock[index][1][2*i+1]
			  if $player.activeCharm?(:CRAFTINGCHARM)
				cost = [cost - 1, 1].max
				pbMessage(_INTL("The Crafting Charm caused fewer materials to be used!"))
				$bag.remove(item,(volume*cost)-1)
			  else
				$bag.remove(item,volume*cost)
			  end
			end
		  end
	  end
	end
end