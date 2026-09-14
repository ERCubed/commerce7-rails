# frozen_string_literal: true

module Commerce7
  # Validates the staff JWT Commerce7 passes into an App Extension iframe
  # (the `account` URL param) via GET /account/user. Confirmed against
  # Commerce7's docs: Authorization header carries the raw token (no
  # "Bearer" prefix), `tenant` header carries the tenantId URL param.
  #
  # Distinct from Commerce7::Client: that one authenticates as the app
  # (Basic Auth with App ID/Secret Key) for server-to-server calls; this
  # authenticates as the staff member currently viewing the iframe, and
  # needs no app credentials of its own.
  class AccountClient
    class Error < StandardError; end
    class AuthenticationError < Error; end
    class ApiError < Error; end

    BASE_URL = Commerce7::Client::BASE_URL

    def initialize(base_url: BASE_URL)
      @base_url = base_url
    end

    def fetch_user(tenant_id:, token:)
      response = connection.get("account/user") do |req|
        req.headers["Authorization"] = token
        req.headers["tenant"] = tenant_id
      end

      handle_response(response)
    end

    private

    attr_reader :base_url

    def handle_response(response)
      case response.status
      when 200..299
        response.body
      when 401
        raise AuthenticationError, "Commerce7 rejected the staff token"
      else
        raise ApiError, "Commerce7 API error (#{response.status}): #{response.body}"
      end
    end

    def connection
      @connection ||= Faraday.new(url: base_url) do |f|
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end
  end
end
