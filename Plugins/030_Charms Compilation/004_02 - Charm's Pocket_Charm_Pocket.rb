#===============================================================================
# * Charm Pocket
#===============================================================================

#-------------------------------------------------------------------------------
# Adds Charm pocket to the bag.
#-------------------------------------------------------------------------------
module Settings
  Settings.singleton_class.alias_method :charm_bag_pocket_names, :bag_pocket_names
  def self.bag_pocket_names
    names = self.charm_bag_pocket_names
    names.push(_INTL("부적"))
    return names
  end
   
  BAG_MAX_POCKET_SIZE.push(-1)
  BAG_POCKET_AUTO_SORT.push(true)
end

#===============================================================================
# Bag Screen compatibility.
#===============================================================================
if PluginManager.installed?("Bag Screen w/int. Party")
  class PokemonBag_Scene
    def pbPocketColor
      case @bag.last_viewed_pocket
      when 1	#Red
        @sprites["background"].color = Color.new(233, 152, 152)
        @sprites["gradient"].color = Color.new(255, 37, 37)
        @sprites["panorama"].color = Color.new(213, 89, 89)
      when 2	#Orange
        @sprites["background"].color = Color.new(233, 161, 152)
        @sprites["gradient"].color = Color.new(255, 134, 37)
        @sprites["panorama"].color = Color.new(224, 112, 56)
      when 3	#Yellow
        @sprites["background"].color = Color.new(233, 197, 152)
        @sprites["gradient"].color = Color.new(255, 177, 37)
        @sprites["panorama"].color = Color.new(200, 136, 32)
      when 4	#Green-Yellow
        @sprites["background"].color = Color.new(216, 233, 152)
        @sprites["gradient"].color = Color.new(194, 255, 37)
        @sprites["panorama"].color = Color.new(128, 168, 32)
      when 5	#Green
        @sprites["background"].color = Color.new(175, 233, 152)
        @sprites["gradient"].color = Color.new(78, 255, 37)
        @sprites["panorama"].color = Color.new(32, 160, 72)
      when 6	#Light Blue
        @sprites["background"].color = Color.new(152, 220, 233)
        @sprites["gradient"].color = Color.new(37, 212, 255)
        @sprites["panorama"].color = Color.new(24, 144, 176)
      when 7	#Blue
        @sprites["background"].color = Color.new(152, 187, 233)
        @sprites["gradient"].color = Color.new(37, 125, 255)
        @sprites["panorama"].color = Color.new(48, 112, 224)
      when 8	#Purple
        @sprites["background"].color = Color.new(178, 152, 233)
        @sprites["gradient"].color = Color.new(145, 37, 255)
        @sprites["panorama"].color = Color.new(144, 72, 216)
      when 9	#Lavender if Z-Power/Pink if not
        if PluginManager.installed?("[DBK] Z-Power")
          @sprites["background"].color = Color.new(207, 152, 233)
          @sprites["gradient"].color = Color.new(197, 37, 255)
          @sprites["panorama"].color = Color.new(191, 89, 213)
        else
          @sprites["background"].color = Color.new(233, 152, 189)
          @sprites["gradient"].color = Color.new(255, 37, 187)
          @sprites["panorama"].color = Color.new(213, 89, 141)
        end
      when 10	#Pink
        @sprites["background"].color = Color.new(233, 152, 189)
        @sprites["gradient"].color = Color.new(255, 37, 187)
        @sprites["panorama"].color = Color.new(213, 89, 141)
      end
    end

    def pbRefresh
      # Draw the pocket icons
      pocketX  = []; incrementX = 0 # Fixes pockets' X coordinates
      @bag.pockets.length.times do |i|
        break if pocketX.length == @bag.pockets.length
        pocketX.push(incrementX)
        incrementX += 2 if i.odd?
      end
      @sprites["pocketicon"].bitmap.clear
      if PluginManager.installed?("[DBK] Z-Power")
        @sprites["pocketicon"] = BitmapSprite.new(166, 52, @viewport)
        @sprites["pocketicon"].x = 368
        @sprites["currentpocket"].x = 368
      else
        @sprites["pocketicon"] = BitmapSprite.new(148, 52, @viewport)
        @sprites["pocketicon"].x = 362
        @sprites["currentpocket"].x = 362
	  end
      #-------------------------------------------------------------------------
      pocketAcc = @sprites["itemlist"].pocket - 1 # Current pocket
      @sprites["pocketicon"].bitmap.clear
	  xPoss = 14
	  xPoss = 12 if PluginManager.installed?("[DBK] Z-Power")
      (1...@bag.pockets.length).each do |i|
        pocketValue = i - 1
        @sprites["pocketicon"].bitmap.blt(
          (i - 1) * xPoss + pocketX[pocketValue], (i % 2) * 26, @pocketbitmap.bitmap,
          Rect.new((i - 1) * 28, 0, 28, 28)) if pocketValue != pocketAcc # Unblocked icons
      end
      if @choosing && @filterlist
        (1...@bag.pockets.length).each do |i|
          next if @filterlist[i].length > 0
          pocketValue = i - 1
          @sprites["pocketicon"].bitmap.blt(
            (i - 1) * xPoss + pocketX[pocketValue], (i % 2) * 26, @pocketbitmap.bitmap,
            Rect.new((i - 1) * 28, 28, 28, 28)) #Blocked icons
        end
      end
      @sprites["currentpocket"].x = @sprites["pocketicon"].x + ((pocketAcc) * xPoss) + pocketX[pocketAcc]
      @sprites["currentpocket"].y = 26 - (((pocketAcc) % 2) * 26)
      @sprites["currentpocket"].src_rect = Rect.new((pocketAcc) * 28, 28, 28, 28) # Current pocket icon
      # Refresh the item window
      @sprites["itemlist"].refresh
      # Refresh more things
      pbRefreshIndexChanged
      # Refresh party and pockets
      pbRefreshParty
      pbPocketColor if BagScreenWiInParty::BGSTYLE == 2
    end
  end
end