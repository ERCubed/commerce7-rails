# frozen_string_literal: true

module Commerce7
  # Receives Commerce7's activation POST on app install. Per Commerce7's
  # docs, this sends `tenantId` plus the installer's first name, last name,
  # and email — NOT API credentials. That's expected: the App ID/Secret Key
  # is a single app-wide pair (see Commerce7.configuration.app_credentials),
  # not something issued per tenant.
  class ActivationsController < BaseController
    def create
      tenant = Commerce7.configuration.tenant_class.activate!(
        commerce7_tenant_id: params.require(:tenantId),
        payload: activation_payload
      )

      # See Commerce7.on_activate — typically used to kick off a one-time
      # backfill sync, since Commerce7's Web Hooks only fire on future
      # changes, not a newly (re)installed tenant's pre-existing data.
      Commerce7.run_activate_hooks(tenant, activation_payload)

      Commerce7.audit!(event_type: "tenant_activated", success: true, commerce7_tenant_id: tenant.commerce7_tenant_id, origin_ip: request.remote_ip)

      head :ok
    end

    private

    def activation_payload
      params.except(:controller, :action).to_unsafe_h
    end
  end
end
