require "rails_helper"

# TLS TERMINATES AT KAMAL-PROXY, SO RAILS MUST BE TOLD (25 Sept 2026).
#
# All three lines were commented out: no Secure cookie on the console, no
# HSTS. They only work TOGETHER, which is why they are checked together.
# Proved once at the production layer (RAILS_ENV=production, plain HTTP as
# the proxy forwards it): the console cookie was `secure`, HSTS was on every
# response, and /up answered 200. With assume_ssl planted off, the console
# and /api answered 301 to https, which behind the proxy is a redirect loop,
# and the console is unreachable.
RSpec.describe "TLS behind the proxy" do
  let(:production) do
    Rails.root.join("config/environments/production.rb").read.lines.reject { _1 =~ /\A\s*#/ }.join
  end

  it "tells Rails the proxy terminated TLS, or force_ssl loops" do
    expect(production).to match(/^\s*config\.assume_ssl = true$/)
  end

  it "forces TLS, for Secure cookies and HSTS" do
    expect(production).to match(/^\s*config\.force_ssl = true$/)
  end

  # kamal-proxy health-checks over plain HTTP; a redirect fails the deploy.
  it "exempts the health check from the redirect" do
    expect(production).to match(%r{config\.ssl_options = \{ redirect: \{ exclude: ->\(request\) \{ request\.path == "/up" \} \} \}})
  end

  it "health-checks the path it exempts" do
    expect(Rails.root.join("config/deploy.yml").read).to match(%r{healthcheck:\s*\n\s*path: /up})
  end
end
