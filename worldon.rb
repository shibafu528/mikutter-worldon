# -*- coding: utf-8 -*-

require_relative 'model'
require_relative 'world'
require_relative 'api'
require_relative 'instance'
require_relative 'stream'

module Plugin::Worldon
  CLIENT_NAME = 'mikutter Worldon'
  WEB_SITE = 'https://github.com/cobodo/mikutter-worldon'
end

Plugin.create(:worldon) do
  PM = Plugin::Worldon

  # 各インスタンス向けアプリケーションキー用のストレージを確保しておく
  keys = at(:instances)
  if keys.nil?
    keys = Hash.new
    store(:instances, keys)
  end

  # ストリーム開始＆直近取得イベント
  defevent :worldon_start_stream, prototype: [String, String, String, String, Integer]

  # ストリーム開始＆直近取得
  on_worldon_start_stream do |domain, type, slug, token, list_id|
    # ストリーム開始
    PM::Stream.start(domain, type, slug, token, list_id)

    # 直近の分を取得
    opts = { limit: 40 }
    path_base = '/api/v1/timelines/'
    case type
    when 'user'
      path = path_base + 'home'
    when 'public'
      path = path_base + 'public'
    when 'public:local'
      path = path_base + 'public'
      opts[:local] = 1
    when 'list'
      path = path_base + 'list/' + list_id.to_s
    end
    tl = PM::Status.build PM::API.call(:get, domain, path, token, opts)
    Plugin.call :extract_receive_message, slug, tl
  end


  # 終了時
  onunload do
    PM::Stream.killall
  end

  # 起動時
  Delayer.new {
    worlds = Enumerator.new{|y|
      Plugin.filtering(:worlds, y)
    }.select{|world|
      world.class.slug == :worldon_for_mastodon
    }

    worlds.each do |world|
      PM::Stream.init_auth_stream(world)
    end

    worlds.map{|world|
      world.domain
    }.to_a.uniq.each{|domain|
      PM::Stream.init_instance_stream(domain)
    }
  }


  # spell系

  # ふぁぼ
  defevent :worldon_favorite, prototype: [PM::World, PM::Status]

  # ふぁぼる
  on_worldon_favorite do |world, status|
    # TODO: guiなどの他plugin向け通知イベントの調査
    status_id = PM::API.get_local_status_id(world, status)
    PM::API.call(:post, world.domain, '/api/v1/statuses/' + status_id.to_s + '/favourite', world.access_token)
    status.favourited = true
  end

  defspell(:favorite, :worldon_for_mastodon, :worldon_status,
           condition: -> (world, status) { !status.favorite? } # TODO: favorite?の引数にworldを取って正しく判定できるようにする
          ) do |world, status|
    Plugin.call(:worldon_favorite, world, status)
  end

  defspell(:favorited, :worldon_for_mastodon, :worldon_status,
           condition: -> (world, status) { status.favorite? } # TODO: worldを使って正しく判定する
          ) do |world, status|
    Delayer::Deferred.new.next {
      status.favorite? # TODO: 何を返せばいい？
    }
  end

  # ブーストイベント
  defevent :worldon_share, prototype: [PM::World, PM::Status]

  # ブースト
  on_worldon_share do |world, status|
    # TODO: guiなどの他plugin向け通知イベントの調査
    status_id = PM::API.get_local_status_id(world, status)
    PM::API.call(:post, world.domain, '/api/v1/statuses/' + status_id.to_s + '/reblog', world.access_token)
    status.reblogged = true
  end

  defspell(:share, :worldon_for_mastodon, :worldon_status,
           condition: -> (world, status) { !status.shared? } # TODO: shared?の引数にworldを取って正しく判定できるようにする
          ) do |world, status|
    Plugin.call(:worldon_share, world, status)
  end

  defspell(:shared, :worldon_for_mastodon, :worldon_status,
           condition: -> (world, status) { status.shared? } # TODO: worldを使って正しく判定する
          ) do |world, status|
    Delayer::Deferred.new.next {
      status.shared? # TODO: 何を返せばいい？
    }
  end


  # world系

  # world追加
  on_world_create do |world|
    if world.class.slug == :worldon_for_mastodon
      Delayer.new {
        PM::Stream.init_instance_stream(world.domain)
        PM::Stream.init_auth_stream(world)
      }
    end
  end

  # world削除
  on_world_destroy do |world|
    if world.class.slug == :worldon_for_mastodon
      Delayer.new {
        PM::Stream.remove_instance_stream(world.domain)
        PM::Stream.remove_auth_stream(world)
      }
    end
  end

  # world作成
  world_setting(:worldon, _('Mastodonアカウント(Worldon)')) do
    input 'インスタンスのドメイン', :domain

    result = await_input
    domain = result[:domain]

    instance = PM::Instance.load(domain)

    label 'Webページにアクセスして表示された認証コードを入力して、次へボタンを押してください。'
    link instance.authorize_url
    input '認証コード', :authorization_code
    result = await_input
    resp = PM::API.call(:post, domain, '/oauth/token',
                                     client_id: instance.client_key,
                                     client_secret: instance.client_secret,
                                     grant_type: 'authorization_code',
                                     redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
                                     code: result[:authorization_code]
                                    )
    token = resp[:access_token]

    resp = PM::API.call(:get, domain, '/api/v1/accounts/verify_credentials', token)
    if resp.has_key?(:error)
      Deferred.fail(resp[:error])
    end
    screen_name = resp[:acct] + '@' + domain
    resp[:acct] = screen_name
    account = PM::Account.new_ifnecessary(resp)
    world = PM::World.new(
      id: screen_name,
      slug: screen_name,
      domain: domain,
      access_token: token,
      account: account
    )

    label '認証に成功しました。このアカウントを追加しますか？'
    label('アカウント名：' + screen_name)
    label('ユーザー名：' + resp[:display_name])
    world
  end
end
