#===============================================================================
# * Triple Triad Charm
#===============================================================================

class TriadScreen
   def pbStartScreen(opponentName, minLevel, maxLevel, rules = nil, oppdeck = nil, prize = nil)
    raise _INTL("Minimum level must be 0 through 9.") if minLevel < 0 || minLevel > 9
    raise _INTL("Maximum level must be 0 through 9.") if maxLevel < 0 || maxLevel > 9
    raise _INTL("Maximum level shouldn't be less than the minimum level.") if maxLevel < minLevel
    if rules.is_a?(Array) && rules.length > 0
      rules.each do |rule|
        @sameWins           = true if rule == "samewins"
        @openHand           = true if rule == "openhand"
        @wrapAround         = true if rule == "wrap"
        @elements           = true if rule == "elements"
        @randomHand         = true if rule == "randomhand"
        @countUnplayedCards = true if rule == "countunplayed"
        @trade              = 1    if rule == "direct"
        @trade              = 2    if rule == "winall"
        @trade              = 3    if rule == "noprize"
      end
    end
    @triadCards = []
    count = 0
    $PokemonGlobal.triads.length.times do |i|
      item = $PokemonGlobal.triads[i]
      ItemStorageHelper.add(@triadCards, $PokemonGlobal.triads.maxSize,
                            TriadStorage::MAX_PER_SLOT, item[0], item[1])
      count += item[1]   # Add item count to total count
    end
    @board = []
    @playerName   = $player ? $player.name : "Trainer"
    @opponentName = opponentName
    type_keys = GameData::Type.keys
    (@width * @height).times do |i|
      square = TriadSquare.new
      if @elements
        loop do
          trial_type = type_keys.sample
          type_data = GameData::Type.get(trial_type)
          next if type_data.pseudo_type
          square.type = type_data.id
          break
        end
      end
      @board.push(square)
    end
    @scene.pbStartScene(self)   # (param1, param2)
    # Check whether there are enough cards.
    if count < self.maxCards
      @scene.pbDisplayPaused(_INTL("You don't have enough cards."))
      @scene.pbEndScene
      return 0
    end
    # Set the player's cards.
    cards = []
    if @randomHand   # Determine hand at random
      self.maxCards.times do
        randCard = @triadCards[rand(@triadCards.length)]
        pbSubtract(@triadCards, randCard[0])
        cards.push(randCard[0])
      end
      @scene.pbShowPlayerCards(cards)
    else
      cards = @scene.pbChooseTriadCard(@triadCards)
    end
    # Set the opponent's cards.
    if oppdeck.is_a?(Array) && oppdeck.length == self.maxCards   # Preset
      opponentCards = []
      oppdeck.each do |species|
        species_data = GameData::Species.try_get(species)
        if !species_data
          @scene.pbDisplayPaused(_INTL("Opponent has an illegal card, \"{1}\".", species))
          @scene.pbEndScene
          return 0
        end
        opponentCards.push(species_data.id)
      end
    else
      species_keys = GameData::Species.keys
      candidates = []
      while candidates.length < 200
        card = species_keys.sample
        card_data = GameData::Species.get(card)
        card = card_data.id   # Make sure it's a symbol
        triad = TriadCard.new(card)
        total = triad.north + triad.south + triad.east + triad.west
        # Add random species and its total point count
        candidates.push([card, total])
        if candidates.length < 200 && $player.owned?(card_data.species)
          # Add again if player owns the species
          candidates.push([card, total])
        end
      end
      # sort by total point count
      candidates.sort! { |a, b| a[1] <=> b[1] }
      opponentCards = []
      self.maxCards.times do
        # Choose random card from candidates based on trainer's level
        index = minLevel + rand(20)
        opponentCards.push(candidates[index][0])
      end
    end
    originalCards = cards.clone
    originalOpponentCards = opponentCards.clone
    @scene.pbNotifyCards(cards.clone, opponentCards.clone)
    @scene.pbShowOpponentCards(opponentCards)
    @scene.pbDisplay(_INTL("Choosing the starting player..."))
    @scene.pbUpdateScore
    playerTurn = (rand(2) == 0)
    @scene.pbDisplay(_INTL("{1} will go first.", (playerTurn) ? @playerName : @opponentName))
    (@width * @height).times do |i|
      position = nil
      triadCard = nil
      cardIndex = 0
      if playerTurn
        # Player's turn
        until position
          cardIndex = @scene.pbPlayerChooseCard(cards.length)
          triadCard = TriadCard.new(cards[cardIndex])
          position = @scene.pbPlayerPlaceCard(cardIndex)
        end
      else
        # Opponent's turn
        @scene.pbDisplay(_INTL("{1} is making a move...", @opponentName))
        scores = []
        opponentCards.length.times do |cardIdx|
          square = TriadSquare.new
          square.card = TriadCard.new(opponentCards[cardIdx])
          square.owner = 2
          (@width * @height).times do |j|
            x = j % @width
            y = j / @width
            square.type = @board[j].type
            flips = flipBoard(x, y, square)
            scores.push([cardIdx, x, y, flips.length]) if flips
          end
        end
        # Sort by number of flips
        scores.sort! { |a, b| (b[3] == a[3]) ? rand(-1..1) : b[3] <=> a[3] }
        scores = scores[0, opponentCards.length]   # Get the best results
        if scores.length == 0
          @scene.pbDisplay(_INTL("{1} can't move somehow...", @opponentName))
          playerTurn = !playerTurn
          continue
        end
        result = scores[rand(scores.length)]
        cardIndex = result[0]
        triadCard = TriadCard.new(opponentCards[cardIndex])
        position = [result[1], result[2]]
        @scene.pbOpponentPlaceCard(triadCard, position, cardIndex)
      end
      boardIndex = (position[1] * @width) + position[0]
      board[boardIndex].card  = triadCard
      board[boardIndex].owner = playerTurn ? 1 : 2
      flipBoard(position[0], position[1])
      if playerTurn
        cards.delete_at(cardIndex)
        @scene.pbEndPlaceCard(position, cardIndex)
      else
        opponentCards.delete_at(cardIndex)
        @scene.pbEndOpponentPlaceCard(position, cardIndex)
      end
      playerTurn = !playerTurn
    end
    # Determine the winner
    playerCount   = 0
    opponentCount = 0
    (@width * @height).times do |i|
      playerCount   += 1 if board[i].owner == 1
      opponentCount += 1 if board[i].owner == 2
    end
    if @countUnplayedCards
      playerCount   += cards.length
      opponentCount += opponentCards.length
    end
    result = 0
    if playerCount == opponentCount
      @scene.pbDisplayPaused(_INTL("The game is a draw."))
      result = 3
      if @trade == 1
        # Keep only cards of your color
        originalCards.each { |crd| $PokemonGlobal.triads.remove(crd) }
        cards.each { |crd| $PokemonGlobal.triads.add(crd) }
        (@width * @height).times do |i|
          if board[i].owner == 1
            crd = GameData::Species.get_species_form(board[i].card.species, board[i].card.form).id
            $PokemonGlobal.triads.add(crd)
          end
        end
        @scene.pbDisplayPaused(_INTL("Kept all cards of your color."))
      end
    elsif playerCount > opponentCount
      @scene.pbDisplayPaused(_INTL("{1} won against {2}.", @playerName, @opponentName))
      result = 1
      if prize
        species_data = GameData::Species.try_get(prize)
        if species_data && $PokemonGlobal.triads.add(species_data.id)
          @scene.pbDisplayPaused(_INTL("Got opponent's {1} card.", species_data.name))
        end
	# Gain extra card from Opponent's deck (TRIP CHARM)
        if $player.activeCharm?(:TRIPTRIADCHARM)
            card = originalOpponentCards[rand(originalOpponentCards.length)]
            if $PokemonGlobal.triads.add(card)
              cardname = GameData::Species.get(card).name
              @scene.pbDisplayPaused(_INTL("Got opponent's {1} card from the Trip Triad Charm!", cardname))
            end
        end
      else
        case @trade
        when 0   # Gain 1 random card from opponent's deck
          card = originalOpponentCards[rand(originalOpponentCards.length)]
          if $PokemonGlobal.triads.add(card)
            cardname = GameData::Species.get(card).name
            @scene.pbDisplayPaused(_INTL("Got opponent's {1} card.", cardname))
          end
          # Gain extra card from Opponent's deck (TRIP CHARM)
          if $player.activeCharm?(:TRIPTRIADCHARM)
            card = originalOpponentCards[rand(originalOpponentCards.length)]
            if $PokemonGlobal.triads.add(card)
              cardname = GameData::Species.get(card).name
              @scene.pbDisplayPaused(_INTL("Got opponent's {1} card from the Trip Triad Charm!", cardname))
            end
          end
        when 1   # Keep only cards of your color
          originalCards.each { |crd| $PokemonGlobal.triads.remove(crd) }
          cards.each { |crd| $PokemonGlobal.triads.add(crd) }
          (@width * @height).times do |i|
            if board[i].owner == 1
              card = GameData::Species.get_species_form(board[i].card.species, board[i].card.form).id
              $PokemonGlobal.triads.add(card)
            end
          end
          @scene.pbDisplayPaused(_INTL("Kept all cards of your color."))
        when 2   # Gain all opponent's cards
          originalOpponentCards.each { |crd| $PokemonGlobal.triads.add(crd) }
          @scene.pbDisplayPaused(_INTL("Got all opponent's cards."))
        end
      end
    else
      @scene.pbDisplayPaused(_INTL("{1} lost against {2}.", @playerName, @opponentName))
      result = 2
      case @trade
      when 0   # Lose 1 random card from your deck
        card = originalCards[rand(originalCards.length)]
        $PokemonGlobal.triads.remove(card)
        cardname = GameData::Species.get(card).name
        @scene.pbDisplayPaused(_INTL("Opponent won your {1} card.", cardname))
      when 1   # Keep only cards of your color
        originalCards.each { |crd| $PokemonGlobal.triads.remove(card) }
        cards.each { |crd| $PokemonGlobal.triads.add(crd) }
        (@width * @height).times do |i|
          if board[i].owner == 1
            card = GameData::Species.get_species_form(board[i].card.species, board[i].card.form).id
            $PokemonGlobal.triads.add(card)
          end
        end
        @scene.pbDisplayPaused(_INTL("Kept all cards of your color.", cardname))
      when 2   # Lose all your cards
        originalCards.each { |crd| $PokemonGlobal.triads.remove(crd) }
        @scene.pbDisplayPaused(_INTL("Opponent won all your cards."))
      end
    end
    @scene.pbEndScene
    return result
  end
end