# frozen_string_literal: true

module Commerce7
  # Registry for Commerce7::WebhooksController to dispatch into. Commerce7's
  # Web Hooks feature (registered once, app-wide, in the Developer Center's
  # "APIs & Webhooks" step) delivers a body of {object, action, payload,
  # user, tenantId} covering far more object/action pairs than any one app
  # acts on — object/action this app doesn't register a handler for are a
  # silent no-op, not an error, matching Commerce7's own retry-tolerant
  # expectations.
  #
  # Register handlers from a host app initializer:
  #
  #   Commerce7::Webhooks.on("Club Membership", "Create", "Update") do |tenant, payload, actor|
  #     SyncJob.perform_later(tenant)
  #   end
  #
  # A handler block receives the tenant (an instance of the configured
  # tenant class), the raw payload hash, and the actor string Commerce7
  # attached to the delivery (its "user" field, if any). Handlers are
  # expected to be idempotent by construction (upsert / find-and-destroy) —
  # Commerce7 doesn't expose a delivery/event id to dedupe against, so a
  # redelivered webhook must land at the same end state, not double-apply.
  module Webhooks
    Handler = Struct.new(:object, :actions, :block)
    private_constant :Handler

    class << self
      def on(object, *actions, &block)
        handlers << Handler.new(object, actions, block)
      end

      # Runs every handler registered for this (object, action) pair.
      # Returns true if at least one handler ran, so the caller knows
      # whether this was a recognized event worth auditing.
      def dispatch(object:, action:, tenant:, payload:, actor:)
        matched = handlers.select { |handler| handler.object == object && handler.actions.include?(action) }
        matched.each { |handler| handler.block.call(tenant, payload, actor) }
        matched.any?
      end

      # Test helper: clears registrations between specs so one example's
      # Commerce7::Webhooks.on doesn't leak into the next.
      def reset!
        @handlers = []
      end

      private

      def handlers
        @handlers ||= []
      end
    end
  end
end
