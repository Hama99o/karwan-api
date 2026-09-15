module Notifications
  module Sms
    # Writes the message to the log instead of sending it.
    #
    # Correct for development, test and a demo; NOT correct for production,
    # where it means every user waits for a code that will never arrive. That
    # is why `SmsClient.production_ready?` exists and why it is false here
    # rather than this adapter pretending.
    class LogAdapter
      def self.deliver(to:, body:)
        Rails.logger.info("[sms:log] to=#{to} body=#{body}")

        SmsClient::Result.new(delivered: true, provider: "log")
      end
    end
  end
end
