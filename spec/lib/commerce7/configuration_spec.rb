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
  describe "allowed_resources" do
    it "defaults to nil, which allows every resource" do
      expect(configuration.allowed_resources).to be_nil
      expect(configuration.resource_allowed?("anything")).to be true
    end

    it "allows only the listed resources once set" do
      configuration.allowed_resources = %w[order club-membership]

      expect(configuration.resource_allowed?("order")).to be true
      expect(configuration.resource_allowed?("club-membership")).to be true
      expect(configuration.resource_allowed?("customer")).to be false
    end

    it "allows nothing when set to an empty list" do
      configuration.allowed_resources = []

      expect(configuration.resource_allowed?("order")).to be false
    end

    it "accepts symbols and a single name, and freezes the list" do
      configuration.allowed_resources = :order

      expect(configuration.allowed_resources).to eq([ "order" ])
      expect(configuration.allowed_resources).to be_frozen
    end

    [ "order/123", "", "https://evil.example", "../order", "order " ].each do |entry|
      it "rejects #{entry.inspect}, so a typo fails at boot rather than on the first request" do
        expect { configuration.allowed_resources = [ entry ] }.to raise_error(ArgumentError, /bare resource names/)
      end
    end
  end
end
