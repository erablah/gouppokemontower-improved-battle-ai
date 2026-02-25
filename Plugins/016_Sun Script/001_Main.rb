module SunSettings
  BGPATH = "Graphics/Fogs/sun.png"
  UPDATESPERSECONDS = 5
end

class Spriteset_Map
  def createSun; end
  def updateSun; end
  def disposeSun; end
end

class Scene_Map
  include SunSettings

  alias sun_main main
  alias sun_update update

  def main(*args)
    create_sun_sprite
    sun_main(*args)
    dispose_sun_sprite
  end

  def update(*args)
    update_sun_sprite
    sun_update(*args)
  end

  def create_sun_sprite
    dispose_sun_sprite   # 혹시 남아있으면 정리
    map_metadata = GameData::MapMetadata.try_get($game_map.map_id)
    return unless map_metadata && map_metadata.outdoor_map
    return if PBDayNight.isNight? || $game_screen.weather_type != :None || $game_map.fog_name != ""
    @sun_sprite = Sprite.new
    @sun_sprite.bitmap = Bitmap.new(BGPATH)
    @sun_sprite.z = 9999
    @sun_sprite.opacity = calculateSunAlpha
    @sun_sprite.blend_type = 1
    @sun_sprite.x = 0
    @sun_sprite.y = 0
  end

def update_sun_sprite
  map_metadata = GameData::MapMetadata.try_get($game_map.map_id)
  tone = $game_screen.tone
  is_screen_black = tone.red <= -200 && tone.green <= -200 && tone.blue <= -200

  sun_condition = map_metadata && map_metadata.outdoor_map &&
                  !PBDayNight.isNight? && $game_screen.weather_type == :None &&
                  $game_map.fog_name == "" && !is_screen_black

  if sun_condition
    if @sun_sprite.nil?
      create_sun_sprite
    end
    @sun_sprite.opacity = calculateSunAlpha if @sun_sprite
    @sun_sprite.visible = true if @sun_sprite
  else
    dispose_sun_sprite
  end
end

  def dispose_sun_sprite
    if @sun_sprite
      @sun_sprite.dispose
      @sun_sprite = nil
    end
  end

  def calculateSunAlpha
    current_time = pbGetTimeNow
    hour = current_time.hour
    alpha = 255
    if hour >= 6 && hour <= 18
      alpha = 255
    elsif hour > 18 && hour <= 20
      alpha = 255 - ((hour - 1) * 100).to_i
    elsif hour >= 4 && hour < 6
      alpha = ((hour - 4) * 100).to_i
    else
      alpha = 0
    end
    return alpha
  end
end
