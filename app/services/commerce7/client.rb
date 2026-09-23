# frozen_string_literal: true

module Commerce7
  # HTTP client for Commerce7's REST API. Confirmed against Commerce7's public
  # docs: base URL, Basic Auth (App ID/App Secret Key as user/pass), endpoint
  # paths, page/limit pagination (max 50/page, matches PAGE_SIZE), response
  # envelope keys, and the 100 req/min rate limit.
  #
  # The App ID/App Secret Key pair is a single pair for the app as a whole,
  # not one per tenant (see Commerce7.configuration.app_credentials) — so the
  # `tenant` header is the only thing that scopes a request to a specific
  # winery's data.
  class Client
    class Error < StandardError; end
    class AuthenticationError < Error; end
    class RateLimitedError < Error; end
    class ApiError < Error; end

    # Trailing slash matters: Faraday/URI joins a relative path onto this by
    # RFC 3986 merge rules, so without it "v1" gets treated as a filename and
    # dropped (e.g. base ".../v1" + "customer" => ".../customer", not ".../v1/customer").
    BASE_URL = "https://api.commerce7.com/v1/"
    PAGE_SIZE = 50
    MAX_RETRIES = 3

    def initialize(tenant, base_url: BASE_URL, sleeper: ->(seconds) { sleep(seconds) })
      @app_id, @app_secret_key = Commerce7.configuration.app_credentials.call
      if @app_id.blank? || @app_secret_key.blank?
        raise ArgumentError, "Commerce7.configuration.app_credentials returned a blank app_id/app_secret_key"
      end

      @tenant = tenant
      @base_url = base_url
      @sleeper = sleeper
    end

    def each_customer(&block)
      return enum_for(:each_customer) unless block_given?

      each_record("customer", "customers", &block)
    end

    def each_club_membership(&block)
      return enum_for(:each_club_membership) unless block_given?

      each_record("club-membership", "clubMemberships", &block)
    end

    # `params` pass straight through as Commerce7 query filters (e.g.
    # `orderPaidDate: "gte:2026-01-01"`), so a caller can bound a listing
    # instead of paging through a tenant's entire order history.
    def each_order(params = {}, &block)
      return enum_for(:each_order, params) unless block_given?

      each_record("order", "orders", params, &block)
    end

    # Products carry their variants inline, and each variant carries its
    # per-location inventory counts (variants[].inventory[], keyed by
    # inventoryLocationId) plus the winery's custom fields (metaData) —
    # enough for a full inventory snapshot without a separate call per SKU.
    def each_product(params = {}, &block)
      return enum_for(:each_product, params) unless block_given?

      each_record("product", "products", params, &block)
    end

    def each_inventory_location(params = {}, &block)
      return enum_for(:each_inventory_location, params) unless block_given?

      each_record("inventory-location", "inventoryLocations", params, &block)
    end

    # Single-order lookup (as opposed to each_order's bulk listing) — some
    # App Extension placements (e.g. an Order Detail tab) only get an
    # orderId from Commerce7. Returns the order hash, which carries a
    # top-level customerId same as club-membership's.
    def fetch_order(order_id)
      get("order/#{order_id}", {})
    end

    private

    attr_reader :tenant, :base_url, :sleeper

    def each_record(path, response_key, params = {})
      page = 1

      loop do
        records = get(path, params.merge(page: page, limit: PAGE_SIZE))[response_key] || []
        records.each { |record| yield record }

        break if records.size < PAGE_SIZE

        page += 1
      end
    end

    def get(path, params)
      response = with_rate_limit_retry { connection.get(path, params) }
      handle_response(response)
    end

    def with_rate_limit_retry
      attempt = 0

      loop do
        response = yield
        return response unless response.status == 429

        attempt += 1
        raise RateLimitedError, "Commerce7 rate limit exceeded after #{MAX_RETRIES} retries" if attempt > MAX_RETRIES

        sleeper.call(retry_delay(response, attempt))
      end
    end

    def retry_delay(response, attempt)
      retry_after = response.headers["retry-after"].to_s.to_i
      retry_after.positive? ? retry_after : 2**attempt
    end

    def handle_response(response)
      case response.status
      when 200..299
        response.body
      when 401
        raise AuthenticationError, "Commerce7 rejected the tenant's credentials"
      else
        raise ApiError, "Commerce7 API error (#{response.status}): #{response.body}"
      end
    end

    def connection
      @connection ||= Faraday.new(url: base_url) do |f|
        f.request :authorization, :basic, @app_id, @app_secret_key
        f.headers["tenant"] = tenant.commerce7_tenant_id
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end
  end
end
