# frozen_string_literal: true

module Commerce7
  # Everything a host app wires up once, in config/initializers/commerce7.rb
  # (see Commerce7::Generators::InstallGenerator for a starting template).
  # There's no default tenant/webhook/app credential source deliberately —
  # this gem never assumes Rails encrypted credentials over any other
  # secrets store, so a missing config surfaces as a clear error rather than
  # silently falling back to something the host never configured.
  class Configuration
    # The ActiveRecord class that includes Commerce7::TenantConcern.
    attr_accessor :tenant_class_name

    # -> { [webhook_username, webhook_password] } — HTTP Basic credentials
    # Commerce7 was configured (in its Developer Center) to send on the
    # Install/Uninstall URLs and the app-level Web Hook.
    attr_accessor :webhook_credentials

    # -> { [app_id, app_secret_key] } — the single app-wide Commerce7 API
    # credential pair (not per-tenant) used by Commerce7::Client.
    attr_accessor :app_credentials

    # ->(event_type:, success:, **kwargs) { ... } — called for every
    # security-relevant event this gem's controllers/jobs produce (auth
    # success/failure, activation/deactivation, webhook-driven mutation,
    # purge). Point this at your app's own audit-log write path (e.g.
    # `->(**kw) { AuditEvent.record!(**kw) }`) so Commerce7-driven events
    # land in the same trail as the rest of the app's.
    attr_accessor :audit

    def initialize
      @tenant_class_name = "Tenant"
      @webhook_credentials = -> { raise_unconfigured!(:webhook_credentials) }
      @app_credentials = -> { raise_unconfigured!(:app_credentials) }
      @audit = ->(**) { }
    end

    def tenant_class
      tenant_class_name.constantize
    end

    private

    def raise_unconfigured!(setting)
      raise Commerce7::Error,
        "Commerce7.configuration.#{setting} is not set — configure it in config/initializers/commerce7.rb"
    end
  end
end
