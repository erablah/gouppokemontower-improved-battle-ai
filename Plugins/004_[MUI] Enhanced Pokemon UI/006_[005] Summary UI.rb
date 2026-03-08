#===============================================================================
# Summary UI edits.
#===============================================================================
class PokemonSummary_Scene
  #-----------------------------------------------------------------------------
  # Aliased to add shiny leaf display.
  #-----------------------------------------------------------------------------
  alias enhanced_drawPage drawPage
  def drawPage(page)
    enhanced_drawPage(page)
    return if !Settings::SUMMARY_SHINY_LEAF
    overlay = @sprites["overlay"].bitmap
    coords = (PluginManager.installed?("BW Summary Screen")) ? [Graphics.width - 18, 114] : [182, 124]
    pbDisplayShinyLeaf(@pokemon, overlay, coords[0], coords[1])
  end
  
  #-----------------------------------------------------------------------------
  # Aliased to add happiness meter display.
  #-----------------------------------------------------------------------------
  alias enhanced_drawPageOne drawPageOne
  def drawPageOne
    enhanced_drawPageOne
    return if !Settings::SUMMARY_HAPPINESS_METER
    overlay = @sprites["overlay"].bitmap
    coords = (PluginManager.installed?("BW Summary Screen")) ? [220, 294] : [242, 340]
    pbDisplayHappiness(@pokemon, overlay, coords[0], coords[1])
  end
  
  #-----------------------------------------------------------------------------
  # Aliased to add IV rankings display.
  #-----------------------------------------------------------------------------
  alias enhanced_drawPageThree drawPageThree
  def drawPageThree
    (@statToggle) ? drawEnhancedStats : enhanced_drawPageThree
    return if !Settings::SUMMARY_IV_RATINGS
    overlay = @sprites["overlay"].bitmap
    coords = (PluginManager.installed?("BW Summary Screen")) ? [110, 83] : [465, 83]
    pbDisplayIVRating(@pokemon, overlay, coords[0], coords[1])
  end
	
  def pbDisplayIVRating(*args)
    return if args.length == 0
    pbDisplayIVRatings(*args)
  end
  
  #-----------------------------------------------------------------------------
  # Aliased to add a toggle for the Enhanced Stats display.
  #-----------------------------------------------------------------------------
  alias enhanced_pbPageCustomUse pbPageCustomUse
  def pbPageCustomUse(page_id)
    if page_id == :page_skills
      @statToggle = !@statToggle
      drawPage(:page_skills)
      pbPlayDecisionSE
      return true
    end
    return enhanced_pbPageCustomUse(page_id)
  end

  #-----------------------------------------------------------------------------
  # Aliased to add Legacy data display.
  #-----------------------------------------------------------------------------
  alias enhanced_pbStartScene pbStartScene
  def pbStartScene(*args)
    if Settings::SUMMARY_LEGACY_DATA
      UIHandlers.edit_hash(:summary, :page_memo, "options", 
        [:item, :nickname, :pokedex, _INTL("기록 보기"), :mark]
      )
    end
    @statToggle = false
    enhanced_pbStartScene(*args)
    @sprites["legacy_overlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    pbSetSystemFont(@sprites["legacy_overlay"].bitmap)
    @sprites["legacyicon"] = PokemonIconSprite.new(@pokemon, @viewport)
    @sprites["legacyicon"].setOffset(PictureOrigin::CENTER)
    @sprites["legacyicon"].visible = false
  end

  alias enhanced_pbPageCustomOption pbPageCustomOption
  def pbPageCustomOption(cmd)
    if cmd == _INTL("기록 보기")
      pbLegacyMenu
      return true
    end
    return enhanced_pbPageCustomOption(cmd)
  end
  
  #-----------------------------------------------------------------------------
  # Legacy data menu.
  #-----------------------------------------------------------------------------
  TOTAL_LEGACY_PAGES = 3
  
  def pbLegacyMenu    
    base    = Color.new(64, 64, 64)
    shadow  = Color.new(176, 176, 176)
    base2   = Color.new(248, 248, 248)
    shadow2 = Color.new(64, 64, 64)
    path = Settings::POKEMON_UI_GRAPHICS_PATH
    legacy_overlay = @sprites["legacy_overlay"].bitmap
    legacy_overlay.clear
    ypos = 62
    index = 0
    @sprites["legacyicon"].x = 64
    @sprites["legacyicon"].y = ypos + 68
    @sprites["legacyicon"].pokemon = @pokemon
    @sprites["legacyicon"].visible = true
    data = @pokemon.legacy_data
    dorefresh = true
    loop do
      Graphics.update
      Input.update
      pbUpdate
      textpos = []
      imagepos = []
      if Input.trigger?(Input::BACK)
        break
      elsif Input.trigger?(Input::UP) && index > 0
        index -= 1
        pbPlayCursorSE
        dorefresh = true
      elsif Input.trigger?(Input::DOWN) && index < TOTAL_LEGACY_PAGES - 1
        index += 1
        pbPlayCursorSE
        dorefresh = true
      end
      if dorefresh
        case index
        when 0  # General
          name = _INTL("일반 기록")
          hour = data[:party_time].to_i / 60 / 60
          min  = data[:party_time].to_i / 60 % 60
          addltext = [
            [_INTL("파티에 함께한 시간:"),    "#{hour}시간 #{min}분"],
            [_INTL("사용한 아이템:"),         data[:item_count]],
            [_INTL("배운 기술:"),          data[:move_count]],
            [_INTL("낳은 알:"),          data[:egg_count]],
            [_INTL("교환 횟수:"), data[:trade_count]]
          ]
        when 1  # Battle History
          name = _INTL("배틀 기록")
          addltext = [
            [_INTL("쓰러뜨린 적:"),        data[:defeated_count]],
            [_INTL("기절 횟수:"),   data[:fainted_count]],
            [_INTL("효과가 뛰어난 공격:"), data[:supereff_count]],
            [_INTL("급소에 맞춘 공격:"),       data[:critical_count]],
            [_INTL("교체 및 도망:"),  data[:retreat_count]]
          ]
        when 2  # Team History
          name = _INTL("팀 기록")
          addltext = [
            [_INTL("트레이너 배틀 승리:"),        data[:trainer_count]],
            [_INTL("체육관 배틀 승리:"),     data[:leader_count]],
            [_INTL("전설의포켓몬 배틀 승리:"), data[:legend_count]],
            [_INTL("명예의전당 등록:"),   data[:champion_count]],
            [_INTL("무승부 및 패배:"),           data[:loss_count]]
          ]
        end
        textpos.push([_INTL("{1}의 기록", @pokemon.name.upcase), 295, ypos + 38, :center, base2, shadow2],
                     [name, Graphics.width / 2, ypos + 90, :center, base, shadow])
        addltext.each_with_index do |txt, i|
          textY = ypos + 134 + (i * 32)
          textpos.push([txt[0], 38, textY, :left, base, shadow])
          textpos.push([_INTL("{1}", txt[1]), Graphics.width - 38, textY, :right, base, shadow])
        end
        imagepos.push([path + "bg_legacy", 0, ypos])
        if index > 0
          imagepos.push([path + "arrows_legacy", 118, ypos + 84, 0, 0, 32, 32])
        end
        if index < TOTAL_LEGACY_PAGES - 1
          imagepos.push([path + "arrows_legacy", 362, ypos + 84, 32, 0, 32, 32])
        end
        legacy_overlay.clear
        pbDrawImagePositions(legacy_overlay, imagepos)
        pbDrawTextPositions(legacy_overlay, textpos)
        dorefresh = false
      end
    end
    legacy_overlay.clear
    @sprites["legacyicon"].visible = false
  end
  
  #-----------------------------------------------------------------------------
  # Enhanced stats display.
  #-----------------------------------------------------------------------------
  def drawEnhancedStats
    overlay = @sprites["overlay"].bitmap
    base   = Color.new(248, 248, 248)
    shadow = Color.new(104, 104, 104)
    base2 = Color.new(64, 64, 64)
    shadow2 = Color.new(176, 176, 176)
    index = 0
    ev_total = 0
    iv_total = 0
    textpos = []
    GameData::Stat.each_main do |s|
      case s.id
      when :HP then xpos, ypos, align = 292, 82, :center
      else xpos, ypos, align = 248, 94 + (32 * index), :left
      end
      name = (s.id == :SPECIAL_ATTACK) ? _INTL("Special Attack") : (s.id == :SPECIAL_DEFENSE) ? _INTL("Special Defense") : s.name
      statshadow = shadow
      if !@pokemon.shadowPokemon? || @pokemon.heartStage <= 3
        @pokemon.nature_for_stats.stat_changes.each do |change|
          next if s.id != change[0]
          if change[1] > 0
            statshadow = Color.new(136, 96, 72)
          elsif change[1] < 0
            statshadow = Color.new(64, 120, 152)
          end
        end
      end
      textpos.push(
        [_INTL("{1}", name), xpos, ypos, align, base, statshadow],
        [_INTL("|"), 424, ypos, :right, base2, shadow2],
        [@pokemon.ev[s.id].to_s, 408, ypos, :right, base2, shadow2],
        [@pokemon.iv[s.id].to_s, 456, ypos, :right, base2, shadow2]
      )
      ev_total += @pokemon.ev[s.id]
      iv_total += @pokemon.iv[s.id]
      index += 1
    end
    textpos.push(
      [_INTL("EV/IV 총합"), 224, 290, :left, base, shadow],
      [sprintf("%d  |  %d", ev_total, iv_total), 434, 290, :center, base2, shadow2],
      [_INTL("남아있는 EV:"), 224, 322, :left, base2, shadow2],
      [sprintf("%d/%d", Pokemon::EV_LIMIT - ev_total, Pokemon::EV_LIMIT), 444, 322, :center, base2, shadow2],
      [_INTL("히든파워 타입:"), 224, 354, :left, base2, shadow2]
    )
    original_size = overlay.font.size
    overlay.font.size = 20  # Smaller text for enhanced stats
    pbDrawTextPositions(overlay, textpos)
    overlay.font.size = original_size
    if @pokemon.hp > 0
      w = @pokemon.hp * 96 / @pokemon.totalhp.to_f
      w = 1 if w < 1
      w = ((w / 2).round) * 2
      hpzone = 0
      hpzone = 1 if @pokemon.hp <= (@pokemon.totalhp / 2).floor
      hpzone = 2 if @pokemon.hp <= (@pokemon.totalhp / 4).floor
      imagepos = [
        ["Graphics/UI/Summary/overlay_hp", 360, 110, 0, hpzone * 6, w, 6]
      ]
      pbDrawImagePositions(overlay, imagepos)
    end
    hiddenpower = pbHiddenPower(@pokemon)
    type_number = GameData::Type.get(hiddenpower[0]).icon_position
    type_rect = Rect.new(0, type_number * 28, 64, 28)
    overlay.blt(428, 351, @typebitmap.bitmap, type_rect)
  end
end