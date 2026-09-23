# frozen_string_literal: true

module Commerce7
  # Base for pages embedded as a Commerce7 App Extension (iframe). Commerce7
  # appends `tenantId` and `account` (a staff JWT) to the iframe src URL;
  # this validates that JWT against Commerce7's API and resolves
  # Current.tenant/Current.staff_user before any subclass action runs. A
  # host app is expected to define a top-level `Current < ActiveSupport::
  # CurrentAttributes` with `tenant` and `staff_user` attributes — the same
  # convention Rails apps already reach for to scope per-request state.
  class ExtensionController < ActionController::Base
    # Explicit rather than relying on a host app's `default_protect_from_forgery`
    # config default — this gem shouldn't depend on that being set for its
    # own controllers' safety. A subclass that adds a mutating, browser-
    # submitted action inherits this; Commerce7's staff-JWT re-validation on
    # every request (see authenticate_staff! below) is a second, independent
    # boundary a subclass can lean on if it needs to skip this one (e.g. for
    # a cross-site iframe POST where the session cookie may not travel).
    protect_from_forgery with: :exception

    before_action :authenticate_staff!

    # Rails sends X-Frame-Options: SAMEORIGIN by default, which blocks
    # Commerce7's admin panel (a different origin) from framing this page at
    # all. Commerce7 doesn't publish a stable admin origin to scope a
    # replacement CSP frame-ancestors to, so this just drops the blanket
    # deny; a host app that wants a tighter CSP can add its own
    # frame-ancestors directive once that origin is confirmed.
    after_action { response.headers.delete("X-Frame-Options") }

    rescue_from ActionController::ParameterMissing do |error|
      render plain: error.message, status: :bad_request
    end

    private

    def authenticate_staff!
      tenant_id = params.require(:tenantId)
      tenant = Commerce7.configuration.tenant_class.active.find_by(commerce7_tenant_id: tenant_id)
      unless tenant
        audit_auth!(success: false, tenant_id: tenant_id, reason: "unknown_or_deactivated_tenant")
        # Same real error page as a rejected staff token (see below), not a
        # bare status code — an uninstalled-then-still-open tab is the
        # common way staff land here.
        return render "commerce7/extension/unauthorized", status: :forbidden
      end

      Current.staff_user = Commerce7::AccountClient.new.fetch_user(tenant_id: tenant_id, token: params.require(:account))
      Current.tenant = tenant
      audit_auth!(success: true, tenant_id: tenant_id, actor: Current.staff_user["email"])
    rescue Commerce7::AccountClient::AuthenticationError
      audit_auth!(success: false, tenant_id: tenant_id, reason: "invalid_staff_token")
      # A host app can override this view (same path, its own app/views) to
      # match its own styling; this gem ships a plain-text fallback so
      # staff always see a real error page here, never a bare 401.
      render "commerce7/extension/unauthorized", status: :unauthorized
    end

    def audit_auth!(success:, tenant_id:, actor: nil, reason: nil)
      Commerce7.audit!(
        event_type: "staff_extension_auth",
        success: success,
        actor: actor,
        commerce7_tenant_id: tenant_id,
        origin_ip: request.remote_ip,
        metadata: reason ? { reason: reason } : {}
      )
    end
  end
end
