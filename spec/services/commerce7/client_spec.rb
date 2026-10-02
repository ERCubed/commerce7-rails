require "rails_helper"

RSpec.describe Commerce7::Client do
  let(:tenant) { Tenant.create!(commerce7_tenant_id: "winery-1") }
  let(:client) { described_class.new(tenant, sleeper: ->(seconds) { }) }
  let(:json_headers) { { "Content-Type" => "application/json" } }

  describe "#initialize" do
    it "raises when app_credentials returns a blank app id" do
      Commerce7.configuration.app_credentials = -> { [ nil, "secret" ] }

      expect { described_class.new(tenant) }.to raise_error(ArgumentError)
    end

    it "raises when app_credentials returns a blank secret key" do
      Commerce7.configuration.app_credentials = -> { [ "app-id", nil ] }

      expect { described_class.new(tenant) }.to raise_error(ArgumentError)
    end
  end

  describe "#each_customer" do
    include_examples "a Commerce7 paginated resource", method: :each_customer, path: "/customer", response_key: "customers"
  end

  describe "#each_club_membership" do
    include_examples "a Commerce7 paginated resource", method: :each_club_membership, path: "/club-membership", response_key: "clubMemberships"
  end

  describe "#each_order" do
    include_examples "a Commerce7 paginated resource", method: :each_order, path: "/order", response_key: "orders"
  end

  describe "#each_order with filters" do
    it "passes params through as query filters alongside pagination" do
      stub = stub_request(:get, "https://api.commerce7.com/v1/order")
        .with(query: { "orderPaidDate" => "gte:2026-01-01", "page" => "1", "limit" => Commerce7::Client::PAGE_SIZE.to_s })
        .to_return(status: 200, body: { "orders" => [] }.to_json, headers: json_headers)

      client.each_order(orderPaidDate: "gte:2026-01-01") { |record| record }

      expect(stub).to have_been_requested
    end
  end

  describe "#each_product" do
    include_examples "a Commerce7 paginated resource", method: :each_product, path: "/product", response_key: "products"
  end

  describe "#each_inventory_location" do
    include_examples "a Commerce7 paginated resource", method: :each_inventory_location, path: "/inventory-location", response_key: "inventoryLocations"
  end

  describe "#fetch_order" do
    it "returns the order hash" do
      stub_request(:get, "https://api.commerce7.com/v1/order/order-1")
        .to_return(status: 200, body: { "id" => "order-1", "customerId" => "cust-1" }.to_json, headers: json_headers)

      order = client.fetch_order("order-1")

      expect(order["customerId"]).to eq("cust-1")
    end
  end

  describe "#each (generic)" do
    # The response key is inferred from the path: last segment, pluralized, camelCased.
    describe "inferring the response key" do
      include_examples "a Commerce7 paginated resource", method: :each, args: [ "customer" ], path: "/customer", response_key: "customers"
      include_examples "a Commerce7 paginated resource", method: :each, args: [ "club-membership" ], path: "/club-membership", response_key: "clubMemberships"
      include_examples "a Commerce7 paginated resource", method: :each, args: [ "inventory-location" ], path: "/inventory-location", response_key: "inventoryLocations"
    end

    it "passes params through as query filters alongside pagination" do
      stub = stub_request(:get, "https://api.commerce7.com/v1/customer")
        .with(query: { "lastName" => "Smith", "page" => "1", "limit" => Commerce7::Client::PAGE_SIZE.to_s })
        .to_return(status: 200, body: { "customers" => [] }.to_json, headers: json_headers)

      client.each("customer", lastName: "Smith") { |record| record }

      expect(stub).to have_been_requested
    end

    it "also accepts filters as a hash, which is how to pass one named key" do
      stub = stub_request(:get, "https://api.commerce7.com/v1/customer")
        .with(query: hash_including("key" => "k", "lastName" => "Smith", "page" => "1"))
        .to_return(status: 200, body: { "customers" => [] }.to_json, headers: json_headers)

      client.each("customer", { "key" => "k" }, lastName: "Smith") { |record| record }

      expect(stub).to have_been_requested
    end

    it "reads records from an explicit key: when given" do
      stub_request(:get, "https://api.commerce7.com/v1/some-endpoint")
        .with(query: hash_including("page" => "1"))
        .to_return(status: 200, body: { "unusualKey" => [ { "id" => "a" } ] }.to_json, headers: json_headers)

      expect(client.each("some-endpoint", key: "unusualKey").to_a).to eq([ { "id" => "a" } ])
    end

    it "raises ApiError, naming the keys present, when the response lacks the expected key" do
      stub_request(:get, "https://api.commerce7.com/v1/some-endpoint")
        .with(query: hash_including("page" => "1"))
        .to_return(status: 200, body: { "somethingElse" => [], "total" => 0 }.to_json, headers: json_headers)

      expect { client.each("some-endpoint").to_a }
        .to raise_error(Commerce7::Client::ApiError, /"someEndpoints".*somethingElse, total/)
    end
  end

  describe "#fetch" do
    it "GETs path/id and returns the record" do
      stub_request(:get, "https://api.commerce7.com/v1/customer/cust-1")
        .to_return(status: 200, body: { "id" => "cust-1" }.to_json, headers: json_headers)

      expect(client.fetch("customer", "cust-1")).to eq({ "id" => "cust-1" })
    end

    # Ids often come from outside (an orderId URL param, a webhook payload),
    # so only a plain identifier is ever sent.
    [ "../customer", "a/b", "x%2F..", "order?x=1", "id#frag", "a b", "a\nb", "", nil ].each do |id|
      it "rejects the id #{id.inspect} before sending anything" do
        expect { client.fetch("customer", id) }.to raise_error(Commerce7::Client::InvalidRequestError, /plain identifier/)
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end

    it "raises a Client::Error for a tampered id, so callers that rescue those handle it like a failed lookup" do
      expect { client.fetch_order("../customer") }.to raise_error(Commerce7::Client::Error)
    end
  end

  describe "#get" do
    it "returns the parsed body for any relative path, with params" do
      stub_request(:get, "https://api.commerce7.com/v1/customer/cust-1/address")
        .with(query: { "x" => "1" })
        .to_return(status: 200, body: { "addresses" => [] }.to_json, headers: json_headers)

      expect(client.get("customer/cust-1/address", x: 1)).to eq({ "addresses" => [] })
    end

    it "retries on 429 like every other call" do
      stub_request(:get, "https://api.commerce7.com/v1/tag")
        .to_return({ status: 429, headers: { "Retry-After" => "1" } }, { status: 200, body: { "tags" => [] }.to_json, headers: json_headers })

      expect(client.get("tag")).to eq({ "tags" => [] })
    end

    # A full URL would make Faraday send the request, App ID/Secret included,
    # to that host instead of Commerce7. Percent-encoding is refused too, so
    # nothing like %2e%2e ("..") can be decoded into another path server-side.
    HOSTILE_PATHS = [
      "https://evil.example/steal", "http:evil.example", "//evil.example/steal", "///evil.example", "\\\\evil.example\\x",
      "/order", "../order", "order/../customer", "order/../../x", "order/./x", ".", "..", "order/..", "order//x",
      "%2e%2e/v2/x", "order/%2e%2e/%2e%2e/x", "%2F%2Fevil.example", "order%2F..%2F..%2Fx", "%252e%252e/x", "order%00",
      "order%0d%0aX:%20y", "evil.example", "order@evil.example", "user:pass@evil.example", "@evil.example",
      "order:8080", "evil.example:443/x", "order?x=1", "order#x", "order;x", "order\nHost: evil", "order\r\nX: y",
      "order\u0000", "order ", " order", "ｏrder", "order/‮", ""
    ].freeze

    HOSTILE_PATHS.each do |path|
      it "rejects #{path.inspect} before sending anything" do
        expect { client.get(path) }.to raise_error(Commerce7::Client::InvalidRequestError, /must be relative/)
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end

    it "applies the same check to each and fetch" do
      expect { client.each("https://evil.example/x").first }.to raise_error(Commerce7::Client::InvalidRequestError)
      expect { client.fetch("https://evil.example", "x") }.to raise_error(Commerce7::Client::InvalidRequestError)
    end

    it "never lets an accepted path build a URL outside the Commerce7 API base" do
      connection = Faraday.new(url: Commerce7::Client::BASE_URL)
      accepted = [ "customer", "club-membership", "order/abc-123", "customer/cust_1/address", "a" * 500 ]

      accepted.each do |path|
        expect(path).to match(Commerce7::Client::PATH_FORMAT)
        expect(connection.build_url(path).to_s).to start_with("https://api.commerce7.com/v1/")
      end
      HOSTILE_PATHS.each { |path| expect(path).not_to match(Commerce7::Client::PATH_FORMAT) }
    end
  end

  describe "allowed_resources" do
    after { Commerce7.configuration.allowed_resources = nil }

    it "sends requests for a listed resource, including sub-paths" do
      Commerce7.configuration.allowed_resources = %w[customer]
      stub_request(:get, "https://api.commerce7.com/v1/customer/cust-1/address")
        .to_return(status: 200, body: { "addresses" => [] }.to_json, headers: json_headers)

      expect(client.get("customer/cust-1/address")).to eq({ "addresses" => [] })
    end

    it "refuses an unlisted resource before sending anything, through every entry point" do
      Commerce7.configuration.allowed_resources = %w[order]

      expect { client.get("customer") }.to raise_error(Commerce7::Client::InvalidRequestError, /"customer" is not in .*allowed_resources \(order\)/)
      expect { client.each("customer").first }.to raise_error(Commerce7::Client::InvalidRequestError)
      expect { client.fetch("customer", "cust-1") }.to raise_error(Commerce7::Client::InvalidRequestError)
      expect { client.each_customer.first }.to raise_error(Commerce7::Client::InvalidRequestError)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it "is a Client::Error, so a caller that rescues those treats it as a failed call" do
      Commerce7.configuration.allowed_resources = []

      expect { client.fetch_order("order-1") }.to raise_error(Commerce7::Client::Error)
    end
  end

  describe "authentication" do
    it "sends HTTP Basic auth (from app_credentials) and the tenant header" do
      stub = stub_request(:get, "https://api.commerce7.com/v1/customer")
        .with(basic_auth: [ "c7-app-id", "c7-app-secret" ], headers: { "tenant" => "winery-1" }, query: hash_including("page" => "1"))
        .to_return(status: 200, body: { "customers" => [] }.to_json, headers: json_headers)

      client.each_customer { |record| record }

      expect(stub).to have_been_requested
    end

    it "raises AuthenticationError on a 401" do
      stub_request(:get, "https://api.commerce7.com/v1/customer")
        .with(query: hash_including("page" => "1"))
        .to_return(status: 401, body: { "message" => "unauthorized" }.to_json, headers: json_headers)

      expect { client.each_customer { |record| record } }.to raise_error(Commerce7::Client::AuthenticationError)
    end
  end

  describe "rate limiting" do
    it "retries using the Retry-After header and then succeeds" do
      stub_request(:get, "https://api.commerce7.com/v1/customer")
        .with(query: hash_including("page" => "1"))
        .to_return(
          { status: 429, headers: { "Retry-After" => "1" } },
          { status: 200, body: { "customers" => [] }.to_json, headers: json_headers }
        )

      results = []
      client.each_customer { |record| results << record }

      expect(results).to eq([])
    end

    it "falls back to exponential backoff when Retry-After is absent" do
      stub_request(:get, "https://api.commerce7.com/v1/customer")
        .with(query: hash_including("page" => "1"))
        .to_return(
          { status: 429 },
          { status: 200, body: { "customers" => [] }.to_json, headers: json_headers }
        )

      expect { client.each_customer { |record| record } }.not_to raise_error
    end

    it "raises RateLimitedError after exhausting retries" do
      stub_request(:get, "https://api.commerce7.com/v1/customer")
        .with(query: hash_including("page" => "1"))
        .to_return(status: 429)

      expect { client.each_customer { |record| record } }.to raise_error(Commerce7::Client::RateLimitedError)
    end
  end

  describe "other API errors" do
    it "raises ApiError on an unexpected status" do
      stub_request(:get, "https://api.commerce7.com/v1/customer")
        .with(query: hash_including("page" => "1"))
        .to_return(status: 500, body: "boom")

      expect { client.each_customer { |record| record } }.to raise_error(Commerce7::Client::ApiError)
    end
  end
end
