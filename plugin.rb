# name: discourse-blockstack
# about: Blockstack Auth Provider
# version: 0.1
# author: Larry Salibra

require_dependency 'auth/oauth2_authenticator'
gem "bitcoin-ruby", "0.0.10", require: false
gem "jwt-blockstack", "2.0.0.beta2", require: false
gem "blockstack", "0.5.7", require: false
gem "omniauth-blockstack", "0.9.2", require: false


require 'omniauth/blockstack'
require 'blockstack'
require 'uri'

class BlockstackAuthenticator < ::Auth::OAuth2Authenticator
  def register_middleware(omniauth)
    omniauth.provider :blockstack,
                      :app_name => SiteSetting.title,
                      :app_description => SiteSetting.site_description,
                      :app_icons => [
                        { :src => lambda {
                          url = URI(SiteSetting.logo_small_url)
                          url = "#{Discourse.base_url}#{url}" unless url.absolute?
                          url.to_s
                        }.call
                      }

                      ],
                      :blockstack_api => 'http://localhost:6270'

  end

  def after_authenticate(auth)
    result = Auth::Result.new
    uid = auth[:uid]
    result.name = auth[:info].name
    result.username = auth[:info].nickname ? auth[:info].nickname : Blockstack.get_address_from_did(uid)
    result.email_valid = false

    current_info = ::PluginStore.get("blockstack", "blockstack_user_#{uid}")
    if current_info
      result.user = User.where(id: current_info[:user_id]).first
    end
    result.extra_data = { blockstack_user_id: uid }
    result
  end

  def after_create_account(user, auth)
    ::PluginStore.set("blockstack", "blockstack_user_#{auth[:extra_data][:blockstack_user_id]}", {user_id: user.id })
  end

end

title = GlobalSetting.try(:blockstack_title) || "Blockstack"
button_title = GlobalSetting.try(:blockstack_title) || "with Blockstack"

auth_provider :title => button_title,
              :authenticator => BlockstackAuthenticator.new('blockstack'),
              :full_screen_login => true
