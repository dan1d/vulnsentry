class Admin::SettingsController < Admin::BaseController
  def show
    @config = BotConfig.instance
  end

  def edit
    @config = BotConfig.instance
  end

  def update
    @config = BotConfig.instance
    if @config.update(bot_config_params)
      redirect_to admin_settings_path, notice: "Settings updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def bot_config_params
      params.require(:bot_config).permit(
        :require_human_approval,
        :emergency_stop,
        :allow_draft_pr,
        :global_daily_cap,
        :global_hourly_cap,
        :per_branch_daily_cap,
        :per_gem_daily_cap,
        :rejection_cooldown_hours,
        :fork_repo,
        :upstream_repo,
        :fork_git_url
      )
    end
end
