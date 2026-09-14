require "rails_helper"

RSpec.describe Commerce7::AccountClient do
  let(:client) { described_class.new }
  let(:json_headers) { { "Content-Type" => "application/json" } }

  describe "#fetch_user" do
    it "returns the parsed user on success" do
      stub_request(:get, "https://api.commerce7.com/v1/account/user")
        .with(headers: { "Authorization" => "jwt-token", "tenant" => "winery-1" })
        .to_return(
          status: 200,
          body: { "id" => "staff-1", "firstName" => "Jason", "lastName" => "Andres", "email" => "jason@example.com", "role" => "Admin Owner" }.to_json,
          headers: json_headers
        )

      user = client.fetch_user(tenant_id: "winery-1", token: "jwt-token")

      expect(user["firstName"]).to eq("Jason")
      expect(user["role"]).to eq("Admin Owner")
    end

    it "raises AuthenticationError on a 401" do
      stub_request(:get, "https://api.commerce7.com/v1/account/user")
        .to_return(status: 401, body: { "statusCode" => 401, "type" => "unauthorized" }.to_json, headers: json_headers)

      expect { client.fetch_user(tenant_id: "winery-1", token: "bad-token") }.to raise_error(Commerce7::AccountClient::AuthenticationError)
    end

    it "raises ApiError on an unexpected status" do
      stub_request(:get, "https://api.commerce7.com/v1/account/user")
        .to_return(status: 500, body: "boom")

      expect { client.fetch_user(tenant_id: "winery-1", token: "jwt-token") }.to raise_error(Commerce7::AccountClient::ApiError)
    end
  end
end
