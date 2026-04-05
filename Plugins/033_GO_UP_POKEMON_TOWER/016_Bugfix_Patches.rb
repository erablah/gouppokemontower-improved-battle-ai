# map event bug fixes


#===============================================================================
# Fix: Game_Character wait_start uses System.uptime which resets on game launch.
# If a character was saved mid-wait, wait_start will be from a previous session
# and the wait condition (System.uptime - wait_start < wait_count) can never
# be satisfied, permanently freezing the character.
#===============================================================================
class Game_Character
  alias _fix_stale_wait_update_command update_command
  def update_command
    if @wait_count > 0 && @wait_start && @wait_start > System.uptime
      @wait_start = System.uptime
    end
    _fix_stale_wait_update_command
  end
end


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
