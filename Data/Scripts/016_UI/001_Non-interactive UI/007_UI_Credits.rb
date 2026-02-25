#==============================================================================
# * Scene_Credits
#------------------------------------------------------------------------------
# Scrolls the credits you make below. Original Author unknown.
#
## Edited by MiDas Mike so it doesn't play over the Title, but runs by calling
# the following:
#    $scene = Scene_Credits.new
#
## New Edit 3/6/2007 11:14 PM by AvatarMonkeyKirby.
# Ok, what I've done is changed the part of the script that was supposed to make
# the credits automatically end so that way they actually end! Yes, they will
# actually end when the credits are finished! So, that will make the people you
# should give credit to now is: Unknown, MiDas Mike, and AvatarMonkeyKirby.
#                                             -sincerly yours,
#                                               Your Beloved
# Oh yea, and I also added a line of code that fades out the BGM so it fades
# sooner and smoother.
#
## New Edit 24/1/2012 by Maruno.
# Added the ability to split a line into two halves with <s>, with each half
# aligned towards the centre. Please also credit me if used.
#
## New Edit 22/2/2012 by Maruno.
# Credits now scroll properly when played with a zoom factor of 0.5. Music can
# now be defined. Credits can't be skipped during their first play.
#
## New Edit 25/3/2020 by Maruno.
# Scroll speed is now independent of frame rate. Now supports non-integer values
# for SCROLL_SPEED.
#
## New Edit 21/8/2020 by Marin.
# Now automatically inserts the credits from the plugins that have been
# registered through the PluginManager module.
#==============================================================================
class Scene_Credits
  # Backgrounds to show in credits. Found in Graphics/Titles/ folder
  BACKGROUNDS_LIST       = ["credits1", "credits2", "credits3", "credits4", "credits5"]
  BGM                    = "Tower Title"
  SCROLL_SPEED           = 40   # Pixels per second
  SECONDS_PER_BACKGROUND = 11
  TEXT_OUTLINE_COLOR     = Color.new(0, 0, 128, 255)
  TEXT_BASE_COLOR        = Color.new(255, 255, 255, 255)
  TEXT_SHADOW_COLOR      = Color.new(0, 0, 0, 100)

  def add_names_to_credits(credits, names, with_final_new_line = true)
    if names.length >= 5
      i = 0
      loop do
        credits.push(names[i] + "<s>" + (names[i + 1] || ""))
        i += 2
        break if i >= names.length
      end
    else
      names.each { |name| credits.push(name) }
    end
    credits.push("") if with_final_new_line
  end

  def get_text
    ret = Settings.game_credits || []
    # Add plugin credits
    if PluginManager.plugins.length > 0
      ret.push("", "", "")
      PluginManager.plugins.each do |plugin|
        pcred = PluginManager.credits(plugin)
        ret.push(_INTL("\"{1}\" v.{2} by:", plugin, PluginManager.version(plugin)))
        add_names_to_credits(ret, pcred)
      end
    end
    # Add Essentials credits
    ret.push("", "", "")
    ret.push(_INTL("\"Pokémon Essentials\" was created by:"))
    add_names_to_credits(ret, [
      "Poccil (Peter O.)",
      "Maruno",
      _INTL("Inspired by work by Flameguru")
    ])
    ret.push(_INTL("With contributions from:"))
    add_names_to_credits(ret, [
      "AvatarMonkeyKirby", "Boushy", "Brother1440", "FL.", "Genzai Kawakami",
      "Golisopod User", "help-14", "IceGod64", "Jacob O. Wobbrock", "KitsuneKouta",
      "Lisa Anthony", "Luka S.J.", "Marin", "MiDas Mike", "Near Fantastica",
      "PinkMan", "Popper", "Rataime", "Savordez", "SoundSpawn",
      "the__end", "Venom12", "Wachunga"
    ], false)
    ret.push("")
    ret.push(_INTL("MAP BY"))
    ret.push("")
    ret.push(_INTL("YOUNG"))
    ret.push("")
    ret.push(_INTL("Tiles"))
    add_names_to_credits(ret, [
    "GameFreak","SirMalo's HGSS Rips for RMXP","La Pampa - Epic Adventures > Tileset from Pokemon Epic Adventures (La Pampa) https://pokemonworkshop.com/forum/index.php?topic=409",
    "Kyledove - Some overworld tiles","SailorVicious - Some overworld tiles","hek-el-grande, light-pa, zerudez, phyromatical - Lava/volcanic tiles",
    "Flurmimon - A few cave tiles","Rayquaza Dot - Some overworld tiles","ChaoticCherryCake - Truck from Public Tiles",
    "DeepBluePacificWaves - HGSS Water", "Outside Emerald"
    ])
    ret.push("")
    ret.push("")
    ret.push(_INTL("ADDITIONAL TILSET BY"))
    add_names_to_credits(ret, [
    "Cinna", "lichenprincess", "Newtiteuf", "Seiyouh", "Pablus94", "Sharm", "Mi",
    "PureAzure", "SDV", "Shen", "Spriters Resource Exclusive Content", "LarkyLovesYou", "victorcavalhosp"
    ])
    ret.push("")
    ret.push("")
    ret.push(_INTL("CHARACTER SPRITE BY"))
    add_names_to_credits(ret, [
    "aveontrainer","CyberStryke7","Lolw3e932","HighNoonMoon","Miused","wjj36",
    "xDracolich","PurpleZaffre","UlithiumDragon","YOUNG"
    ])
    ret.push("")
    ret.push(_INTL("Accurate FRLG-style NPC Megapack"))
    add_names_to_credits(ret, [
    "Maribel Hearn and Renko Usami sprites courtesy of Hemoglobin_A1C (Playable Characters in Touhoumon fangames).",
    "HGSS OWs in FR Style courtesy of Delta231, Mimi, M.vit, and Kimoras.",
    "Accurate Fire Red Overworld Sprite ResourceAvatar: Psychic (Male), Rich Boy, Cue Ball (Dismounted)",
    "Aveontrainer: Lass, a lot of bases for Emerald's Overworld Sprites",
    "Daman: Professor Ivy, Professor Ivy's Assistant",
    "Kalarie: Aroma Lady, Blackbelt, Burglar, Crush Girl, Dragon Tamer, Engineer, Juggler, Lady, Pokémon Breeder, Psychic (Female), Rocker, Tamer, Twin, Young Couple, All Anime Sprites",
    "MrDollSteak: Cue Ball, Cue Ball (Dismounted), Painter, PokéManiac, Pokémon Ranger (Male), Pokémon Ranger (Female)",
    "Pokésho: Various First Frames of Anime Overworld Sprites",
    "Spherical Ice: Biker (Dismounted), Bird Keeper, Expert (Male), Expert (Female), Kindler, Ruin Maniac",
    "FRLG Pokédude Backsprite Ripped by Tsuka",
    "Koiking Player Sprites courtesy of pixiv",
    "FRLG Style RSE NPCs, ORAS Brendan and May courtesy of Poffin_Case",
    "Gen 4 and 5 Trainer sprites and PBS Courtesy of Mr. Gela/theo#7722",
    "FRLG Cynthia, Hilbert, Hilda, Ethan and Lyra Sprites courtesy of Pokésho, Marnic, Reign, and KisiroKitsune",
    "TR Grunt courtesy of Othienka",
    "Brendan and May Extra Sprites courtesy of GreenWithAwesome / 15avaughn",
    "HGSS Ethan and Lyra Back Sprites 0.2; Ripped by Tsuka from Spriters Resource. Original graphics by Game Freak. Formatted by Ozander.",
    "PUBLIC OrAs Protagonists GBA Back and Front Sprites by Solo993; Additional Front Sprites by hyo-oppa",
    ])
    ret.push("")
    ret.push(_INTL("HGSS MAP KIT"))
    ret.push(_INTL("NikNaks93"))
    ret.push("")
    ret.push("")
    ret.push(_INTL("TRAINER SPRITE BY"))
    add_names_to_credits(ret, [
    "GeroisBlackboots","kyledove","Brumirage",
    "Beliot419","Gnomowladny","mid117","Sophocles",
    "Miused","ShiningStar5022","PIXAI","YOUNG"
    ])
    ret.push("")
    ret.push("")
    ret.push(_INTL("MUSIC by"))
    add_names_to_credits(ret, [
    "Gamefreak","YOUNG"
    ])
    ret.push("")
    ret.push("")
    ret.push(_INTL("TEST PLAY BY"))
    ret.push("강멍꿀")
    ret.push("팔로")
    ret.push("구미")
    ret.push("서라")
    ret.push("이포그")
    ret.push("pieris")
    ret.push("구취소콩밥도둑")
    ret.push("")
    ret.push("Special Thanks to")
    ret.push("강멍꿀")
    ret.push("")
    ret.push("")
    ret.push(_INTL("\"mkxp-z\" by:"))
    add_names_to_credits(ret, [
      "Roza",
      _INTL("Based on \"mkxp\" by Ancurio et al.")
    ])
    ret.push(_INTL("\"RPG Maker XP\" by:"))
    add_names_to_credits(ret, ["Enterbrain"])
    ret.push(_INTL("Pokémon is owned by:"))
    add_names_to_credits(ret, [
      "The Pokémon Company",
      "Nintendo",
      _INTL("Affiliated with Game Freak")
    ])
    ret.push("", "")
    ret.push(_INTL("This is a non-profit fan-made game."),
             _INTL("No copyright infringements intended."),
             _INTL("Please support the official games!"))
    return ret
  end

  def main
    @quit = false
    #-------------------------------
    # Animated Background Setup
    #-------------------------------
    @timer_start = System.uptime   # Time when the credits started
    @bg_index = 0
    @bitmap_height = Graphics.height   # For a single credits text bitmap
    @trim = Graphics.height / 10
    # Number of game frames per background frame
    @realOY = -(Graphics.height - @trim)
    #-------------------------------
    # Credits text Setup
    #-------------------------------
    credit_lines = get_text
    #-------------------------------
    # Make background and text sprites
    #-------------------------------
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99999
    text_viewport = Viewport.new(0, @trim, Graphics.width, Graphics.height - (@trim * 2))
    text_viewport.z = 99999
    @background_sprite = IconSprite.new(0, 0)
    @background_sprite.setBitmap("Graphics/Titles/" + BACKGROUNDS_LIST[0])
    @credit_sprites = []
    @total_height = credit_lines.size * 32
    lines_per_bitmap = @bitmap_height / 32
    num_bitmaps = (credit_lines.size.to_f / lines_per_bitmap).ceil
    num_bitmaps.times do |i|
      credit_bitmap = Bitmap.new(Graphics.width, @bitmap_height + 16)
      pbSetSystemFont(credit_bitmap)
      lines_per_bitmap.times do |j|
        line = credit_lines[(i * lines_per_bitmap) + j]
        next if !line
        line += " " if line.end_with?("<s>")
        line = line.split("<s>")
        xpos = 0
        align = 1   # Centre align
        linewidth = Graphics.width
        line.length.times do |k|
          text = line[k].strip
          if line.length > 1
            xpos = (k == 0) ? 0 : 20 + (Graphics.width / 2)
            align = (k == 0) ? 2 : 0   # Right align : left align
            linewidth = (Graphics.width / 2) - 20
          end
          credit_bitmap.font.color = TEXT_SHADOW_COLOR
          credit_bitmap.draw_text(xpos, (j * 32) + 12, linewidth, 32, text, align)
          credit_bitmap.font.color = TEXT_OUTLINE_COLOR
          credit_bitmap.draw_text(xpos + 2, (j * 32) + 2, linewidth, 32, text, align)
          credit_bitmap.draw_text(xpos,     (j * 32) + 2, linewidth, 32, text, align)
          credit_bitmap.draw_text(xpos - 2, (j * 32) + 2, linewidth, 32, text, align)
          credit_bitmap.draw_text(xpos + 2, (j * 32) + 4, linewidth, 32, text, align)
          credit_bitmap.draw_text(xpos - 2, (j * 32) + 4, linewidth, 32, text, align)
          credit_bitmap.draw_text(xpos + 2, (j * 32) + 6, linewidth, 32, text, align)
          credit_bitmap.draw_text(xpos,     (j * 32) + 6, linewidth, 32, text, align)
          credit_bitmap.draw_text(xpos - 2, (j * 32) + 6, linewidth, 32, text, align)
          credit_bitmap.font.color = TEXT_BASE_COLOR
          credit_bitmap.draw_text(xpos, (j * 32) + 4, linewidth, 32, text, align)
        end
      end
      credit_sprite = Sprite.new(text_viewport)
      credit_sprite.bitmap = credit_bitmap
      credit_sprite.z      = 9998
      credit_sprite.oy     = @realOY - (@bitmap_height * i)
      @credit_sprites[i] = credit_sprite
    end
    #-------------------------------
    # Setup
    #-------------------------------
    # Stops all audio but background music
    previousBGM = $game_system.getPlayingBGM
    pbMEStop
    pbBGSStop
    pbSEStop
    pbBGMFade(2.0)
    pbBGMPlay(BGM)
    Graphics.transition
    loop do
      Graphics.update
      Input.update
      update
      break if @quit
    end
    $game_temp.background_bitmap = Graphics.snap_to_bitmap
    pbBGMFade(2.0)
    Graphics.freeze
    viewport.color = Color.black   # Ensure screen is black
    text_viewport.color = Color.black   # Ensure screen is black
    Graphics.transition(8, "fadetoblack")
    $game_temp.background_bitmap.dispose
    @background_sprite.dispose
    @credit_sprites.each { |s| s&.dispose }
    viewport.dispose
    text_viewport.dispose
    $PokemonGlobal.creditsPlayed = true
    pbBGMPlay(previousBGM)
    $scene = ($game_map) ? Scene_Map.new : nil
  end

  # Check if the credits should be cancelled
  def cancel?
    @quit = true if Input.trigger?(Input::USE) && $PokemonGlobal.creditsPlayed
    return @quit
  end

  # Checks if credits bitmap has reached its ending point
  def last?
    @quit = true if @realOY > @total_height + @trim
    return @quit
  end

  def update
    # Go to next slide
    new_bg_index = ((System.uptime - @timer_start) / SECONDS_PER_BACKGROUND) % BACKGROUNDS_LIST.length
    if @bg_index != new_bg_index
      @bg_index = new_bg_index
      @background_sprite.setBitmap("Graphics/Titles/" + BACKGROUNDS_LIST[@bg_index])
    end
    return if cancel?
    return if last?
    @realOY = (SCROLL_SPEED * (System.uptime - @timer_start)) - Graphics.height + @trim
    @credit_sprites.each_with_index { |s, i| s.oy = @realOY - (@bitmap_height * i) }
  end
end
