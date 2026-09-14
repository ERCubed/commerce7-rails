require "rails_helper"

RSpec.describe "Commerce7 activations", type: :request do
  let(:auth_headers) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("c7-webhook-user", "c7-webhook-pass") } }

  it "creates a new tenant from the activation payload" do
    post commerce7_activate_path,
      params: { tenantId: "winery-1", firstName: "Jane", lastName: "Doe", email: "jane@example.com" },
      headers: auth_headers

    expect(response).to have_http_status(:ok)

    tenant = Tenant.find_by(commerce7_tenant_id: "winery-1")
    expect(tenant).to be_present
    expect(tenant.activated_at).to be_present
    expect(tenant.deactivated_at).to be_nil
    expect(tenant.raw_activation_payload["email"]).to eq("jane@example.com")
    expect(AuditEvent.last).to have_attributes(event_type: "tenant_activated", success: true, commerce7_tenant_id: "winery-1")
  end

  it "runs the on_activate hook with the tenant and payload" do
    received = nil
    Commerce7.on_activate { |tenant, payload| received = [ tenant, payload ] }

    post commerce7_activate_path, params: { tenantId: "winery-1", firstName: "Jane" }, headers: auth_headers

    expect(received[0]).to eq(Tenant.find_by(commerce7_tenant_id: "winery-1"))
    expect(received[1]["firstName"]).to eq("Jane")
  end

  it "reactivates an existing tenant and clears deactivated_at" do
    tenant = Tenant.create!(commerce7_tenant_id: "winery-1", deactivated_at: 1.day.ago)

    post commerce7_activate_path, params: { tenantId: "winery-1" }, headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(Tenant.count).to eq(1)
    expect(tenant.reload.deactivated_at).to be_nil
  end

  it "returns 400 when tenantId is missing" do
    post commerce7_activate_path, params: {}, headers: auth_headers

    expect(response).to have_http_status(:bad_request)
  end

  it "returns 401 when the credentials are wrong" do
    bad_headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong") }

    post commerce7_activate_path, params: { tenantId: "winery-1" }, headers: bad_headers

    expect(response).to have_http_status(:unauthorized)
    expect(Tenant.find_by(commerce7_tenant_id: "winery-1")).to be_nil
  end

  it "records an AuditEvent for a failed authentication attempt" do
    bad_headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong") }

    post commerce7_activate_path, params: { tenantId: "winery-1" }, headers: bad_headers

    event = AuditEvent.last
    expect(event.event_type).to eq("commerce7_server_auth")
    expect(event.success).to be false
    expect(event.commerce7_tenant_id).to eq("winery-1")
  end

  it "returns 401 when no webhook credentials are configured" do
    Commerce7.configuration.webhook_credentials = -> { [ nil, nil ] }

    post commerce7_activate_path, params: { tenantId: "winery-1" }, headers: auth_headers

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 when no Authorization header is sent at all" do
    post commerce7_activate_path, params: { tenantId: "winery-1" }

    expect(response).to have_http_status(:unauthorized)
  end
end
