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


module Settings
  ANIMATION_FRAME_DELAY = 240
end