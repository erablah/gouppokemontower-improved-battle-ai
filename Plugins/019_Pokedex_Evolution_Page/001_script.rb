#===============================================================================
# Pokedex Evolution Page
#===============================================================================
# Adding the page
#===============================================================================
UIHandlers.add(:pokedex, :page_evolution, {
  "name"      => "EVOLUTION",
  "suffix"    => "evolution",
  "order"     => 40,
	"onlyOwned" => true,
  "layout"    => proc { |pkmn, scene| scene.drawPageEvolution }
})

#===============================================================================
# Page Script
#===============================================================================
class PokemonPokedexInfo_Scene
	alias org_pbStartScene pbStartScene
  def pbStartScene(*args)
		org_pbStartScene(*args)
		10.times do |i|
			@sprites["evoicon#{i}"] = PokemonSpeciesIconSprite.new(nil, @viewport)
    	@sprites["evoicon#{i}"].setOffset(PictureOrigin::CENTER)
    	@sprites["evoicon#{i}"].x = 0
    	@sprites["evoicon#{i}"].y = 158
			@sprites["evoicon#{i}"].visible = false
		end
		pbUpdateDummyPokemon
	end

	alias org_pbUpdateDummyPokemon pbUpdateDummyPokemon
	def pbUpdateDummyPokemon
		org_pbUpdateDummyPokemon
		stage_1 = GameData::Species.get(@species).get_baby_species
		stage_2 = GameData::Species.get(stage_1).get_evolutions.map {|poke| poke.push(stage_1)}
		stage_3 = []
		stage_2.each do |pkmn|
			stage_3.concat(GameData::Species.get(pkmn[0]).get_evolutions.map {|poke| poke.push(pkmn[0])})
		end
		@evolutions = [[[stage_1]]]
		@evolutions.push(stage_2.uniq {|pkmn| pkmn[0]}) if !stage_2.empty?
		@evolutions.push(stage_3.uniq {|pkmn| pkmn[0]}) if !stage_3.empty?
		10.times do |i|
			@sprites["evoicon#{i}"]&.species = nil
		end
		index = 0
		@evolutions.length.times do |i|
			@evolutions[i].length.times do |v|
				specie = @evolutions[i][v][0]
				gender, form, shiny = $player.pokedex.last_form_seen(specie)
				@sprites["evoicon#{index}"]&.pbSetParams(specie, gender, form, shiny)
				@sprites["evoicon#{index}"]&.x = ((Graphics.width + 100) / (@evolutions[i].length + 1)) * (v + 1) - 50
				@sprites["evoicon#{index}"]&.y = (Graphics.height / (@evolutions.length + 1)) * (i + 1)
				index += 1
			end
		end
		index = 0
		if @evolutions[0][0][0].to_sym == :EEVEE
			@evolutions.length.times do |i|
				@evolutions[i].length.times do |v|
					@sprites["evoicon#{index}"]&.x = [256, 103, 409, 103, 256, 409, 103, 256, 409][index]
					@sprites["evoicon#{index}"]&.y = [96, 96, 96, 192, 192, 192, 288, 288, 288][index]
					index += 1
				end
			end
		end
	end

	alias org_drawPage drawPage
	def drawPage(page)
		10.times do |i|
			@sprites["evoicon#{i}"].visible = false if @sprites["evoicon#{i}"]
		end
		pbSetSystemFont(@sprites["overlay"].bitmap)
		org_drawPage(page)
	end

	def drawPageEvolution
		10.times do |i|
			@sprites["evoicon#{i}"].visible = true if !@sprites["evoicon#{i}"].species.nil?
		end
    overlay = @sprites["overlay"].bitmap
		pbSetNarrowFont(overlay)
    base    = Color.new(88, 88, 80)
    shadow  = Color.new(168, 184, 184)
    # Write species and form name
    species = ""
    @available.each do |i|
      if i[1] == @gender && i[2] == @form
        formname = i[0]
        break
      end
    end
    textpos = []
		index = 0
		@evolutions.length.times do |i|
			@evolutions[i].length.times do |v|
				if GameData::Species.get(@evolutions[i][v][0]).get_baby_species == @evolutions[i][v][0]
					index += 1
					next
				end
				case @evolutions[i][v][1]
				when :Level,:Silcoon,:Cascoon then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}")]
				when :LevelMale then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(수컷)")]
				when :LevelFemale then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(암컷)")]
				when :LevelDay then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(낮 중에)")]
				when :LevelNight then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(밤 중에)")]
				when :LevelMorning then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(아침에)")]
				when :LevelAfternoon then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(오후에)")]
				when :LevelNoWeather then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(저녁에)")]
				when :LevelSun then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(쾌청일 때)")]
				when :LevelRain then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(비가 올 떄)")]
				when :LevelSnow then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(눈이 올 때)")]
				when :LevelSandstorm then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(모래바람이 불 때)")]
				when :LevelCycling then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(자전거를 타고 있을 때)")]
				when :LevelSurfing then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(파도타기 중에)")]
				when :LevelDiving then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(다이빙 중에)")]
				when :LevelDarkness then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), "(어두운 곳에서)"]
				when :LevelDarkInParty then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("(파티에 악 타입 포켓몬이 있을 때)")]
				when :AttackGreater then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"),_INTL("\n(공 > 방)")]
				when :AtkDefEqual then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("\n(공 = 방)")]
				when :DefenseGreater then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}"), _INTL("\n(공 < 방)")]
				when :Ninjask then evo_txt = [_INTL("Lv. #{@evolutions[i][v][2]}")]
				when :Shedinja then evo_txt = [_INTL("가방의 여분의 볼과"), _INTL("파티에 자리가 있을 때")]
				when :Happiness then evo_txt = [_INTL("친밀도가 높을 때"), _INTL("레벨업")]
				when :HappinessMale then evo_txt = [_INTL("친밀도가 높을 때"),_INTL("\n(수컷)")]
				when :HappinessFemale then evo_txt = [_INTL("친밀도가 높을 때"),_INTL("\n(암컷)")]
				when :HappinessDay then evo_txt = [_INTL("친밀도가 높을 때"), _INTL("\n(낮 중에)")]
				when :HappinessNight then evo_txt = [_INTL("친밀도가 높을 때"), _INTL("\n(밤 중에)")]
				when :HappinessMove then evo_txt = [_INTL("#{GameData::Move.get(@evolutions[i][v][2]).name} 배우고"), _INTL("친밀도가 높을 때")]
				when :HappinessMoveType then evo_txt = [_INTL("#{GameData::Type.get(@evolutions[i][v][2]).name}타입 기술을 배우고"),_INTL("\n친밀도가 높을 때")]
				when :HappinessHoldItem then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}"), _INTL("지니고\n친밀도가 높을 때")]
				when :MaxHappiness then evo_txt = [_INTL("친밀도가 높을 때"), _INTL("레벨업")]
				when :Beauty then evo_txt = [_INTL("아름다움 수치가 최고일 때"), _INTL("레벨업")]
				when :HoldItem then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}"), _INTL("지니고 레벨업")]
				when :HoldItem then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}", _INTL("지니고 레벨업"))]
				when :HoldItemMale then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name} 지니고"), _INTL("레벨업 (수컷)")]
				when :HoldItemFemale then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}"), _INTL("지니고 레벨업 (암컷)")]
				when :DayHoldItem then evo_txt = [_INTL("낮에"), _INTL("#{GameData::Item.get(@evolutions[i][v][2]).name} 지니고 레벨업")]
				when :NightHoldItem then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}"), _INTL("지니고 레벨업 (밤 중에)")]
				when :HasMove then evo_txt = [_INTL("#{GameData::Move.get(@evolutions[i][v][2]).name} 배운 후"), _INTL("레벨업")]
				when :HasMoveType then evo_txt = [_INTL("#{GameData::Type.get(@evolutions[i][v][2]).name}타입 기술을 배우고"), _INTL("레벨업")]
				when :HasInParty then evo_txt = [_INTL("파티에 #{GameData::Species.get(@evolutions[i][v][2]).name} 있을 때"), _INTL("레벨업")]
				when :Location then evo_txt = [_INTL("#{@evolutions[i][v][2]} 근처에서"), _INTL("레벨업")]
				when :LocationFlag then evo_txt = [_INTL("#{@evolutions[i][v][2]} 근처에서"), _INTL("레벨업")]
				when :Item then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}")]
				when :ItemMale then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}"), _INTL("(수컷)")]
				when :ItemFemale then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}"), _INTL("(암컷)")]
				when :ItemDay then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}"), _INTL("(낮 중에)")]
				when :ItemNight then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}"), _INTL("(밤 중에)")]
				when :ItemHappiness then evo_txt = [_INTL("#{GameData::Item.get(@evolutions[i][v][2]).name}"), _INTL("친밀도가 높을 때")]
				when :Trade then evo_txt = [_INTL("교환")]
				when :TradeMale then evo_txt = [_INTL("교환"), _INTL("(수컷)")]
				when :TradeFemale then evo_txt = [_INTL("교환"), _INTL("(암컷)")]
				when :TradeDay then evo_txt = [_INTL("교환"), _INTL("(낮 중에)")]
				when :TradeNight then evo_txt = [_INTL("교환"), _INTL("(밤 중에)")]
				when :TradeItem then evo_txt = [_INTL("교환"), _INTL("holding #{GameData::Item.get(@evolutions[i][v][2]).name}")]
				when :TradeSpecies then evo_txt = [_INTL("교환"), _INTL("for #{GameData::Species.get(@evolutions[i][v][2]).name}")]
				when :Event then evo_txt = [_INTL("족자에 따라 진화")]
				when :EventAfterDamageTaken then evo_txt = [_INTL("배틀에서 49 이상의 데미지를 받은 후 레벨업")]
				when :LevelUseMoveCount then evo_txt = [_INTL("#{GameData::Move.get(@evolutions[i][v][2]).name}"), _INTL("20번 사용 후 레벨업")]
				when :BattleDealCriticalHit then evo_txt = [_INTL("한 배틀에서 급소를 3번 맞추기")]
				when :LevelWalk then evo_txt = [_INTL("1000보 걸은 후 레벨업")]
				when :CollectItems then evo_txt = [_INTL("모으령의 코인을 999개 모은 후 레벨업")]
				else evo_txt = [_INTL("???")]
				end
				evo_txt = [evo_txt[0] + " " + evo_txt[1]] if @evolutions[i].length < 2 && evo_txt.length > 1
				evo_txt = [evo_txt[0] + " " + evo_txt[1]] if evo_txt[1] && (evo_txt[0].length + evo_txt[1].length <= 16)
				textpos.push([evo_txt[0], @sprites["evoicon#{index}"].x, @sprites["evoicon#{index}"].y + 32, :center, base, shadow])
				textpos.push([evo_txt[1], @sprites["evoicon#{index}"].x, @sprites["evoicon#{index}"].y + 64, :center, base, shadow]) if evo_txt.length > 1
				index += 1
			end
		end
    # Draw all text
    pbDrawTextPositions(overlay, textpos)
	end
end