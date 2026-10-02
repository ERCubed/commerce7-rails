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
    # A path or id that isn't safe to send. A Client::Error, so callers that
    # already rescue those (e.g. around a lookup by an id from a URL) handle a
    # tampered value like any other failed lookup.
    class InvalidRequestError < Error; end

    # Trailing slash matters: Faraday/URI joins a relative path onto this by
    # RFC 3986 merge rules, so without it "v1" gets treated as a filename and
    # dropped (e.g. base ".../v1" + "customer" => ".../customer", not ".../v1/customer").
    BASE_URL = "https://api.commerce7.com/v1/"
    PAGE_SIZE = 50
    MAX_RETRIES = 3
    # A relative API path: segments of letters, digits, - and _, joined by
    # single slashes. Never a full URL (Faraday would send the request, App
    # ID/Secret included, to that host instead), never "." or ".." segments,
    # and no "%", so nothing percent-encoded (e.g. %2e%2e for "..") can be
    # decoded into a different path by the server.
    PATH_FORMAT = %r{\A[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\z}
    # A record id, which becomes one path segment. Commerce7 ids are UUIDs.
    ID_FORMAT = /\A[A-Za-z0-9_-]+\z/

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
      fetch("order", order_id)
    end

    # Generic read access to any Commerce7 list endpoint, with the same
    # pagination and rate-limit handling as the named methods above:
    #
    #   client.each("club-membership") { |membership| ... }
    #   client.each("customer", lastName: "Smith") { |customer| ... }
    #   client.each("some-endpoint", key: "unusualKey") { |record| ... }
    #
    # Records are read from the response key Commerce7 names after the
    # resource: the path's last segment, pluralized and camelCased
    # ("club-membership" => "clubMemberships"). Pass `key:` when an endpoint
    # differs. A response without that key raises ApiError rather than
    # quietly yielding nothing. Filters can be keywords (as above) or a hash;
    # `key` is the one name reserved for this method, so pass a filter that
    # happens to be called "key" in the params hash.
    def each(path, params = {}, key: nil, **filters, &block)
      return enum_for(:each, path, params, key: key, **filters) unless block_given?

      each_record(path, key || response_key_for(path), params.merge(filters), require_key: true, &block)
    end

    # A single record by id from any endpoint: fetch("customer", id) is
    # GET customer/{id}. The id often comes from outside (a URL param, a
    # webhook), so anything but a plain identifier raises InvalidRequestError
    # rather than being sent.
    def fetch(path, id)
      id = id.to_s
      raise InvalidRequestError, "Commerce7 record id must be a plain identifier, got #{id.inspect}" unless id.match?(ID_FORMAT)

      get("#{path}/#{id}")
    end

    # Any GET, for endpoints that don't fit `each`/`fetch`. Returns the parsed
    # response body. Read-only on purpose: this client has no POST/PUT/DELETE.
    def get(path, params = {})
      path = path.to_s # validate and send the same string
      raise InvalidRequestError, "Commerce7 API path must be relative, like \"customer\" or \"order/123\", got #{path.inspect}" unless path.match?(PATH_FORMAT)
      resource = path.split("/").first
      unless Commerce7.configuration.resource_allowed?(resource)
        raise InvalidRequestError, "Commerce7 resource #{resource.inspect} is not in Commerce7.configuration.allowed_resources (#{Commerce7.configuration.allowed_resources.join(', ')})"
      end

      response = with_rate_limit_retry { connection.get(path, params) }
      handle_response(response)
    end

    private

    attr_reader :tenant, :base_url, :sleeper

    def each_record(path, response_key, params = {}, require_key: false)
      page = 1

      loop do
        body = get(path, params.merge(page: page, limit: PAGE_SIZE))
        if require_key && !body.key?(response_key)
          raise ApiError, "Commerce7 response for #{path.inspect} has no #{response_key.inspect} key (keys: #{body.keys.join(', ')}); pass key: to Client#each"
        end

        records = body[response_key] || []
        records.each { |record| yield record }

        break if records.size < PAGE_SIZE

        page += 1
      end
    end

    def response_key_for(path)
      path.split("/").last.tr("-", "_").pluralize.camelize(:lower)
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
