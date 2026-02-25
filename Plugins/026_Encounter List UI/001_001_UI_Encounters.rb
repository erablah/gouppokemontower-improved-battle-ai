#########################################################
###                 Encounter list UI                 ###
### Based on the original resource by raZ and friends ###
#########################################################

# 종을 만난 적이 있는지 확인 (도감 대체)
def pbGetEncountered(species)
  # NOTE: $player.pokedex.seen? 대신 사용할 만남 기록 확인 로직
  # 여기서는 포켓몬 ID(species)에 해당하는 만남 플래그/변수를 확인한다고 가정합니다.
  # 예: $player.seen_pokemon.include?(species)
  # 또는 Pokedex 대신 $player에 자체 목록이 있다면...
  return $player.pokedex.seen?(species) # 임시로 기존 도감 함수 사용 (사용자님이 이 부분을 실제 게임 로직으로 변경해야 합니다)
end

# 종을 포획한 적이 있는지 확인 (도감 대체)
def pbGetCaught(species)
  # NOTE: $player.pokedex.owned? 대신 사용할 포획 기록 확인 로직
  # 예: $player.caught_pokemon.include?(species)
  # 또는 Pokedex 대신 $player에 자체 목록이 있다면...
  return $player.pokedex.owned?(species) # 임시로 기존 도감 함수 사용 (사용자님이 이 부분을 실제 게임 로직으로 변경해야 합니다)
end
# 전역 진화 계열 캐시 (느린 계산 결과를 저장하는 공간)
# 이 캐시는 이제 필요한 순간에만 한 번 계산됩니다.
$evolution_family_cache ||= {}

# 특정 종의 진화 계열 전체 목록을 반환하는 함수 (내장 함수 get_family_species 사용)
# [피츄, 피카츄, 라이츄] 같은 배열을 반환합니다.
def pbGetEvolutionFamily(species_id)
    # 1. 캐시 확인: 이미 계산된 결과가 있으면 즉시 반환 (가장 빠른 경로)
    return $evolution_family_cache[species_id] if $evolution_family_cache.key?(species_id)
    
    # 2. 인스턴스 가져오기
    species_data = GameData::Species.get(species_id)
    return [species_id] unless species_data # 데이터가 없으면 자기 자신만 반환
    
    # 3. 내장 함수를 사용하여 진화 계열 목록 가져오기 (가장 정확한 방법)
    # species_data.get_family_species는 이 종이 속한 진화 계열 전체를 반환합니다.
    family_list = species_data.get_family_species
    
    # 4. 계열의 모든 구성원 ID에 대해 결과를 캐시에 저장합니다. (재계산 방지)
    # (예: PIKACHU, RAICHU를 조회해도 모두 동일한 [PICHU, PIKACHU, RAICHU] 리스트를 캐시)
    family_list.each do |member_id|
        $evolution_family_cache[member_id] = family_list.dup 
    end

    return family_list
end


# 이 종의 진화 계열 중 하나라도 플레이어가 만났는지 확인하는 함수
# (이 함수는 진화 계열 확인 로직을 변경하지 않고 그대로 사용합니다.)
def pbGetEncounteredFamily(species_id)
    # pbGetEvolutionFamily는 캐시를 확인하고 없으면 계산 후 캐시합니다.
    family = pbGetEvolutionFamily(species_id) 
    
    # 진화 계열의 모든 종을 순회하며 만남 기록 확인
    family.each do |s|
        # pbGetEncountered는 해당 종을 만났는지 확인하는 함수입니다.
        return true if pbGetEncountered(s)
    end
    return false
end

# This is the name of a graphic in your Graphics/UI folder that changes the look of the UI
# If the graphic does not exist, you will get an error
WINDOWSKIN = "base.png"

# This hash allows you to define the names of your encounter types if you want them to be more logical
# E.g. "파도타기" instead of "Water"
# If missing, the script will use the encounter type names in GameData::EncounterTypes
USER_DEFINED_NAMES = {
:Land => "풀밭",
:LandDay => "풀밭 (day)",
:LandNight => "풀밭 (night)",
:LandMorning => "풀밭 (morning)",
:LandAfternoon => "풀밭 (afternoon)", 
:LandEvening => "풀밭 (evening)",
:PokeRadar => "Poké Radar", 
:Cave => "동굴",
:CaveDay => "동굴 (day)",
:CaveNight => "동굴 (night)",
:CaveMorning => "동굴 (morning)",
:CaveAfternoon => "동굴 (afternoon)",
:CaveEvening => "동굴 (evening)",
:Water => "파도타기",
:WaterDay => "파도타기 (day)",
:WaterNight => "파도타기 (night)",
:WaterMorning => "파도타기 (morning)",
:WaterAfternoon => "파도타기 (afternoon)",
:WaterEvening => "파도타기 (evening)",
:OldRod => "Fishing (Old Rod)",
:SuperRod => "낚시",
:RockSmash => "Rock Smash",
:HeadbuttLow => "박치기(낮은확률)",
:HeadbuttHigh => "박치기(높은확률)",
:BugContest => "Bug Contest"
}

# Remove the '#' from this line to use default encounter type names
#USER_DEFINED_NAMES = nil

# Method that returns whether a specific form has been seen (any gender)
def seen_form_any_gender?(species, form)
  ret = false
  if $player.pokedex.seen_form?(species, 0, form) ||
    $player.pokedex.seen_form?(species, 1, form)
    ret = true
  end
  return ret
end

class EncounterList_Scene

  # Constructor method
  # Sets a handful of key variables needed throughout the script
  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    mapid = $game_map.map_id
    @encounter_data = GameData::Encounter.get(mapid, $PokemonGlobal.encounter_version)
    if @encounter_data
      @encounter_tables = Marshal.load(Marshal.dump(@encounter_data.types))
      @max_enc, @eLength = getMaxEncounters(@encounter_tables)
    else
      @max_enc, @eLength = [1, 1]
    end
    @index = 0
  end
 
  # This gets the highest number of unique encounters across all defined encounter types for the map
  # It might sound weird, but this is needed for drawing the icons
  def getMaxEncounters(data)
    keys = data.keys
    a = []
    for key in keys
      b = []
      arr = data[key]
      for i in 0...arr.length
        b.push( arr[i][1] )
      end
      a.push(b.uniq.length)
    end
    return a.max, keys.length
  end
  
  # This method initiates the following:
  # Background graphics, text overlay, Pokémon sprites and navigation arrows
  def pbStartScene
    if !File.file?("Graphics/UI/EncounterUI/"+WINDOWSKIN)
      raise _INTL("You are missing the graphic for this UI. Make sure the image is in your Graphics/UI folder and that it is named appropriately.")
    end
    addBackgroundPlane(@sprites,"bg","EncounterUI/bg",@viewport)
    @sprites["base"] = IconSprite.new(0,0,@viewport)
    @sprites["base"].setBitmap("Graphics/UI/EncounterUI/"+WINDOWSKIN)
    @sprites["base"].ox = @sprites["base"].bitmap.width/2
    @sprites["base"].oy = @sprites["base"].bitmap.height/2
    @sprites["base"].x = Graphics.width/2; @sprites["base"].y = Graphics.height/2
    @sprites["base"].opacity = 200
    @sprites["locwindow"] = Window_AdvancedTextPokemon.new("")
    @sprites["locwindow"].viewport = @viewport
    @sprites["locwindow"].width = 512
    @sprites["locwindow"].height = 344
    @sprites["locwindow"].x = (Graphics.width - @sprites["locwindow"].width)/2
    @sprites["locwindow"].y = (Graphics.height - @sprites["locwindow"].height)/2
    @sprites["locwindow"].windowskin = nil
    @h = (Graphics.height - @sprites["base"].bitmap.height)/2
    @w = (Graphics.width - @sprites["base"].bitmap.width)/2
    @max_enc.times do |i|
      @sprites["icon_#{i}"] = PokemonSpeciesIconSprite.new(nil,@viewport)
      @sprites["icon_#{i}"].x = @w + 28 + 64*(i%7)
      @sprites["icon_#{i}"].y = @h + 100 + (i/7)*64
      @sprites["icon_#{i}"].visible = false
    end
    @sprites["rightarrow"] = AnimatedSprite.new("Graphics/UI/right_arrow",8,40,28,2,@viewport)
    @sprites["rightarrow"].x = Graphics.width - @sprites["rightarrow"].bitmap.width
    @sprites["rightarrow"].y = Graphics.height/2 - @sprites["rightarrow"].bitmap.height/16
    @sprites["rightarrow"].visible = false
    @sprites["rightarrow"].play
    @sprites["leftarrow"] = AnimatedSprite.new("Graphics/UI/left_arrow",8,40,28,2,@viewport)
    @sprites["leftarrow"].x = 0
    @sprites["leftarrow"].y = Graphics.height/2 - @sprites["rightarrow"].bitmap.height/16
    @sprites["leftarrow"].visible = false
    @sprites["leftarrow"].play
    @encounter_data ? drawPresent : drawAbsent
    pbFadeInAndShow(@sprites) { pbUpdate }
  end
  
  # Main function that controls the UI
  def pbEncounter
    loop do
      Graphics.update
      Input.update
      pbUpdate
      if Input.trigger?(Input::RIGHT) && @eLength >1 && @index< @eLength-1
        pbPlayCursorSE
        hideSprites
        @index += 1
        drawPresent
      elsif Input.trigger?(Input::LEFT) && @eLength >1 && @index !=0
        pbPlayCursorSE
        hideSprites
        @index -= 1
        drawPresent
      elsif Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        break
      end
    end
  end
 
# Draw text and icons if map has encounters defined
def drawPresent
    # **참고: 이전 버전에서 여기에 있던 pbGenerateEvolutionFamilyCache 호출은 삭제했습니다.**
    # 이제 pbGetEncounteredFamily 호출 내에서 필요할 때 자동으로 캐시를 채웁니다.
    
    @sprites["rightarrow"].visible = (@index < @eLength-1) ? true : false
    @sprites["leftarrow"].visible = (@index > 0) ? true : false
    i = 0
    enc_array, currKey = getEncData
    enc_array.each do |s|
      species_data = GameData::Species.get(s)
      
      # 1. 포획 여부는 해당 종(s)만 확인
      is_caught = pbGetCaught(s)          
      
      # 2. 만남 여부는 진화 계열 전체 확인 로직을 통해 가져옵니다. (수정된 헬퍼 함수 사용)
      is_encountered = pbGetEncounteredFamily(s) 
      
      if !is_caught && !is_encountered
        @sprites["icon_#{i}"].pbSetParams(0,0,0,false) # 물음표 아이콘
        @sprites["icon_#{i}"].visible = true
      elsif !is_caught
        @sprites["icon_#{i}"].pbSetParams(s,0,species_data.form,false) # 실루엣 아이콘 (계열 중 하나 만남)
        @sprites["icon_#{i}"].tone = Tone.new(0,0,0,255)
        @sprites["icon_#{i}"].visible = true
      else
        @sprites["icon_#{i}"].pbSetParams(s,0,species_data.form,false) # 정상 아이콘 (해당 종 포획함)
        @sprites["icon_#{i}"].tone = Tone.new(0,0,0,0)
        @sprites["icon_#{i}"].visible = true
      end
      i += 1
    end
    # Get user-defined encounter name or default one if not present
    name = USER_DEFINED_NAMES ? USER_DEFINED_NAMES[currKey] : GameData::EncounterType.get(currKey).real_name
    loctext = _INTL("<ac><c2=43F022E8>{1}: {2}</c2></ac>", $game_map.name,name)
    loctext += sprintf("<al><c2=7FF05EE8>이 지역에서 만난 포켓몬: %s</c2></al>",enc_array.length)
    loctext += sprintf("<c2=63184210>-----------------------------------------</c2>")
    @sprites["locwindow"].setText(loctext)
  end

  
  # Draw text if map has no encounters defined (e.g. in buildings)
  def drawAbsent
    loctext = _INTL("<ac><c2=43F022E8>{1}</c2></ac>", $game_map.name)
    loctext += sprintf("<al><c2=7FF05EE8>이 지역에선 포켓몬이 나오지 않는다!</c2></al>")
    loctext += sprintf("<c2=63184210>-----------------------------------------</c2>")
    @sprites["locwindow"].setText(loctext)
  end
 
  # Method that returns an array of symbolic names for chosen encounter type on current map
  # Currently, the resulting array is sorted by national Pokédex number
  def getEncData
    currKey = @encounter_tables.keys[@index]
    arr = []
    enc_array = []
    @encounter_tables[currKey].each { |s| arr.push( s[1] ) }
    GameData::Species.each { |s| enc_array.push(s.id) if arr.include?(s.id) } # From Maruno
    enc_array.uniq!
    return enc_array, currKey
  end
  
  def pbUpdate
    pbUpdateSpriteHash(@sprites)
  end
  
  # Hide sprites
  def hideSprites
    for i in 0...@max_enc
      @sprites["icon_#{i}"].visible = false
    end
  end

  # Dipose stuff at the end
  def pbEndScene
    pbFadeOutAndHide(@sprites) { pbUpdate }
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end

end


class EncounterList_Screen
  def initialize(scene)
    @scene = scene
  end

  def pbStartScreen
    @scene.pbStartScene
    @scene.pbEncounter
    @scene.pbEndScene
  end
end

# Utility method for calling UI
def pbViewEncounters
  scene = EncounterList_Scene.new
  screen = EncounterList_Screen.new(scene)
  screen.pbStartScreen
end