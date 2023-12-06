require 'net/http'
require 'json'
require 'uri'

# TODO: 膨大な量のMessageを収集するためそれに耐えうるようにする
# TODO: チャンネル数は絞ろう

# SlackのAPIを叩くためのトークン
# curl -X POST "https://slack.com/api/auth.test" -d "token=your_slack_user_oauth_token"

SLACK_USER_OAUTH_TOKEN = 'your_slack_user_oauth_token'.freeze

BASE_API_URL = 'https://slack.com/api'
CHANNEL_URL = "#{BASE_API_URL}/conversations.list?exclude_archived=true"
HISTORY_URL = "#{BASE_API_URL}/conversations.history"
USER_INFO_URL = "#{BASE_API_URL}/users.info"

# 取得したいメッセージの期間を1ヶ月とする
OLDEST_MSG_TIMESTAMP = Time.new(2023, 11, 1).to_i.freeze
LATEST_MSG_TIMESTAMP = Time.new(2023, 11, 30).to_i.freeze


# ワークスペースの全チャンネルのIDを取得
def get_channel_ids
  uri = URI(CHANNEL_URL)
  request = Net::HTTP::Get.new(uri.path, {'Authorization' => "Bearer #{SLACK_USER_OAUTH_TOKEN}"})

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  response = http.request(request)
  channels_data = JSON.parse(response.body)
  channel_ids = channels_data['channels'].map { |channel| channel['id'] }
end

# 1チャンネルのメッセージを取得し、ユーザーごとのリアクション数をカウント
def get_messages_on(channel_id, user_reaction_hash)  
  uri = URI.parse(HISTORY_URL)
  request = Net::HTTP::Post.new(uri.path, {
    'Content-Type' => 'application/x-www-form-urlencoded',
    'Authorization' => "Bearer #{SLACK_USER_OAUTH_TOKEN}"
  })
  request.body = URI.encode_www_form(
    channel: channel_id,
    oldest: OLDEST_MSG_TIMESTAMP,
    latest: LATEST_MSG_TIMESTAMP
  )
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  response = http.request(request)
  messages_data = JSON.parse(response.body)
  caluculate_reaction_counts_per_user(messages_data, user_reaction_hash)
end

# ユーザーごとのリアクション数をカウント
def caluculate_reaction_counts_per_user(messages_data, user_reaction_hash)
  messages_data['messages'].each do |message|
    if message.key?('reactions')
      message['reactions'].each do |reaction|
        # reaction {"name"=>"innocent", "users"=>["U05QPMP75BL"], "count"=>1}
        # 複数の人で同じスタンプを押している場合は、usersに複数のユーザーが入っている
        reaction['users'].each do |user|
          user_reaction_hash[user]["reaction_count"] += 1
          reaction['name'] ||= 'unknown_reaction'
          user_reaction_hash[user]["emoji"][reaction['name']] += 1
        end
      end
    end
  end
end

def user_name(user_id)
  uri = URI(USER_INFO_URL)
  request = Net::HTTP::Post.new(uri.path, {
    'Content-Type' => 'application/x-www-form-urlencoded',
    'Authorization' => "Bearer #{SLACK_USER_OAUTH_TOKEN}"
  })
  request.body = URI.encode_www_form(user: user_id)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  response = http.request(request)
  user_data = JSON.parse(response.body)
  user_data['user']['real_name']
end


def most_often_used_emoji(emoji_hash)
  emoji_hash.sort_by { |_, count| -count }.take(1)[0][0]
end

def run_script
  # 各チャンネルのメッセージを取得し、リアクションをつけたユーザーをカウント
  # {"U05QPMP75BL"=>{"reaction_count"=>5, "emoji"=>{"smile"=>3, "heart"=>2}}
  user_reaction_hash = Hash.new { |hash, key| hash[key] = { "reaction_count" => 0, "emoji" => Hash.new(0) } }
  
  # ワークスペースの全チャンネルのIDを取得
  channel_ids = get_channel_ids
  
  messages = []
  channel_ids.each do |channel_id|
    get_messages_on(channel_id, user_reaction_hash)
    # 1回のAPIアクセスで1000件までしか取得できないため、cursor（ページネーション）がある場合は繰り返し取得する
    # while messages.any? && messages_data['response_metadata'] && messages_data['response_metadata']['next_cursor']
    #   cursor = messages_data['response_metadata']['next_cursor']
    #   additional_messages_data = get_messages_on(channel_id, user_reaction_counts_hash)
    #   messages.concat(additional_messages_data)
    # end
  end
  
  # 最もリアクションをした3ユーザーを取得
  top_three_reaction_users = user_reaction_hash.sort_by { |_, reaction_hash| -reaction_hash['reaction_count'] }.take(3)
  
  # 結果を表示
  top_three_reaction_users.each_with_index do |user, i|
    user_name = user_name(user[0])
    reaction_count = user[1]['reaction_count']
    most_often_used_emoji = most_often_used_emoji(user[1]['emoji'])
    most_often_used_emoji_count = user[1]['emoji'][most_often_used_emoji]
  
    puts "[No.#{i.to_i + 1}]#{user_name} is reaction_counts: #{reaction_count}, most_often_used_emoji: #{most_often_used_emoji} is #{most_often_used_emoji_count} times"
  end
end

# 実行
run_script
