# frozen_string_literal: true

module Commerce7
  # Schedule this as a recurring job (e.g. Solid Queue's config/recurring.yml,
  # `schedule: every day at 3am`) to enforce Commerce7's app security policy:
  # customer data deleted within 30 days of app termination. Hard-deletes
  # any tenant still deactivated past Commerce7::TenantConcern::
  # DATA_RETENTION_DAYS — cascading to whatever `dependent: :destroy`
  # associations the host's tenant model declares.
  class PurgeDeactivatedTenantsJob < ::ActiveJob::Base
    queue_as :default

    def perform
      Commerce7.configuration.tenant_class.pending_deletion.find_each { |tenant| purge(tenant) }
    end

    private

    # Many tenant-scoped hosts (see the app's TenantScoped-style pattern)
    # resolve their default_scope through Current.tenant, which
    # `dependent: :destroy` associations rely on to find what to cascade —
    # skipping this can leave dependent rows behind, or make the tenant
    # DELETE itself fail outright against a real FK constraint. Setting
    # Current.tenant here mirrors what Commerce7::ExtensionController and
    # Commerce7::WebhooksController already do per-request.
    def purge(tenant)
      commerce7_tenant_id = tenant.commerce7_tenant_id
      Current.tenant = tenant
      tenant.destroy!
      Commerce7.audit!(event_type: "tenant_data_purged", success: true, commerce7_tenant_id: commerce7_tenant_id)
    ensure
      Current.tenant = nil
    end
  end
end
