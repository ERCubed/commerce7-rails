require "rails_helper"

RSpec.describe "Commerce7 deactivations", type: :request do
  let(:auth_headers) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("c7-webhook-user", "c7-webhook-pass") } }

  it "deactivates an existing tenant" do
    tenant = Tenant.create!(commerce7_tenant_id: "winery-1", activated_at: 1.day.ago)

    post commerce7_deactivate_path, params: { tenantId: "winery-1" }, headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(tenant.reload.deactivated_at).to be_present
    expect(AuditEvent.last).to have_attributes(event_type: "tenant_deactivated", success: true, commerce7_tenant_id: "winery-1")
  end

  it "runs the on_deactivate hook" do
    tenant = Tenant.create!(commerce7_tenant_id: "winery-1", activated_at: 1.day.ago)
    received = nil
    Commerce7.on_deactivate { |t| received = t }

    post commerce7_deactivate_path, params: { tenantId: "winery-1" }, headers: auth_headers

    expect(received).to eq(tenant)
  end

  it "is a no-op for an unrecognized tenantId" do
    post commerce7_deactivate_path, params: { tenantId: "unknown-winery" }, headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(Tenant.count).to eq(0)
  end

  it "returns 400 when tenantId is missing" do
    post commerce7_deactivate_path, params: {}, headers: auth_headers

    expect(response).to have_http_status(:bad_request)
  end

  it "returns 401 when the credentials are wrong" do
    tenant = Tenant.create!(commerce7_tenant_id: "winery-1", activated_at: 1.day.ago)
    bad_headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong") }

    post commerce7_deactivate_path, params: { tenantId: "winery-1" }, headers: bad_headers

    expect(response).to have_http_status(:unauthorized)
    expect(tenant.reload.deactivated_at).to be_nil
  end
end
