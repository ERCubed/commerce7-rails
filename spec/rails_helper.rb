# frozen_string_literal: true

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

require "combustion"
Combustion.path = "spec/dummy"
Combustion.initialize! :active_record, :action_controller, :active_job

require "rspec/rails"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!

  # Every example gets a known-good configuration by default (fake but
  # well-formed credentials, and an audit hook wired to the dummy app's
  # AuditEvent model, mirroring how a real host app wires it) so specs only
  # need to override what they're actually testing.
  config.before do
    Commerce7.reset!
    Commerce7.configure do |c|
      c.tenant_class_name = "Tenant"
      c.webhook_credentials = -> { [ "c7-webhook-user", "c7-webhook-pass" ] }
      c.app_credentials = -> { [ "c7-app-id", "c7-app-secret" ] }
      c.audit = ->(**kwargs) { AuditEvent.record!(**kwargs) }
    end
  end
end
