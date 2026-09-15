require "net/http"
require "json"

module Notifications
  # Firebase Cloud Messaging, HTTP v1.
  #
  # FCM is chosen because it costs nothing per message, which matters: the
  # per-order marginal cost must be effectively zero and the only recurring
  # costs in v0 are the VPS and SMS.
  #
  # NO CREDENTIALS ARE WIRED. Standing up a Firebase project is Hamma9900's
  # decision and account, so with no credentials this logs and reports
  # `:unconfigured` rather than raising. That distinction matters downstream:
  # "we could not send" must escalate to a human, while "nothing is configured
  # yet" is a deployment state, not a failed alert.
  class FcmClient
    Error = Class.new(StandardError)

    Result = Data.define(:delivered, :failed, :status) do
      def configured?
        status != :unconfigured
      end

      def any_delivered?
        delivered.positive?
      end
    end

    def initialize(project_id: nil, access_token: nil)
      @project_id = project_id || ENV.fetch("FCM_PROJECT_ID", nil)
      @access_token = access_token || ENV.fetch("FCM_ACCESS_TOKEN", nil)
    end

    def configured?
      @project_id.present? && @access_token.present?
    end

    # Returns a Result rather than raising per token: one dead phone must not
    # stop the alert reaching the tablet beside it.
    def send_to(tokens, title_key:, body_key:, data: {})
      tokens = Array(tokens).uniq.compact
      return Result.new(delivered: 0, failed: 0, status: :no_tokens) if tokens.empty?

      unless configured?
        Rails.logger.info("[fcm] unconfigured; would notify #{tokens.size} device(s): #{title_key}")
        return Result.new(delivered: 0, failed: 0, status: :unconfigured)
      end

      delivered = 0
      failed = 0

      tokens.each do |token|
        deliver_one(token, title_key: title_key, body_key: body_key, data: data) ? delivered += 1 : failed += 1
      end

      Result.new(delivered: delivered, failed: failed, status: failed.zero? ? :ok : :partial)
    end

    private

    def deliver_one(token, title_key:, body_key:, data:)
      uri = URI("https://fcm.googleapis.com/v1/projects/#{@project_id}/messages:send")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@access_token}"
      request["Content-Type"] = "application/json"
      request.body = payload(token, title_key: title_key, body_key: body_key, data: data).to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      # A push must never hold up the request that triggered it. This runs in a
      # job, but a hung socket would still occupy a worker.
      http.open_timeout = 2
      http.read_timeout = 5

      response = http.request(request)
      return true if response.is_a?(Net::HTTPSuccess)

      Rails.logger.warn("[fcm] HTTP #{response.code} for token ending #{token.to_s.last(6)}")
      false
    rescue StandardError => e
      Rails.logger.warn("[fcm] #{e.class} for token ending #{token.to_s.last(6)}")
      false
    end

    def payload(token, title_key:, body_key:, data:)
      {
        message: {
          token: token,
          # KEYS, not words. The server cannot write Pashto, and a
          # server-written English notification is untranslatable on the
          # device — so the app localises from these and renders the values.
          data: data.merge(title_key: title_key, body_key: body_key).transform_values(&:to_s),
          android: {
            # Cheap Android with aggressive OEM power management will drop a
            # normal-priority push. A new order is not an announcement.
            priority: "high",
            notification: {
              channel_id: "karwan_orders",
              # Loud and repeating until acknowledged — PRODUCT.md assumes a
              # tablet on a counter in a noisy kitchen.
              sound: "alert",
              default_vibrate_timings: false,
              vibrate_timings: [ "0s", "0.5s", "0.5s", "0.5s" ]
            }
          },
          apns: {
            headers: { "apns-priority" => "10" },
            payload: { aps: { sound: "alert.caf", "interruption-level" => "time-sensitive" } }
          }
        }
      }
    end
  end
end
