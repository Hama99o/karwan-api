# Every error Rails reports is logged and kept on the console (launch
# readiness A6). See lib/error_reporting/subscriber.rb for why the log comes
# first. A hosted service, if he ever chooses one, is a second subscriber here.
require Rails.root.join("lib/error_reporting/subscriber")

Rails.error.subscribe(ErrorReporting::Subscriber.new)
