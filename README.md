# commerce7-rails

Rails building blocks for building a [Commerce7](https://www.commerce7.com/) App Store integration: activation/deactivation lifecycle, App Extension staff-JWT auth, safe webhook dispatch, the Commerce7 REST client, and the post-uninstall data purge Commerce7's App Store security review requires.

This gem owns the Commerce7-protocol plumbing. Your app owns the business logic: your tenant model's own fields, what a webhook handler actually does, what your App Extension pages render.

## Requirements

- Rails 8.1.4 or later
- Faraday 2.14.4 or later

Both floors date from v0.3.0. Earlier versions allowed Rails 7.1+ and any Faraday 2.x.

**Why:** `json` 3.0 changed the signature of `JSON.parse`, and older Rails and Faraday releases call it in ways it no longer accepts. Nothing in your app has to request `json` 3 for this to happen. It arrives as a transitive dependency (rubocop 1.91 pulls it in, for one), and neither Rails nor Faraday caps `json` below 3, so Bundler will happily resolve a combination that breaks at runtime. The floors rule those combinations out.

- **Faraday 2.14.3 and earlier:** the JSON response middleware breaks, so every Commerce7 REST client response raises `Faraday::ParsingError: wrong number of arguments (given 2, expected 1)`.
- **Rails before 8.1.4:** `ActiveSupport::JSON.decode` breaks, so every `json`/`jsonb` column read raises. That includes the `raw_activation_payload` column the install generator creates. How it fails depends on the Rails line:

  | Rails | With `json` 3 |
  |---|---|
  | 7.1.x, 8.0.x | `ArgumentError: unknown keyword: quirks_mode` |
  | 7.2.x | JSON decoding works |
  | 8.1.0 to 8.1.3.x | `ArgumentError: wrong number of arguments (given 2, expected 1)` |
  | 8.1.4 and later | Works |

  A gemspec can't say "7.2.x or 8.1.4 and later", so the floor is 8.1.4.

If you're stuck on an older Rails, stay on v0.2.1 and pin `json` below 3 in your app's Gemfile (`gem "json", "~> 2.21"`).

## Install

```ruby
# Gemfile
gem "commerce7-rails", github: "ERCubed/commerce7-rails", tag: "v0.3.0"
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
  c.webhook_credentials = -> {
    [
      Rails.application.credentials.dig(:commerce7, :webhook_username),
      Rails.application.credentials.dig(:commerce7, :webhook_password)
    ]
  }

  # -> { [app_id, app_secret_key] } — the single app-wide Commerce7 API
  # credential pair (not per-tenant).
  c.app_credentials = -> {
    [
      Rails.application.credentials.dig(:commerce7, :app_id),
      Rails.application.credentials.dig(:commerce7, :app_secret_key)
    ]
  }

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
client.each_order(orderPaidDate: "gte:2026-01-01") { |order| ... }  # params pass through as filters
client.each_product { |product| ... }              # variants + per-location inventory inline
client.each_inventory_location { |location| ... }
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
