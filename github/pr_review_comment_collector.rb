#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'time'
require 'optparse'

# GitHub PR レビューコメント収集クラス
class PrReviewCommentCollector
  BASE_URL = 'https://api.github.com'
  
  def initialize(token)
    @token = token
    @headers = {
      'Authorization' => "token #{@token}",
      'Accept' => 'application/vnd.github.v3+json',
      'User-Agent' => 'PR-Review-Comment-Collector'
    }
  end

  # メインの実行メソッド
  def collect_review_comments(repository, reviewer, start_date, end_date)
    # トークンの有効性を検証
    unless validate_token
      puts "エラー: GitHub Personal Access Tokenが無効です。"
      puts "トークンを確認して再実行してください。"
      return 0
    end

    puts "=== PR レビューコメント収集開始 ==="
    puts "リポジトリ: #{repository}"
    puts "レビュー者: #{reviewer}"
    puts "期間: #{start_date} ～ #{end_date}"
    puts "=" * 40

    total_comments = 0
    pr_count = 0
    
    # 指定期間内のPRを取得
    prs = fetch_prs_in_period(repository, start_date, end_date)
    puts "期間内のPR数: #{prs.length}"

    prs.each do |pr|
      # レビュー者がアサインされているかチェック
      if pr_has_reviewer?(pr, reviewer)
        pr_count += 1
        comment_count = count_review_comments(repository, pr['number'], reviewer)
        total_comments += comment_count
        
        puts "PR ##{pr['number']}: #{pr['title']} - #{comment_count}件のコメント"
      end
    end

    puts "=" * 40
    puts "結果:"
    puts "対象PR数: #{pr_count}"
    puts "総レビューコメント数: #{total_comments}"
    puts "平均コメント数/PR: #{'%.2f' % (pr_count > 0 ? total_comments.to_f / pr_count : 0)}"
    
    total_comments
  end

  # GitHub Personal Access Tokenの有効性を検証
  def validate_token
    response = make_request("/user")
    !response.nil? && !response.empty? && response.is_a?(Hash) && response.key?('login')
  rescue => e
    puts "トークン検証エラー: #{e.message}"
    false
  end

  private

  # 指定期間内のPRを取得
  def fetch_prs_in_period(repository, start_date, end_date)
    prs = []
    page = 1
    per_page = 100

    loop do
      response = make_request("/repos/#{repository}/pulls", {
        state: 'closed',
        sort: 'updated',
        direction: 'desc',
        page: page,
        per_page: per_page
      })

      break if response.empty?

      page_prs = response.select do |pr|
        pr_updated = Time.parse(pr['updated_at'])
        pr_updated >= start_date && pr_updated <= end_date
      end

      prs.concat(page_prs)

      # 更新日時が期間外になったら終了
      break if response.last && Time.parse(response.last['updated_at']) < start_date

      page += 1
    end

    prs
  end

  # PRにレビュー者がアサインされているかチェック
  def pr_has_reviewer?(pr, reviewer)
    # PR作成者は除外
    return false if pr['user']['login'] == reviewer

    # レビューリクエストをチェック
    reviews = make_request("/repos/#{pr['base']['repo']['full_name']}/pulls/#{pr['number']}/reviews")
    
    reviews.any? { |review| review['user']['login'] == reviewer }
  end

  # 特定のPRにおけるレビュー者のコメント数をカウント
  def count_review_comments(repository, pr_number, reviewer)
    comment_count = 0

    # レビューコメント（コードに対するコメント）を取得
    review_comments = make_request("/repos/#{repository}/pulls/#{pr_number}/comments")
    
    review_comments.each do |comment|
      if comment['user']['login'] == reviewer
        # approveやrequest_changesのコメントは除外し、純粋なレビューコメントのみカウント
        if comment['body'] && !comment['body'].strip.empty?
          comment_count += 1
        end
      end
    end

    # 通常のレビュー（submit時のコメント）も確認
    reviews = make_request("/repos/#{repository}/pulls/#{pr_number}/reviews")
    
    reviews.each do |review|
      if review['user']['login'] == reviewer && 
         review['body'] && 
         !review['body'].strip.empty? &&
         review['state'] != 'APPROVED' # approve時の自動コメントは除外
        comment_count += 1
      end
    end

    comment_count
  end

  # GitHub API リクエスト
  def make_request(endpoint, params = {})
    uri = URI("#{BASE_URL}#{endpoint}")
    
    unless params.empty?
      uri.query = URI.encode_www_form(params)
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    @headers.each { |key, value| request[key] = value }

    response = http.request(request)

    case response.code
    when '200'
      JSON.parse(response.body)
    when '401'
      puts "エラー: 認証に失敗しました (HTTP 401)"
      puts "GitHub Personal Access Tokenを確認してください。"
      puts "トークン作成方法: https://docs.github.com/ja/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token"
      []
    when '404'
      puts "エラー: リソースが見つかりません (HTTP 404)"
      puts "リポジトリ名を確認してください: #{uri}"
      []
    when '403'
      puts "エラー: API制限またはアクセス権限がありません (HTTP 403)"
      puts "レート制限に達している可能性があります。1時間後に再実行してください。"
      []
    else
      puts "エラー: HTTP #{response.code} - #{response.body}"
      []
    end
  rescue => e
    puts "エラー: #{e.message}"
    []
  end
end

# コマンドライン引数の解析
def parse_arguments
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "使用方法: ruby pr_review_comment_collector.rb [options]"
    
    opts.on("-r", "--repository REPOSITORY", "対象リポジトリ (例: owner/repo)") do |repo|
      options[:repository] = repo
    end
    
    opts.on("-u", "--reviewer USERNAME", "レビュー者のGitHubユーザー名") do |user|
      options[:reviewer] = user
    end
    
    opts.on("-s", "--start-date DATE", "開始日 (YYYY-MM-DD形式)") do |date|
      options[:start_date] = Date.parse(date)
    end
    
    opts.on("-e", "--end-date DATE", "終了日 (YYYY-MM-DD形式)") do |date|
      options[:end_date] = Date.parse(date)
    end
    
    opts.on("-t", "--token TOKEN", "GitHub Personal Access Token") do |token|
      options[:token] = token
    end
    
    opts.on("-h", "--help", "ヘルプを表示") do
      puts opts
      exit
    end
  end.parse!
  
  options
end

# バリデーション
def validate_options(options)
  required_fields = [:repository, :reviewer, :start_date, :end_date, :token]
  missing_fields = required_fields.select { |field| options[field].nil? }
  
  unless missing_fields.empty?
    puts "エラー: 以下の必須パラメータが不足しています: #{missing_fields.join(', ')}"
    puts "使用方法: ruby pr_review_comment_collector.rb --help"
    exit 1
  end
  
  if options[:start_date] > options[:end_date]
    puts "エラー: 開始日は終了日より前である必要があります"
    exit 1
  end
end

# .envファイルを読み込む関数
def load_env_file(env_path = '.env')
  return unless File.exist?(env_path)
  
  File.readlines(env_path).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')
    
    key, value = line.split('=', 2)
    ENV[key] = value if key && value
  end
end

# メイン実行部
if __FILE__ == $0
  # .envファイルを読み込み
  env_file_path = File.join(File.dirname(__FILE__), '..', '.env')
  load_env_file(env_file_path)
  
  # 環境変数からトークンを取得（コマンドライン引数で上書き可能）
  ENV['GITHUB_TOKEN'] ||= ''
  
  options = parse_arguments
  options[:token] ||= ENV['GITHUB_TOKEN']
  
  validate_options(options)
  
  # 日付をTimeオブジェクトに変換
  start_time = Time.new(options[:start_date].year, options[:start_date].month, options[:start_date].day)
  end_time = Time.new(options[:end_date].year, options[:end_date].month, options[:end_date].day, 23, 59, 59)
  
  begin
    collector = PrReviewCommentCollector.new(options[:token])
    result = collector.collect_review_comments(
      options[:repository],
      options[:reviewer], 
      start_time,
      end_time
    )
    
    puts "\n処理が完了しました。"
    
  rescue => e
    puts "エラーが発生しました: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end