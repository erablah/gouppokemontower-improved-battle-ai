#===============================================================================
#
#===============================================================================
class PokemonJukebox_Scene
  def pbUpdate
    pbUpdateSpriteHash(@sprites)
  end

  def pbStartScene(commands)
    @commands = commands
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @sprites["background"] = IconSprite.new(0, 0, @viewport)
    @sprites["background"].setBitmap(_INTL("Graphics/UI/jukebox_bg"))
    @sprites["header"] = Window_UnformattedTextPokemon.newWithSize(
      _INTL("Jukebox"), 2, -18, 128, 64, @viewport
    )
    @sprites["header"].baseColor   = Color.new(248, 248, 248)
    @sprites["header"].shadowColor = Color.black
    @sprites["header"].windowskin  = nil
    @sprites["commands"] = Window_CommandPokemon.newWithSize(
      @commands, 94, 92, 324, 224, @viewport
    )
    @sprites["commands"].windowskin = nil
    pbFadeInAndShow(@sprites) { pbUpdate }
  end

  def pbScene
    ret = -1
    loop do
      Graphics.update
      Input.update
      pbUpdate
      if Input.trigger?(Input::BACK)
        break
      elsif Input.trigger?(Input::USE)
        ret = @sprites["commands"].index
        break
      end
    end
    return ret
  end

  def pbSetCommands(newcommands, newindex)
    @sprites["commands"].commands = (!newcommands) ? @commands : newcommands
    @sprites["commands"].index    = newindex
  end

  def pbEndScene
    pbFadeOutAndHide(@sprites) { pbUpdate }
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end
end

#===============================================================================
#
#===============================================================================
class PokemonJukeboxScreen
  def initialize(scene)
    @scene = scene
  end

  def pbStartScreen
    commands = []
    cmdMarch   = -1
    cmdLullaby = -1
    cmdOak     = -1
    cmdMood = -1
    cmdForest = -1
    cmdVintage = -1
    cmdTurnOff = -1
    commands[cmdMarch = commands.length]   = _INTL("재생: 오프닝송")
    commands[cmdLullaby = commands.length] = _INTL("재생: 한남자의 이야기")
    commands[cmdOak = commands.length]     = _INTL("재생: 숲을 따라서")
    commands[cmdMood = commands.length]  = _INTL("재생: In The Mood")
    commands[cmdForest = commands.length]  = _INTL("재생: The Fairy's Forest")
    commands[cmdVintage = commands.length]  = _INTL("재생: Vintage Vibe")
    commands[cmdTurnOff = commands.length] = _INTL("Stop")
    commands[commands.length]              = _INTL("Exit")
    @scene.pbStartScene(commands)
    loop do
      cmd = @scene.pbScene
      if cmd < 0
        pbPlayCloseMenuSE
        break
      elsif cmdMarch >= 0 && cmd == cmdMarch
        pbPlayDecisionSE
        pbBGMPlay("Title", 100, 100)
        if $PokemonMap
          $PokemonMap.lower_encounter_rate = false
          $PokemonMap.higher_encounter_rate = true
        end
      elsif cmdLullaby >= 0 && cmd == cmdLullaby
        pbPlayDecisionSE
        pbBGMPlay("한남자의이야기", 100, 100)
        if $PokemonMap
          $PokemonMap.lower_encounter_rate = true
          $PokemonMap.higher_encounter_rate = false
        end
      elsif cmdOak >= 0 && cmd == cmdOak
        pbPlayDecisionSE
        pbBGMPlay("숲을 따라서", 100, 100)
        if $PokemonMap
          $PokemonMap.lower_encounter_rate = false
          $PokemonMap.higher_encounter_rate = false
        end
      elsif cmdMood >= 0 && cmd == cmdMood
        pbPlayDecisionSE
        pbBGMPlay("In the Mood", 100, 100)
        if $PokemonMap
          $PokemonMap.lower_encounter_rate = false
          $PokemonMap.higher_encounter_rate = false
        end
      elsif cmdForest >= 0 && cmd == cmdForest
        pbPlayDecisionSE
        pbBGMPlay("The Fairy's Forest", 100, 100)
        if $PokemonMap
          $PokemonMap.lower_encounter_rate = false
          $PokemonMap.higher_encounter_rate = false
        end
      elsif cmdVintage >= 0 && cmd == cmdVintage
        pbPlayDecisionSE
        pbBGMPlay("Vintage Vibe", 100, 100)
        if $PokemonMap
          $PokemonMap.lower_encounter_rate = false
          $PokemonMap.higher_encounter_rate = false
        end
      elsif cmdTurnOff >= 0 && cmd == cmdTurnOff
        pbPlayDecisionSE
        $game_system.setDefaultBGM(nil)
        pbBGMPlay(pbResolveAudioFile($game_map.bgm_name, $game_map.bgm.volume, $game_map.bgm.pitch))
        if $PokemonMap
          $PokemonMap.lower_encounter_rate = false
          $PokemonMap.higher_encounter_rate = false
        end
      else   # Exit
        pbPlayCloseMenuSE
        break
      end
    end
    @scene.pbEndScene
  end
end
