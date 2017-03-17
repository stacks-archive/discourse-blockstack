# name: discourse-blockstack
# about: Blockstack Auth Provider
# version: 0.4
# author: Larry Salibra

require_dependency 'auth/oauth2_authenticator'
gem "bitcoin-ruby", "0.0.10", require: false
gem "jwt-blockstack", "2.0.0.beta2", require: false
gem "blockstack", "0.5.7", require: false
gem "omniauth-blockstack", "0.9.3", require: false


require 'omniauth/blockstack'
require 'blockstack'
require 'uri'

class BlockstackAuthenticator < ::Auth::OAuth2Authenticator
  def register_middleware(omniauth)
    omniauth.provider :blockstack,
                      :setup => lambda { |env|
                              strategy = env["omniauth.strategy"]
                              strategy.options[:app_name] = SiteSetting.title
                              strategy.options[:app_description] = SiteSetting.site_description
                              strategy.options[:app_icons] = [
                                { :src => lambda {
                                  url = URI(SiteSetting.logo_small_url)
                                  url = "#{Discourse.base_url}#{url}" unless url.absolute?
                                  url.to_s
                                }.call
                              }
                            ]
                              strategy.options[:blockstack_api] = SiteSetting.blockstack_api.chomp("/")
                            }



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
      sync_blockstack_info(result.user, auth[:info])
    # TODO Finish writing logic to change username to blockstack id
    # elsif result.username
    #   username_without_tld = result.username.split(".")[0]
    #   existing_user = User.where(username: username_without_tld)
    #   if existing_user
    #     remaining_tries = 5
    #     while remaining_tries > 0 && result.user.nil?
    #     # change username to blockstack id
    #     result = UsernameChanger.change(existing_user, result.username, nil)
    #     result.user = existing_user if result
    #     remaining_tries--
    #   end
    end
    result.extra_data = { blockstack_user_id: uid, info: auth[:info] }
    result
  end

  def after_create_account(user, auth)
    ::PluginStore.set("blockstack", "blockstack_user_#{auth[:extra_data][:blockstack_user_id]}", {user_id: user.id })
    sync_blockstack_info(user, auth[:extra_data][:info])
  end

  protected

  def sync_blockstack_info(user, info)
    Rails.logger.debug("sync_blockstack_info #{info}")

    user_profile = user.user_profile

    if SiteSetting.blockstack_sync_name && info.name
      user.name = info.name
      user.save
    end

    if SiteSetting.blockstack_sync_description && info[:description]
      user_profile.bio_raw = info[:description]
      user_profile.save
    end

    if SiteSetting.blockstack_sync_location && info[:location]
      user_profile.location = info[:location]
      user_profile.save
    end

    if SiteSetting.blockstack_sync_website && info[:urls]
      urls = info[:urls]
      if urls.count > 0
        user_profile.website = info[:urls][0]
        user_profile.save
      end
    end

    # Adding support for syncing avatar & cover images
    # is more complicated than text fields.
    # If you see this comment, feel free to add support and send
    # a pull request!
  end
end

title = GlobalSetting.try(:blockstack_title) || "Blockstack"
button_title = GlobalSetting.try(:blockstack_title) || "with Blockstack"

auth_provider :title => button_title,
              :authenticator => BlockstackAuthenticator.new('blockstack'),
              :full_screen_login => true
