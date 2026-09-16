class ApplicationMailer < ActionMailer::Base
  # From a variable, like every other host and credential in this project — and
  # NOT the Rails-generated `from@example.com`, which would have gone out on a
  # real password-reset email and been silently dropped by every receiving
  # server as unroutable. A reset nobody receives presents as "the app is
  # broken", which is the most expensive kind of wrong.
  default from: ENV.fetch("MAILER_FROM", "no-reply@karwan.af")
  layout "mailer"
end
