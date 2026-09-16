# Mail to a USER, as opposed to the ops console operator.
#
# One method, and it sends a CODE rather than a link. `hatiwal-api`'s
# `UserMailer#reset_password` puts a token in a URL on hatiwal.com; Karwan has
# no web app (correction 16), so there is no page to open and the person types
# the code into the app instead. See Users::PasswordResetService.
class UserMailer < ApplicationMailer
  def password_reset(user, code, locale: nil)
    @code = code
    @name = user.name.presence
    locale = locale.presence || user.locale

    # RTL for Pashto and Dari, set on the <html> element: an email client is
    # not our app and will not infer direction from the script. A Dari reset
    # email rendering left-to-right is the first thing this platform sends a
    # partner, and it would look broken by a company that cannot write Dari.
    @direction = %w[ps fa].include?(locale.to_s[0, 2]) ? "rtl" : "ltr"
    @body_text = Setting.fetch(body_key(locale)).presence || Setting.fetch("password_reset_email_body_en")
    @body_text = format(@body_text, code: code) if @body_text.include?("%{code}")

    mail(to: user.email, subject: Setting.fetch(subject_key(locale)).presence || Setting.fetch("password_reset_email_subject_en"))
  end

  private

  def suffix(locale)
    case locale.to_s[0, 2]
    when "ps" then "ps"
    when "fa" then "fa"
    else "en"
    end
  end

  def body_key(locale) = "password_reset_email_body_#{suffix(locale)}"
  def subject_key(locale) = "password_reset_email_subject_#{suffix(locale)}"
end
