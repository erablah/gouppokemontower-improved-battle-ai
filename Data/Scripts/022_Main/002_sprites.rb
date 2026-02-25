class Spriteset_Map
  alias custom_sprite_initialize initialize
  def initialize(*args)
    custom_sprite_initialize(*args)
    @custom_sprite = nil
    @custom_sprite_map_id = nil
    @custom_sprite_filename = nil
    @custom_sprite_prev_x = nil
    @custom_sprite_prev_y = nil
    @custom_sprite_ready = false
    update_custom_map_sprite(true) # 최초 1회 즉시 적용
  end

  alias custom_sprite_dispose dispose
  def dispose
    dispose_custom_map_sprite
    custom_sprite_dispose
  end

  alias custom_sprite_update update
  def update
    custom_sprite_update
    update_custom_map_sprite
  end

  # 스프라이트 업데이트 메인
  def update_custom_map_sprite(force_init = false)
    # ======= <<1>> 내 맵이 실제 플레이 중인 맵이 아니면 sprite 제거 =======
    # (map connection 중에 여러 Spriteset_Map이 동시에 관리되기 때문)
    return dispose_custom_map_sprite if !@map || $game_map.map_id != @map.map_id

    map_id = $game_map.map_id
    filename = sprintf("Graphics/Pictures/Map%02d.png", map_id)
    is_night = defined?(PBDayNight) ? PBDayNight.isNight? : false
    need_sprite = is_night && FileTest.exist?(filename)

    # ========== <<2>> 화면 tone(암전 등) 체크 ==========
    screen_blackout = false
    if $game_screen && $game_screen.tone
      tone = $game_screen.tone
      screen_blackout = (
        tone.gray <= -120 ||
        (tone.red <= -120 && tone.green <= -120 && tone.blue <= -120)
      )
    end

    # ========== <<3>> 실제 스프라이트를 만들/삭제 ==========
    if need_sprite && !screen_blackout
      if @custom_sprite.nil? || @custom_sprite.disposed? ||
         @custom_sprite_map_id != map_id || @custom_sprite_filename != filename || force_init
        dispose_custom_map_sprite
        @custom_sprite = Sprite.new(@viewport1)
        @custom_sprite.bitmap = Bitmap.new(filename)
        @custom_sprite.opacity = 220
        @custom_sprite.blend_type = 0
        @custom_sprite.z = 200
        @custom_sprite_map_id = map_id
        @custom_sprite_filename = filename
        @custom_sprite_ready = false
        @custom_sprite_prev_x = $game_map.display_x
        @custom_sprite_prev_y = $game_map.display_y
        @custom_sprite.visible = false # 최초에는 숨김
      end
      # ---- 좌표 업데이트
      @custom_sprite.x = -($game_map.display_x / 4).round
      @custom_sprite.y = -($game_map.display_y / 4).round

      # ---- 최초 한 번만 움직임 감지 후 visible
      unless @custom_sprite_ready
        if $game_map.display_x != @custom_sprite_prev_x || $game_map.display_y != @custom_sprite_prev_y
          @custom_sprite.visible = true
          @custom_sprite_ready = true
        end
        @custom_sprite_prev_x = $game_map.display_x
        @custom_sprite_prev_y = $game_map.display_y
      else
        @custom_sprite.visible = true
      end
    else
      dispose_custom_map_sprite
    end
  end

  # 안전한 스프라이트 제거
  def dispose_custom_map_sprite
    if @custom_sprite && !@custom_sprite.disposed?
      @custom_sprite.dispose rescue nil
    end
    @custom_sprite = nil
    @custom_sprite_map_id = nil
    @custom_sprite_filename = nil
    @custom_sprite_ready = nil
    @custom_sprite_prev_x = nil
    @custom_sprite_prev_y = nil
  end
end
