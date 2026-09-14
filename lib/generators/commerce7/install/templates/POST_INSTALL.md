
==============================================================================

commerce7-rails installed. Next steps:

  1. Run the generated migration: bin/rails db:migrate
  2. Add `include Commerce7::TenantConcern` and
     `encrypts :raw_activation_payload` to your Tenant model.
  3. Fill in config/initializers/commerce7.rb — credentials sources, your
     audit hook, and any on_activate/webhook handlers.
  4. Add routes (see the README's "Routes" section) pointing at
     commerce7/activations, commerce7/deactivations, commerce7/webhooks,
     and any Commerce7::ExtensionController subclasses you write.
  5. Schedule Commerce7::PurgeDeactivatedTenantsJob as a recurring job —
     required for Commerce7's 30-day post-uninstall deletion policy.

==============================================================================
