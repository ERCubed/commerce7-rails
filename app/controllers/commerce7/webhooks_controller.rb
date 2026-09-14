# frozen_string_literal: true

module Commerce7
  # Receives Commerce7's Web Hooks — configured once, app-wide, in the
  # Developer Center's app version under "Step 1. APIs & Webhooks", NOT
  # per-tenant. Per Commerce7's docs (developer.commerce7.com/docs/
  # app-apis-webhooks), a webhook registered there applies automatically to
  # every tenant that installs the app, no per-winery setup required — this
  # is a different, app-level mechanism from a store's own independent
  # "Developer > Web Hooks" admin page, which is for a winery's own
  # integrations, unrelated to marketplace apps like this one.
  #
  # Per Commerce7's docs (developer.commerce7.com/docs/webhooks), the body
  # is {object, action, payload, user, tenantId}; object/action cover far
  # more than any one app acts on, so this only parses and dispatches —
  # see Commerce7::Webhooks for how a host app registers what it cares
  # about. Anything with no registered handler is silently a no-op rather
  # than an error.
  class WebhooksController < BaseController
    # `action` is also the name Rails reserves for the controller action
    # itself (routing sets params[:action] = "create" on every request
    # regardless of body content) — reading it via `params` would silently
    # return "create" no matter what Commerce7 actually sent, matching no
    # registered handler and turning every webhook into a silent no-op.
    # Parsing the raw JSON body instead sidesteps that collision entirely.
    def create
      body = JSON.parse(request.body.read)
      return head :bad_request unless body["tenantId"].present? && body["object"].present? && body["action"].present?

      tenant = Commerce7.configuration.tenant_class.active.find_by(commerce7_tenant_id: body["tenantId"])
      handle(tenant, object: body["object"], action: body["action"], payload: body["payload"] || {}, actor: body["user"]) if tenant

      head :ok
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def handle(tenant, object:, action:, payload:, actor:)
      handled = Commerce7::Webhooks.dispatch(object: object, action: action, tenant: tenant, payload: payload, actor: actor)
      return unless handled

      Commerce7.audit!(
        event_type: "webhook_#{object.parameterize(separator: '_')}_#{action.downcase}",
        success: true,
        actor: actor,
        commerce7_tenant_id: tenant.commerce7_tenant_id,
        origin_ip: request.remote_ip
      )
    end
  end
end
