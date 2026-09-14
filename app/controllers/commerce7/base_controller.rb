# frozen_string_literal: true

module Commerce7
  # Base for Commerce7 server-to-server POSTs: the app-wide Install/Uninstall
  # URLs (activation, deactivation) and the app-level Web Hooks feature. Not
  # browser requests, so this skips the CSRF check and doesn't inherit a
  # host app's ApplicationController (e.g. its allow_browser restriction).
  #
  # Auth is HTTP Basic in both cases, per Commerce7's docs: Install/Uninstall
  # URLs support an optional username/password configured in their
  # dashboard's "Advanced" section, and a Web Hook registered in the same
  # Developer Center app version supports the same "Advanced Authentication"
  # — both are a single app-wide credential pair set once, not something
  # each tenant configures (see Commerce7.configuration.webhook_credentials).
  class BaseController < ActionController::Base
    # Explicit rather than relying on a host app's `default_protect_from_forgery`
    # config default — this gem shouldn't depend on that being set for its
    # own controllers' safety. Immediately skipped below since these are
    # server-to-server requests with no session/cookie to forge against.
    protect_from_forgery with: :exception
    skip_before_action :verify_authenticity_token, raise: false

    before_action :authenticate_commerce7!

    rescue_from ActionController::ParameterMissing do |error|
      render json: { error: error.message }, status: :bad_request
    end

    private

    # Deliberately not authenticate_or_request_with_http_basic: that method's
    # return value is truthy even on failure (it's a bare
    # `response_body = message` assignment under the hood — see
    # ActionController::HttpAuthentication::Basic::ProtectedMethods#authentication_request),
    # so it can't be used as a success/failure signal for auditing. Calling
    # authenticate_with_http_basic directly and handling the 401 ourselves
    # gives an unambiguous boolean instead.
    def authenticate_commerce7!
      return if authenticate_with_http_basic { |username, password| valid_commerce7_credentials?(username, password) }

      Commerce7.audit!(
        event_type: "commerce7_server_auth",
        success: false,
        commerce7_tenant_id: params[:tenantId],
        origin_ip: request.remote_ip,
        metadata: { path: request.path }
      )
      request_http_basic_authentication
    end

    def valid_commerce7_credentials?(username, password)
      expected_username, expected_password = Commerce7.configuration.webhook_credentials.call

      expected_username.present? && expected_password.present? &&
        ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &&
        ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
    end
  end
end
