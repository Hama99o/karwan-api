require "rails_helper"
RSpec.describe "DUMP wallet page", type: :request do
  it "writes it" do
    out = ENV.fetch("DUMP_DIR")
    admin = AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password")
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    get "/admin/courier_wallets/#{create(:user, :courier).courier_wallet.id}"
    File.write(File.join(out, "wallet.html"), response.body)
    Nokogiri::HTML(response.body).css("script[src]").each do |s|
      path = URI(s["src"]).path
      get path
      File.binwrite(File.join(out, File.basename(path)), response.body)
      puts "SCRIPT #{path} #{response.status}"
    end
  end
end
