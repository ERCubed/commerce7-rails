# frozen_string_literal: true

module Commerce7
  # Receives Commerce7's deactivation POST on app uninstall. Soft-deactivates
  # the tenant (never hard-deletes) so a reinstall can reactivate the same
  # record — see Commerce7::TenantConcern#activate! and
  # Commerce7::PurgeDeactivatedTenantsJob, which enforces the actual
  # post-uninstall deletion after a retention window. A tenantId this app
  # doesn't recognize is a no-op, not an error, since webhook/POST retries
  # are common and shouldn't fail loudly.
  class DeactivationsController < BaseController
    def create
      tenant = Commerce7.configuration.tenant_class.find_by(commerce7_tenant_id: params.require(:tenantId))
      if tenant
        tenant.deactivate!
        Commerce7.run_deactivate_hooks(tenant)
        Commerce7.audit!(event_type: "tenant_deactivated", success: true, commerce7_tenant_id: tenant.commerce7_tenant_id, origin_ip: request.remote_ip)
      end

      head :ok
    end
  end
end
