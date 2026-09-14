Commerce7.configure do |c|
  c.tenant_class_name = "Tenant"

  c.webhook_credentials = -> {
    [
      Rails.application.credentials.dig(:commerce7, :webhook_username),
      Rails.application.credentials.dig(:commerce7, :webhook_password)
    ]
  }
  c.app_credentials = -> {
    [
      Rails.application.credentials.dig(:commerce7, :app_id),
      Rails.application.credentials.dig(:commerce7, :app_secret_key)
    ]
  }

  # Point this at your app's own audit-log write path so Commerce7-driven
  # events (server auth, activation/deactivation, staff extension auth,
  # webhook-driven mutations, the post-uninstall purge) land in the same
  # trail as the rest of the app's. See the README's "Audit trail" section.
  c.audit = ->(**kwargs) { AuditEvent.record!(**kwargs) }
end

# Runs once, after a tenant activates (first install or a reinstall) —
# typically a one-time backfill sync, since Commerce7's Web Hooks only fire
# on future changes.
# Commerce7.on_activate do |tenant, payload|
# end

# Register a handler per (object, action) pair your app cares about — see
# Commerce7::Webhooks for the full contract, including the idempotency
# expectation.
# Commerce7::Webhooks.on("Club Membership", "Create", "Update") do |tenant, payload, actor|
# end
