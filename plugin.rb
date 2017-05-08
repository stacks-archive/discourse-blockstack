# name: discourse-blockstack
# about: Blockstack Auth Provider
# version: 0.6.3
# author: Larry Salibra

require_dependency 'auth/oauth2_authenticator'
gem "bitcoin-ruby", "0.0.10", require: false
gem "jwtb", "2.0.0.beta2.bsk1", require: false
gem "blockstack", "0.5.9", require: false
gem "omniauth-blockstack", "0.10.3", require: false


require 'omniauth/blockstack'
require 'blockstack'
require 'uri'


register_asset 'stylesheets/blockstack.scss'

class BlockstackAuthenticator < ::Auth::OAuth2Authenticator
  def register_middleware(omniauth)
    # Blockstack IDs can be up to 60 characters long
    # SiteSetting.max_username_length = 60


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
    did = auth[:uid]
    result.name = auth[:info].name
    blockstack_id = auth[:info].nickname

    result.user = get_user_by_blockstack_did(did)

    if result.user
      debug_log "Found a user that previously logged in with DID #{did}"
      sync_blockstack_info(result.user, auth[:info])
    elsif blockstack_id
      debug_log "No user previously logged in with did #{did}, but Blockstack ID #{blockstack_id } is claimed."
      existing_user = User.where(username: blockstack_id).first
      if existing_user && SiteSetting.blockstack_id_owns_forum_account
        debug_log "User with matching Blockstack ID #{blockstack_id} has never logged in with Blockstack"
        result.user = existing_user # log in this user
      end
      if SiteSetting.blockstack_id_without_tld_owns_forum_account
        if existing_user
          debug_log "Found a discourse user with username that matches Blockstack ID so blockstack_id_without_tld_owns_forum_account has no effect."
        else
          debug_log "No discourse user with Blockstack ID #{blockstack_id} - let's look for one without the TLD"
          username_without_tld = blockstack_id.split(".")[0]
          existing_user = User.where(username: username_without_tld).first
          if existing_user
            debug_log "Found existing discourse user matching Blockstack ID minus TLD: #{username_without_tld}"

            result.user = existing_user # log in this user

            debug_log "Trying to change #{username_without_tld}'s username to #{blockstack_id}'"
            # try to change username to fully qualified blockstack id
            change_result = ::UsernameChanger.change(existing_user, blockstack_id, nil)
            if change_result != true
              debug_log "Failed to change #{username_without_tld}'s username to #{blockstack_id}'"
              debug_log "This will happen if #{blockstack_id}'s DID changed."
            end
          end
        end
      end

      if result.user
        # We found a user
        link_user_with_blockstack_did(result.user, did)
      end
    end

    if result.user.nil?  # This is a new user
      # Set their username
      result.username = blockstack_id ? blockstack_id : Blockstack.get_address_from_did(did)
      result.email_valid = false
    end

    result.extra_data = { blockstack_did: did, info: auth[:info] }
    result
  end

  def after_create_account(user, auth)
    link_user_with_blockstack_did(user, auth[:extra_data][:blockstack_did])
    sync_blockstack_info(user, auth[:extra_data][:info])
  end

  protected

  def link_user_with_blockstack_did(user, did)
    ::PluginStore.set("blockstack", "blockstack_user_#{did}", {user_id: user.id })
  end

  def get_user_by_blockstack_did(did)
    current_info = ::PluginStore.get("blockstack", "blockstack_user_#{did}")
    current_info.nil? ? nil : User.where(id: current_info[:user_id]).first
  end

  def sync_blockstack_info(user, info)
    debug_log("sync_blockstack_info #{info}")

    user_profile = user.user_profile


    if info[:image] && SiteSetting.blockstack_sync_avatar
      begin
        image_uri = URI::parse(info[:image])
        ::Jobs.enqueue(:download_avatar_from_url, url: image_uri.to_s, user_id: user.id, override_gravatar: true)
      rescue URI::InvalidURIError => error
        debug_log "User id #{user.id} has an invalid url as their Blockstack ID avatar"
      end
    end

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

  def debug_log(message)
    Rails.logger.debug "discourse-blockstack: #{message}"
  end
end

title = GlobalSetting.try(:blockstack_title) || "Blockstack"
button_title = GlobalSetting.try(:blockstack_title) || "with Blockstack"

auth_provider :title => button_title,
              :authenticator => BlockstackAuthenticator.new('blockstack'),
              :full_screen_login => true
