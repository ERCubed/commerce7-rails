require "rails_helper"

RSpec.describe Commerce7::TenantConcern do
  describe ".activate!" do
    it "creates a new tenant on first install" do
      tenant = Tenant.activate!(commerce7_tenant_id: "winery-1", payload: { "email" => "jane@example.com" })

      expect(tenant).to be_persisted
      expect(tenant.activated_at).to be_present
      expect(tenant.deactivated_at).to be_nil
      expect(tenant.raw_activation_payload["email"]).to eq("jane@example.com")
    end

    it "reactivates and clears deactivated_at on a reinstall, without creating a duplicate" do
      existing = Tenant.create!(commerce7_tenant_id: "winery-1", deactivated_at: 1.day.ago)

      tenant = Tenant.activate!(commerce7_tenant_id: "winery-1", payload: {})

      expect(tenant.id).to eq(existing.id)
      expect(Tenant.count).to eq(1)
      expect(tenant.deactivated_at).to be_nil
    end
  end

  describe "#deactivate!" do
    it "sets deactivated_at without destroying the record" do
      tenant = Tenant.create!(commerce7_tenant_id: "winery-1", activated_at: 1.day.ago)

      tenant.deactivate!

      expect(tenant.deactivated_at).to be_present
      expect(Tenant.exists?(tenant.id)).to be true
    end
  end

  describe "#active?" do
    it "is true when deactivated_at is nil" do
      expect(Tenant.new(deactivated_at: nil)).to be_active
    end

    it "is false once deactivated_at is set" do
      expect(Tenant.new(deactivated_at: Time.current)).not_to be_active
    end
  end

  describe "scopes" do
    it ".active excludes deactivated tenants" do
      active = Tenant.create!(commerce7_tenant_id: "winery-active")
      Tenant.create!(commerce7_tenant_id: "winery-inactive", deactivated_at: 1.day.ago)

      expect(Tenant.active).to contain_exactly(active)
    end

    it ".pending_deletion only includes tenants past the retention window" do
      recent = Tenant.create!(commerce7_tenant_id: "winery-recent", deactivated_at: 10.days.ago)
      old = Tenant.create!(commerce7_tenant_id: "winery-old", deactivated_at: 31.days.ago)
      Tenant.create!(commerce7_tenant_id: "winery-active")

      expect(Tenant.pending_deletion).to contain_exactly(old)
      expect(Tenant.pending_deletion).not_to include(recent)
    end
  end

  it "validates commerce7_tenant_id presence and uniqueness" do
    Tenant.create!(commerce7_tenant_id: "winery-1")

    expect(Tenant.new(commerce7_tenant_id: "winery-1")).not_to be_valid
    expect(Tenant.new(commerce7_tenant_id: nil)).not_to be_valid
  end
end
