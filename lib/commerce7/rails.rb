# frozen_string_literal: true

require "faraday"
require "commerce7/version"
require "commerce7/configuration"
require "commerce7/webhooks"
require "commerce7/engine" if defined?(Rails::Engine)

module Commerce7
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    # Runs after Commerce7::ActivationsController activates (or
    # reactivates) a tenant — typically used to kick off a one-time backfill
    # sync, since Commerce7's Web Hooks only fire on future changes, not a
    # newly (re)installed tenant's pre-existing data.
    def on_activate(&block)
      activate_hooks << block
    end

    # Runs after Commerce7::DeactivationsController soft-deactivates a
    # tenant. Optional — Commerce7::PurgeDeactivatedTenantsJob independently
    # enforces the 30-day post-uninstall deletion requirement regardless of
    # whether a host registers this hook.
    def on_deactivate(&block)
      deactivate_hooks << block
    end

    def run_activate_hooks(tenant, payload)
      activate_hooks.each { |hook| hook.call(tenant, payload) }
    end

    def run_deactivate_hooks(tenant)
      deactivate_hooks.each { |hook| hook.call(tenant) }
    end

    # Auditing must never be why the thing it's observing fails — a bad
    # configured audit hook shouldn't 500 a webhook delivery or a staff
    # member's page load. Logged loudly on failure so a real bug in the
    # host's audit hook still surfaces instead of vanishing.
    def audit!(**kwargs)
      configuration.audit.call(**kwargs)
    rescue StandardError => e
      Rails.logger.error("Commerce7.audit! hook raised: #{e.class}: #{e.message}") if defined?(Rails)
    end

    # Test helper: resets configuration, lifecycle hooks, and webhook
    # registrations. Call from a spec suite's global before/after hook so
    # one example's Commerce7.configure doesn't leak into the next.
    def reset!
      @configuration = nil
      @activate_hooks = []
      @deactivate_hooks = []
      Commerce7::Webhooks.reset!
    end

    private

    def activate_hooks
      @activate_hooks ||= []
    end

    def deactivate_hooks
      @deactivate_hooks ||= []
    end
  end
end
