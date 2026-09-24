require "rails_helper"

RSpec.describe Commerce7::ExtensionController, type: :controller do
  render_views

  controller do
    def index
      render plain: "tenant=#{Current.tenant&.commerce7_tenant_id} staff=#{Current.staff_user && Current.staff_user['firstName']}"
    end
  end

  before do
    routes.draw { get "index" => "commerce7/extension#index" }
  end

  let!(:tenant) { Tenant.create!(commerce7_tenant_id: "winery-1", activated_at: 1.day.ago) }
  let(:user_payload) { { "id" => "staff-1", "firstName" => "Jason", "lastName" => "Andres", "email" => "jason@example.com", "role" => "Admin Owner" } }
  let(:json_headers) { { "Content-Type" => "application/json" } }

  it "resolves Current.tenant and Current.staff_user on valid auth" do
    stub_request(:get, "https://api.commerce7.com/v1/account/user")
      .with(headers: { "Authorization" => "jwt-token", "tenant" => "winery-1" })
      .to_return(status: 200, body: user_payload.to_json, headers: json_headers)

    get :index, params: { tenantId: "winery-1", account: "jwt-token" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("tenant=winery-1 staff=Jason")
    expect(AuditEvent.last).to have_attributes(event_type: "staff_extension_auth", success: true, actor: "jason@example.com", commerce7_tenant_id: "winery-1")
  end

  # The error pages matter most here: they're what staff see inside the
  # Commerce7 iframe when auth fails, and a before_action that renders halts
  # the chain before any after_action could strip the header.
  describe "framing on error pages" do
    it "lets Commerce7 frame the unknown-tenant page" do
      get :index, params: { tenantId: "unknown-winery", account: "jwt-token" }

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["X-Frame-Options"]).to be_nil
    end

    it "lets Commerce7 frame the rejected-token page" do
      stub_request(:get, "https://api.commerce7.com/v1/account/user")
        .to_return(status: 401, body: { "statusCode" => 401 }.to_json, headers: json_headers)

      get :index, params: { tenantId: "winery-1", account: "bad-token" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["X-Frame-Options"]).to be_nil
    end

    it "lets Commerce7 frame the missing-params response" do
      get :index, params: { tenantId: "winery-1" }

      expect(response).to have_http_status(:bad_request)
      expect(response.headers["X-Frame-Options"]).to be_nil
    end
  end

  it "drops the default X-Frame-Options so Commerce7 can embed the page" do
    stub_request(:get, "https://api.commerce7.com/v1/account/user")
      .to_return(status: 200, body: user_payload.to_json, headers: json_headers)

    get :index, params: { tenantId: "winery-1", account: "jwt-token" }

    expect(response.headers["X-Frame-Options"]).to be_nil
  end

  it "returns 403 when the tenant is unknown" do
    get :index, params: { tenantId: "unknown-winery", account: "jwt-token" }

    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("Unauthorized")
    expect(AuditEvent.last).to have_attributes(event_type: "staff_extension_auth", success: false, commerce7_tenant_id: "unknown-winery")
  end

  it "returns 403 when the tenant is deactivated" do
    tenant.update!(deactivated_at: Time.current)

    get :index, params: { tenantId: "winery-1", account: "jwt-token" }

    expect(response).to have_http_status(:forbidden)
  end

  it "renders a real error page (not a bare 401) when Commerce7 rejects the staff token" do
    stub_request(:get, "https://api.commerce7.com/v1/account/user")
      .to_return(status: 401, body: { "statusCode" => 401, "type" => "unauthorized" }.to_json, headers: json_headers)

    get :index, params: { tenantId: "winery-1", account: "bad-token" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).to include("Unauthorized")
    expect(AuditEvent.last).to have_attributes(event_type: "staff_extension_auth", success: false, commerce7_tenant_id: "winery-1")
  end

  it "returns 400 when tenantId is missing" do
    get :index, params: { account: "jwt-token" }

    expect(response).to have_http_status(:bad_request)
  end

  it "returns 400 when the account token is missing" do
    get :index, params: { tenantId: "winery-1" }

    expect(response).to have_http_status(:bad_request)
  end
end
