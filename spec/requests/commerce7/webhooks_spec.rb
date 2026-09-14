require "rails_helper"

RSpec.describe "Commerce7 webhooks", type: :request do
  let!(:tenant) { Tenant.create!(commerce7_tenant_id: "winery-1") }
  let(:auth_headers) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("c7-webhook-user", "c7-webhook-pass") } }

  def post_webhook(object:, action:, payload: {}, tenant_id: "winery-1", user: "staff@example.com")
    post commerce7_webhooks_path,
      params: { tenantId: tenant_id, object: object, action: action, payload: payload, user: user },
      headers: auth_headers,
      as: :json
  end

  it "returns 401 when the credentials are wrong" do
    post commerce7_webhooks_path,
      params: { tenantId: "winery-1", object: "Customer", action: "Delete", payload: { customerId: "cust-1" } },
      headers: { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong") },
      as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(AuditEvent.last).to have_attributes(event_type: "commerce7_server_auth", success: false, commerce7_tenant_id: "winery-1")
  end

  it "returns 400 when a required top-level field is missing" do
    post commerce7_webhooks_path, params: { tenantId: "winery-1", object: "Customer" }, headers: auth_headers, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "returns 400 for a malformed JSON body" do
    post commerce7_webhooks_path, params: "not json", headers: auth_headers.merge("CONTENT_TYPE" => "application/json")

    expect(response).to have_http_status(:bad_request)
  end

  it "acks and no-ops for an unknown tenant, without dispatching to any handler" do
    Commerce7::Webhooks.on("Customer", "Delete") { |*| raise "should not run" }

    post_webhook(object: "Customer", action: "Delete", payload: { customerId: "cust-1" }, tenant_id: "unknown-winery")

    expect(response).to have_http_status(:ok)
  end

  it "acks and no-ops for an object/action combo with no registered handler" do
    post_webhook(object: "Order", action: "Create", payload: { id: "order-1" })

    expect(response).to have_http_status(:ok)
    expect(AuditEvent.count).to eq(0)
  end

  it "dispatches to a registered handler with the tenant, payload, and actor" do
    received = nil
    Commerce7::Webhooks.on("Club Membership", "Create", "Update") { |t, payload, actor| received = [ t, payload, actor ] }

    post_webhook(object: "Club Membership", action: "Update", payload: { customerId: "cust-1" }, user: "jason@example.com")

    expect(response).to have_http_status(:ok)
    expect(received[0]).to eq(tenant)
    expect(received[1]["customerId"]).to eq("cust-1")
    expect(received[2]).to eq("jason@example.com")
    expect(AuditEvent.last).to have_attributes(
      event_type: "webhook_club_membership_update",
      success: true,
      actor: "jason@example.com",
      commerce7_tenant_id: "winery-1"
    )
  end

  it "does not audit an object/action pair only partially registered (Create but not Delete)" do
    Commerce7::Webhooks.on("Club Membership", "Create") { |*| }

    post_webhook(object: "Club Membership", action: "Delete", payload: { customerId: "cust-1" })

    expect(response).to have_http_status(:ok)
    expect(AuditEvent.count).to eq(0)
  end

  it "is idempotent by construction — a repeated delivery just re-runs the same handler" do
    Current.tenant = tenant
    Note.create!(tenant: tenant, body: "cust-1")
    Current.tenant = nil

    Commerce7::Webhooks.on("Club Membership", "Delete") do |t, payload, _actor|
      Current.tenant = t
      Note.find_by(body: payload["customerId"])&.destroy
      Current.tenant = nil
    end

    post_webhook(object: "Club Membership", action: "Delete", payload: { customerId: "cust-1" })
    post_webhook(object: "Club Membership", action: "Delete", payload: { customerId: "cust-1" })

    expect(response).to have_http_status(:ok)
  end
end
