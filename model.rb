require_relative 'entity_class'
require_relative 'api'

module Plugin::Worldon
  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#application
  class Application < Diva::Model
    register :worldon_application, name: "Mastodonアプリケーション(Worldon)"

    field.string :name, required: true
    field.uri :website
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#emoji
  class Emoji < Diva::Model
    register :worldon_emoji, name: "Mastodon絵文字(Worldon)"

    field.string :shortcode, required: true
    field.uri :static_url, required: true
    field.uri :url, required: true
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#attachment
  class Attachment < Diva::Model
    register :worldon_attachment, name: "Mastodon添付メディア(Worldon)"

    field.string :id, required: true
    field.string :type, required: true
    field.uri :url
    field.uri :remote_url
    field.uri :preview_url, required: true
    field.uri :text_url
    field.string :description

    attr_accessor :meta

    def initialize(hash)
      @meta = hash[:meta]
      hash.delete :meta
      super hash
    end
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#mention
  class Mention < Diva::Model
    register :worldon_mention, name: "Mastodonメンション(Worldon)"

    field.uri :url, required: true
    field.string :username, required: true
    field.string :acct, required: true
    field.string :id, required: true
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#tag
  class Tag < Diva::Model
    register :worldon_tag, name: "Mastodonタグ(Worldon)"

    field.string :name, required: true
    field.uri :url, required: true
  end

  class Icon < Diva::Model
    include Diva::Model::PhotoMixin

    register :worldon_icon, name: "Mastodonアカウントアイコン(Worldon)"

    field.uri :uri

    handle ->uri{
      uri.path.start_with?('/system/accounts/avatars/')
    } do |uri|
      new(uri: uri)
    end
  end

  class AccountSource < Diva::Model
    register :worldon_account_source, name: "Mastodonアカウント追加情報(Worldon)"

    field.string :privacy
    field.bool :sensitive
    field.string :note
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#status
  class Account < Diva::Model
    include Diva::Model::UserMixin

    register :worldon_account, name: "Mastodonアカウント(Worldon)"

    field.string :id, required: true
    field.string :username, required: true
    field.string :acct, required: true
    field.string :display_name, required: true
    field.bool :locked, required: true
    field.time :created_at, required: true
    field.int :followers_count, required: true
    field.int :following_count, required: true
    field.int :statuses_count, required: true
    field.string :note, required: true
    field.uri :url, required: true
    field.uri :avatar, required: true
    field.uri :avatar_static, required: true
    field.uri :header, required: true
    field.uri :header_static, required: true
    field.has :moved, Account
    field.has :source, AccountSource

    alias_method :perma_link, :url
    alias_method :uri, :url
    alias_method :idname, :acct
    alias_method :name, :display_name
    alias_method :description, :note

    def initialize(hash)
      hash[:created_at] = Time.parse(hash[:created_at]).localtime
      if hash[:acct].index('@').nil?
        hash[:acct] = hash[:acct] + '@' + Diva::URI.new(hash[:url]).host
      end
      super hash
    end

    def title
      "#{acct}(#{display_name})"
    end

    def icon
      Plugin::Worldon::Icon.new(uri: avatar)
    end
  end

  # https://github.com/tootsuite/documentation/blob/master/Using-the-API/API.md#status
  class Status < Diva::Model
    include Diva::Model::MessageMixin

    register :worldon_status, name: "Mastodonステータス(Worldon)", timeline: true, reply: true, myself: true

    field.string :id, required: true
    field.string :uri, required: true
    field.uri :url, required: true
    field.has :account, Plugin::Worldon::Account, required: true
    field.string :in_reply_to_id
    field.string :in_reply_to_account_id
    field.has :reblog, Plugin::Worldon::Status
    field.string :content, required: true
    field.time :created_at, required: true
    field.time :created
    field.int :reblogs_count
    field.int :favourites_count
    field.bool :reblogged
    field.bool :favourited
    field.bool :muted
    field.bool :sensitive
    field.string :visibility
    field.bool :sensitive?
    field.string :spoiler_text
    field.string :visibility
    field.has :application, Application
    field.string :language
    field.bool :pinned

    field.string :domain # APIには無い追加フィールド

    alias_method :perma_link, :url
    alias_method :shared?, :reblogged
    alias_method :favorite?, :favourited
    alias_method :muted?, :muted
    alias_method :pinned?, :pinned

    attr_accessor :emojis
    attr_accessor :media_attachments
    attr_accessor :mentions
    attr_accessor :tags

    entity_class MastodonEntity

    class << self
      def build(domain_name, json)
        return [] if json.nil?
        json.map do |record|
          record[:domain] = domain_name
          Status.new(record)
        end
      end
    end

    def initialize(hash)
      hash[:created] = hash[:created_at] = Time.parse(hash[:created_at]).localtime

      @emojis = hash[:emojis].nil? ? [] : hash[:emojis].map { |v| Emoji.new(v) }
      @media_attachments = hash[:media_attachments].nil? ? [] : hash[:media_attachments].map { |v| Attachment.new(v) }
      @mentions = hash[:mentions].nil? ? [] : hash[:mentions].map { |v| Mention.new(v) }
      @tags = hash[:tags].nil? ? [] : hash[:tags].map { |v| Tag.new(v) }
      hash.delete :emojis
      hash.delete :media_attachments
      hash.delete :mentions
      hash.delete :tags
      super hash
    end

    def actual_status
      if reblog.nil?
        self
      else
        reblog
      end
    end

    def user
      actual_status.account
    end

    def retweet_count
      actual_status.reblogs_count
    end

    def favorite_count
      actual_status.favourites_count
    end

    def retweeted_by
      if reblog.nil?
        []
      else
        [account]
      end
    end

    def sensitive?
      actual_status.sensitive
    end

    def dehtmlize(text)
      text
        .gsub(/<span class="ellipsis">([^<]*)<\/span>/) {|s| $1 + "..." }
        .gsub(/^<p>|<\/p>|<span class="invisible">[^<]*<\/span>|<\/?span[^>]*>/, '')
        .gsub(/<br[^>]*>|<p>/) { "\n" }
    end

    def description
      msg = actual_status
      desc = dehtmlize(msg.content)
      if !msg.spoiler_text.nil? && msg.spoiler_text.size > 0
        desc = dehtmlize(msg.spoiler_text) + "\n----\n" + desc
      end
      desc
    end

    # register reply:true用API
    def mentioned_by_me?
      # TODO: Status.in_reply_to_account_id と current_world（もしくは受信時のworld？）を見てどうにかする
      false
    end

    # register myself:true用API
    def myself?
      # TODO: Status.account と current_world（もしくは受信時のworld？）を見てどうにかする
      false
    end

    # Basis Model API
    def title
      msg = actual_status
      if !msg.spoiler_text.nil? && msg.spoiler_text.size > 0
        msg.spoiler_text
      else
        msg.content
      end
    end

    # ふぁぼ
    def favorite(do_fav)
      world, = Plugin.filtering(:world_current, nil)
      if do_fav
        Plugin[:worldon].favorite(world, self)
      else
        # TODO: unfavorite spell
      end
    end

    def retweeted_statuses
      # TODO: APIで個別取得するタイミングがわからないので適当
      if reblog.nil?
        []
      else
        [self]
      end
    end

    def quoting?
      content = actual_status.content
      r = %r!<a [^>]*href="https://(?:[^/]+/@[^/]+/\d+|twitter\.com/[^/]+/status/\d+)"!.match(content).nil?
      !r
    end

    def quoting_messages(force_retrieve=false)
      content = actual_status.content
      matches = []
      regexp = %r!<a [^>]*href="(https://(?:[^/]+/@[^/]+/\d+|twitter\.com/[^/]+/\d+))"!
      rest = content
      while m = regexp.match(rest)
        matches.push m.to_a
        rest = m.post_match
      end
      matches
        .map do |m|
          url = m[1]
          if url.index('twitter.com')
            Plugin::Twitter::Message.findbyid(quoted_id, -1)
          else
            m = %r!https://([^/]+)/@[^/]+/(\d+)!.match(url)
            next nil if m.nil?
            domain_name = m[1]
            id = m[2]
            resp = Plugin::Worldon::API.status(domain_name, id)
            next nil if resp.nil?
            resp[:domain] = domain_name
            Status.new(resp)
          end
        end
        .compact
    end

    def around(force_retrieve=false)
      resp = Plugin::Worldon::API.call(:get, domain, '/api/v1/statuses/' + id + '/context')
      return [] if resp.nil?
      Status.build(domain, resp[:ancestors] + resp[:descendants])
    end

    def has_receive_message?
      !in_reply_to_id.nil?
    end

    def replyto_source(force_retrieve=false)
      resp = Plugin::Worldon::API.status(domain, in_reply_to_id)
      return nil if resp.nil?
      resp[:domain] = domain
      Status.new(resp)
    end

    def replyto_source_d(force_retrieve=true)
      promise = Delayer::Deferred.new(true)
      Thread.new do
        begin
          result = replyto_source(force_retrieve)
          if result.is_a? Status
            promise.call(result)
          else
            promise.fail(result)
          end
        rescue Exception => e
          promise.fail(e)
        end
      end
      promise
    end
  end
end
