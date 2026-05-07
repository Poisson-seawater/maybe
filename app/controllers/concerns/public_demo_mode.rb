module PublicDemoMode
  extend ActiveSupport::Concern

  included do
    before_action :block_public_demo_write_requests

    helper_method :public_demo_mode?
  end

  private
    def public_demo_mode?
      PublicDemoConfig.enabled?
    end

    def block_public_demo_write_requests
      return unless public_demo_mode?
      return if request.get? || request.head?

      message = "This public demo is read-only."

      respond_to do |format|
        format.json { render json: { error: message }, status: :forbidden }
        format.any { redirect_to root_path, alert: message, status: :see_other }
      end
    end
end
