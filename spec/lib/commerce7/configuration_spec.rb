require "rails_helper"

RSpec.describe Commerce7::Configuration do
  subject(:configuration) { described_class.new }

  it "defaults tenant_class_name to \"Tenant\"" do
    expect(configuration.tenant_class_name).to eq("Tenant")
    expect(configuration.tenant_class).to eq(Tenant)
  end

  it "raises a clear error when webhook_credentials was never configured" do
    expect { configuration.webhook_credentials.call }.to raise_error(Commerce7::Error, /webhook_credentials/)
  end

  it "raises a clear error when app_credentials was never configured" do
    expect { configuration.app_credentials.call }.to raise_error(Commerce7::Error, /app_credentials/)
  end

  it "defaults audit to a no-op" do
    expect { configuration.audit.call(event_type: "x", success: true) }.not_to raise_error
  end
end
