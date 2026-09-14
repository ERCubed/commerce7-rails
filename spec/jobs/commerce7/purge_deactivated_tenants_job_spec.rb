require "rails_helper"

RSpec.describe Commerce7::PurgeDeactivatedTenantsJob do
  after { Current.tenant = nil }

  def create_tenant_with_data(commerce7_tenant_id:, deactivated_at: nil)
    tenant = Tenant.create!(commerce7_tenant_id: commerce7_tenant_id, deactivated_at: deactivated_at)
    Current.tenant = tenant
    Note.create!(tenant: tenant, body: "note")
    Current.tenant = nil
    tenant
  end

  it "deletes a tenant deactivated more than 30 days ago, along with its dependent data" do
    tenant = create_tenant_with_data(commerce7_tenant_id: "winery-old", deactivated_at: 31.days.ago)

    described_class.perform_now

    expect(Tenant.exists?(tenant.id)).to be false
    expect(Note.unscoped.where(tenant_id: tenant.id)).to be_empty
    expect(AuditEvent.last).to have_attributes(event_type: "tenant_data_purged", success: true, commerce7_tenant_id: "winery-old")
  end

  it "leaves an active tenant and its data alone" do
    tenant = create_tenant_with_data(commerce7_tenant_id: "winery-active")

    described_class.perform_now

    expect(Tenant.exists?(tenant.id)).to be true
    expect(Note.unscoped.where(tenant_id: tenant.id)).not_to be_empty
  end

  it "leaves a tenant deactivated less than 30 days ago alone, so a reinstall within the window keeps its data" do
    tenant = create_tenant_with_data(commerce7_tenant_id: "winery-recent", deactivated_at: 10.days.ago)

    described_class.perform_now

    expect(Tenant.exists?(tenant.id)).to be true
    expect(Note.unscoped.where(tenant_id: tenant.id)).not_to be_empty
  end
end
