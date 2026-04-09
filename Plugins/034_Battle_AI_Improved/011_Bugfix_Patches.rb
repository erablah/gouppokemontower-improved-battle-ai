# Battle-related bug fixes


class Battle::AI::AITrainer
  alias remove_flags_best_traniner set_up_skill_flags
  def set_up_skill_flags
    remove_flags_best_traniner
    if best_skill?
      @skill_flags.delete("ReserveLastPokemon")
    end
  end
end

# AI compute takes a lot of time, so slow animated battler frame stepping only
# while battle speedup is active.
class DeluxeBitmapWrapper
  alias _tower_speedup_aware_update update
  def update
    return false if self.disposed?
    return false if $PokemonSystem.animated_sprites > 0
    return false if @speed <= 0
    timer = System.uptime
    delay = ((@speed / 2.0) * Settings::ANIMATION_FRAME_DELAY).round / 1000.0
    if defined?($GameSpeed) && $GameSpeed && $GameSpeed > 0 &&
       defined?(SPEEDUP_STAGES) && SPEEDUP_STAGES[$GameSpeed]
      delay *= SPEEDUP_STAGES[$GameSpeed]
    end
    return if timer - @last_uptime < delay
    (@reversed) ? @frame_idx -= 1 : @frame_idx += 1
    @frame_idx = 0 if @frame_idx >= @total_frames
    @frame_idx = @total_frames - 1 if @frame_idx < 0
    @last_uptime = timer
  end
end
