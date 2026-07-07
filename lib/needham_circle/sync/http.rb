# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module NeedhamCircle
  module Sync
    # Shared HTTP fetch helpers for the syncers — one home for the SSL/timeout/
    # User-Agent setup and the status/transport/JSON error handling. Everything
    # returns nil (and logs) on failure, so a broken feed degrades gracefully
    # rather than raising.
    module HTTP
      class << self
        # GET url and return the response body, or nil on a non-2xx status or a
        # transport error (both logged).
        #: (String url, ?Hash[String, String] headers, ?logger: Logger?) -> String?
        def get(url, headers = {}, logger: nil)
          uri = URI(url)
          perform(uri, Net::HTTP::Get.new(uri.request_uri), headers, logger)&.body
        end

        # GET url and parse the body as JSON, or nil on request failure or
        # malformed JSON (logged).
        #: (String url, ?Hash[String, String] headers, ?logger: Logger?) -> untyped
        def get_json(url, headers = {}, logger: nil)
          uri = URI(url)
          parse_json(perform(uri, Net::HTTP::Get.new(uri.request_uri), headers, logger), url, logger)
        end

        # POST a JSON body to url and parse the JSON response, or nil on failure.
        #: (String url, String body, ?Hash[String, String] headers, ?logger: Logger?) -> untyped
        def post_json(url, body, headers = {}, logger: nil)
          uri = URI(url)
          request = Net::HTTP::Post.new(uri.request_uri)
          request.body = body
          request["Content-Type"] = "application/json"
          parse_json(perform(uri, request, headers, logger), url, logger)
        end

        private

        #: (URI uri, Net::HTTPRequest request, Hash[String, String] headers, Logger? logger) -> Net::HTTPResponse?
        def perform(uri, request, headers, logger)
          request["User-Agent"] = USER_AGENT
          headers.each { |name, value| request[name] = value }

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 10
          http.read_timeout = 30

          response = http.request(request)
          return response if response.is_a?(Net::HTTPSuccess)

          logger&.error("Sync::HTTP #{request.method} #{uri} returned status #{response.code}")
          nil
        rescue StandardError => error
          logger&.error("Sync::HTTP #{request.method} #{uri} raised: #{error.class}: #{error.message}")
          nil
        end

        #: (Net::HTTPResponse? response, String url, Logger? logger) -> untyped
        def parse_json(response, url, logger)
          response && JSON.parse(response.body)
        rescue JSON::ParserError => error
          logger&.error(
            "Sync::HTTP #{url} returned invalid JSON " \
              "(Content-Type: #{response["Content-Type"].inspect}): #{error.message}; " \
              "body starts with: #{response.body.to_s[0, 500].inspect}"
          )
          nil
        end
      end
    end
  end
end
