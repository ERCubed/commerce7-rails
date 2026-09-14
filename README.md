# commerce7-rails

Rails building blocks for building a [Commerce7](https://www.commerce7.com/) App Store integration: activation/deactivation lifecycle, App Extension staff-JWT auth, safe webhook dispatch, the Commerce7 REST client, and the post-uninstall data purge Commerce7's App Store security review requires.

This gem owns the Commerce7-protocol plumbing. Your app owns the business logic: your tenant model's own fields, what a webhook handler actually does, what your App Extension pages render.

## Install

```ruby
# Gemfile
gem "commerce7-rails", github: "ERCubed/commerce7-rails", tag: "v0.1.0"
```

```
bundle install
bin/rails generate commerce7:install
bin/rails db:migrate
```

The generator creates `db/migrate/*_create_tenants.rb` (skip/adapt it if your app already has a `tenants` table) and `config/initializers/commerce7.rb`.

## Configure

```ruby
# config/initializers/commerce7.rb
Commerce7.configure do |c|
  c.tenant_class_name = "Tenant"

  # -> { [username, password] } — the Basic Auth pair you configured in
  # Commerce7's Developer Center for the Install/Uninstall URLs and the
  # app-level Web Hook.
  c.webhook_credentials = -> { Rails.application.credentials.dig(:commerce7, :webhook_username, :webhook_password) }

  # -> { [app_id, app_secret_key] } — the single app-wide Commerce7 API
  # credential pair (not per-tenant).
  c.app_credentials = -> { Rails.application.credentials.dig(:commerce7, :app_id, :app_secret_key) }

  # ->(event_type:, success:, **kwargs) { ... } — point this at your own
  # audit-log write path so Commerce7-driven events land in the same trail
  # as the rest of your app's.
  c.audit = ->(**kwargs) { AuditEvent.record!(**kwargs) }
end
```

Your tenant model includes the lifecycle concern and, since Commerce7's activation POST carries the installing staff member's name/email, encrypts it:

```ruby
class Tenant < ApplicationRecord
  include Commerce7::TenantConcern
  encrypts :raw_activation_payload
end
```

Your app also needs a top-level `Current`, the standard Rails per-request-state convention — `Commerce7::ExtensionController` and `Commerce7::PurgeDeactivatedTenantsJob` both use it:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :tenant, :staff_user
end
```

## Routes

This gem mounts nothing — you declare routes exactly as you would for any in-app controller, just pointing at the gem's classes, so the URLs already registered in Commerce7's Developer Center (Install/Uninstall URLs, an App Extension's iframe src) stay stable and under your control:

```ruby
namespace :commerce7 do
  post "activate", to: "activations#create", as: :activate
  post "deactivate", to: "deactivations#create", as: :deactivate
  post "webhooks", to: "webhooks#create", as: :webhooks

  # Your own App Extension pages, subclassing Commerce7::ExtensionController:
  get "dashboard", to: "dashboard#show", as: :dashboard
end
```

## Webhook dispatch

`Commerce7::WebhooksController` handles the parsing, Basic Auth, tenant lookup, and audit write. You register what your app actually does for each `(object, action)` pair Commerce7 might send — anything unregistered is a silent no-op, matching Commerce7's own retry-tolerant expectations:

```ruby
Commerce7::Webhooks.on("Club Membership", "Create", "Update") do |tenant, payload, actor|
  SyncJob.perform_later(tenant)
end

Commerce7::Webhooks.on("Customer", "Delete") do |tenant, payload, actor|
  Current.tenant = tenant
  ClubMember.find_by(commerce7_customer_id: payload["customerId"])&.destroy
  Current.tenant = nil
end
```

Handlers must be **idempotent by construction** (upsert / find-and-destroy) — Commerce7 doesn't expose a delivery/event id to dedupe a redelivery against.

## Activation/deactivation hooks

```ruby
# Runs once, after a tenant activates (first install or reinstall) — typically
# a one-time backfill sync, since Web Hooks only fire on future changes.
Commerce7.on_activate do |tenant, payload|
  SyncJob.perform_later(tenant)
end

Commerce7.on_deactivate do |tenant|
  # optional
end
```

## The 30-day post-uninstall purge

Commerce7's security review requires customer data deleted within 30 days of app termination. `Commerce7::TenantConcern` soft-deactivates on uninstall (never hard-deletes, so a reinstall within the window keeps the tenant's data) and exposes a `pending_deletion` scope; `Commerce7::PurgeDeactivatedTenantsJob` hard-deletes anything past that window. Schedule it as a recurring job:

```yaml
# config/recurring.yml (Solid Queue)
production:
  commerce7_purge_deactivated_tenants:
    class: Commerce7::PurgeDeactivatedTenantsJob
    queue: default
    schedule: every day at 3am
```

## The REST client

```ruby
client = Commerce7::Client.new(tenant)
client.each_club_membership { |membership| ... }  # paginates automatically
client.each_customer { |customer| ... }
client.each_order { |order| ... }
client.fetch_order(order_id)
```

Handles pagination, the 100 req/min rate limit (retries on 429 using `Retry-After` when present, exponential backoff otherwise), and raises `Commerce7::Client::AuthenticationError` / `RateLimitedError` / `ApiError` as appropriate.

`Commerce7::AccountClient` validates the staff JWT Commerce7 passes into an App Extension iframe — used internally by `Commerce7::ExtensionController`, but available directly if you need it.

## Security posture

This gem exists so every app built on it starts from a "Yes" on Commerce7's App Store security questionnaire, not a retrofit:

- **Server-to-server auth**: `Commerce7::BaseController` requires HTTP Basic Auth (your `webhook_credentials`) on every activation/deactivation/webhook POST, and audits both successful and failed attempts.
- **App Extension auth**: `Commerce7::ExtensionController` validates the staff JWT Commerce7 passes into every iframe load against Commerce7's own `/account/user` endpoint — a real error page on failure, never a bare status code.
- **PII**: `raw_activation_payload` (the installing staff member's name/email) is your model's column to encrypt — see Install above.
- **Data deletion**: built in — soft-deactivate on uninstall, hard-delete after 30 days (`Commerce7::PurgeDeactivatedTenantsJob`).
- **Webhook auth + idempotency**: Basic Auth on every delivery; handlers are expected to be idempotent by construction, since Commerce7 exposes no delivery id to dedupe against.
- **Audit trail**: every security-relevant event (server auth success/failure, activation/deactivation, staff extension auth, webhook-driven dispatch, the post-uninstall purge) flows through your configured `audit` hook — user identity, event type, timestamp, success/failure, and origin.

## Development

```
bundle install
bundle exec rspec
bundle exec rubocop
bundle exec brakeman
bundle exec bundler-audit --update
```

Tests run against a minimal dummy Rails app (via [combustion](https://github.com/pat/combustion)) at `spec/dummy`.
