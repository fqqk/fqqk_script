#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'time'
require 'optparse'

# PR レビュー迅速性計測クラス
class PrReviewSpeedAnalyzer
  BASE_URL = 'https://api.github.com'
  
  def initialize(token)
    @token = token
    @headers = {
      'Authorization' => "token #{@token}",
      'Accept' => 'application/vnd.github.v3+json',
      'User-Agent' => 'PR-Review-Speed-Analyzer'
    }
  end

  # メインの実行メソッド
  def analyze_review_speed(repository, reviewer, start_date, end_date, design_keywords = [])
    # トークンの有効性を検証
    unless validate_token
      puts "エラー: GitHub Personal Access Tokenが無効です。"
      puts "トークンを確認して再実行してください。"
      return false
    end

    puts "=== PR レビュー迅速性分析開始 ==="
    puts "リポジトリ: #{repository}"
    puts "レビュー者: #{reviewer}"
    puts "期間: #{start_date} ～ #{end_date}"
    puts "設計レビューキーワード: #{design_keywords.join(', ')}" unless design_keywords.empty?
    puts "=" * 50

    # 指定期間内のPRを取得
    prs = fetch_prs_in_period(repository, start_date, end_date)
    puts "期間内のPR数: #{prs.length}"

    normal_prs = []
    design_prs = []
    
    prs.each do |pr|
      # レビュー者がアサインされているかチェック
      if pr_has_reviewer?(pr, reviewer)
        if is_design_review?(pr, design_keywords)
          design_prs << pr
        else
          normal_prs << pr
        end
      end
    end

    puts "\n=== 分析結果 ==="
    
    # 通常のPRレビュー分析（当日中）
    normal_result = analyze_normal_reviews(repository, normal_prs, reviewer)
    
    # 設計レビュー分析（3日以内）
    design_result = analyze_design_reviews(repository, design_prs, reviewer)
    
    # 総合結果
    display_summary(normal_result, design_result)
    
    {
      normal: normal_result,
      design: design_result
    }
  end

  private

  # 通常のPRレビュー分析（当日中のレビュー率）
  def analyze_normal_reviews(repository, prs, reviewer)
    puts "\n--- 通常PRレビュー（レビューリクエストから当日中レビュー率） ---"
    
    total_count = 0
    on_time_count = 0
    review_details = []

    prs.each do |pr|
      review_data = analyze_pr_review_timing(repository, pr, reviewer, 1) # 1日以内
      if review_data
        total_count += 1
        if review_data[:on_time]
          on_time_count += 1
        end
        review_details << review_data
        
        status = review_data[:on_time] ? "✅ 当日中" : "❌ 遅延"
        puts "PR ##{pr['number']}: #{pr['title']} - #{status} (リクエストから#{review_data[:review_time]})"
      end
    end

    rate = total_count > 0 ? (on_time_count.to_f / total_count * 100).round(1) : 0
    target_met = rate >= 70.0

    puts "通常PRレビュー結果:"
    puts "  対象PR数: #{total_count}"
    puts "  当日中レビュー数: #{on_time_count}"
    puts "  当日中レビュー率: #{rate}% #{target_met ? '✅ 目標達成' : '❌ 目標未達成'} (目標: 70%以上)"

    {
      type: 'normal',
      total_count: total_count,
      on_time_count: on_time_count,
      rate: rate,
      target_met: target_met,
      details: review_details
    }
  end

  # 設計レビュー分析（3日以内のレビュー率）
  def analyze_design_reviews(repository, prs, reviewer)
    puts "\n--- 設計レビュー（レビューリクエストから3日以内レビュー率） ---"
    
    total_count = 0
    on_time_count = 0
    review_details = []

    prs.each do |pr|
      review_data = analyze_pr_review_timing(repository, pr, reviewer, 3) # 3日以内
      if review_data
        total_count += 1
        if review_data[:on_time]
          on_time_count += 1
        end
        review_details << review_data
        
        status = review_data[:on_time] ? "✅ 3日以内" : "❌ 遅延"
        puts "PR ##{pr['number']}: #{pr['title']} - #{status} (リクエストから#{review_data[:review_time]})"
      end
    end

    rate = total_count > 0 ? (on_time_count.to_f / total_count * 100).round(1) : 0
    target_met = rate >= 70.0

    puts "設計レビュー結果:"
    puts "  対象PR数: #{total_count}"
    puts "  3日以内レビュー数: #{on_time_count}"
    puts "  3日以内レビュー率: #{rate}% #{target_met ? '✅ 目標達成' : '❌ 目標未達成'} (目標: 70%以上)"

    {
      type: 'design',
      total_count: total_count,
      on_time_count: on_time_count,
      rate: rate,
      target_met: target_met,
      details: review_details
    }
  end

  # 個別PRのレビュータイミング分析
  def analyze_pr_review_timing(repository, pr, reviewer, target_days)
    # レビューリクエストの開始時点を取得
    review_start_time = get_review_request_start_time(repository, pr, reviewer)
    return nil unless review_start_time
    
    # レビューを取得
    reviews = make_request("/repos/#{repository}/pulls/#{pr['number']}/reviews")
    reviewer_reviews = reviews.select { |review| review['user']['login'] == reviewer }
    
    return nil if reviewer_reviews.empty?
    
    # 最初のレビュー時刻を取得
    first_review_time = reviewer_reviews.map { |review| Time.parse(review['submitted_at']) }.min
    
    # レビューリクエストから実際のレビューまでの時間を計算
    review_delay_hours = ((first_review_time - review_start_time) / 3600).round(1)
    review_delay_days = (review_delay_hours / 24).round(1)
    
    # 目標時間内かチェック
    on_time = review_delay_days <= target_days
    
    # レビュー時間の表記
    if review_delay_hours < 24
      review_time_display = "#{review_delay_hours}時間後"
    else
      review_time_display = "#{review_delay_days}日後"
    end

    {
      pr_number: pr['number'],
      pr_title: pr['title'],
      review_requested_at: review_start_time,
      first_review_at: first_review_time,
      delay_hours: review_delay_hours,
      delay_days: review_delay_days,
      on_time: on_time,
      review_time: review_time_display,
      target_days: target_days
    }
  end

  # レビューリクエストの開始時点を取得
  def get_review_request_start_time(repository, pr, reviewer)
    # PRのイベントを取得してレビューリクエストのタイミングを確認
    events = make_request("/repos/#{repository}/issues/#{pr['number']}/events")
    
    # レビューリクエストされた時刻を探す
    review_requested_events = events.select do |event|
      event['event'] == 'review_requested' && 
      event['requested_reviewer'] && 
      event['requested_reviewer']['login'] == reviewer
    end
    
    if review_requested_events.any?
      # 最初にレビューリクエストされた時刻
      Time.parse(review_requested_events.first['created_at'])
    else
      # レビューリクエストイベントが見つからない場合は、レビューした事実があるかチェック
      reviews = make_request("/repos/#{repository}/pulls/#{pr['number']}/reviews")
      reviewer_reviews = reviews.select { |review| review['user']['login'] == reviewer }
      
      if reviewer_reviews.any?
        # レビューがある場合は、PR作成時刻をレビューリクエスト開始とみなす
        # （明示的なリクエストがなくても、レビューした場合は暗黙的にリクエストされていたとみなす）
        Time.parse(pr['created_at'])
      else
        # レビューもない場合はnil
        nil
      end
    end
  end

  # 設計レビューかどうかを判定
  def is_design_review?(pr, design_keywords)
    return false if design_keywords.empty?
    
    title = pr['title'].downcase
    body = (pr['body'] || '').downcase
    
    design_keywords.any? do |keyword|
      title.include?(keyword.downcase) || body.include?(keyword.downcase)
    end
  end

  # 総合結果表示
  def display_summary(normal_result, design_result)
    puts "\n" + "=" * 50
    puts "=== 総合結果サマリー ==="
    puts "=" * 50
    
    puts "📊 通常PRレビュー（リクエストから当日中）:"
    puts "   レビュー率: #{normal_result[:rate]}% (#{normal_result[:on_time_count]}/#{normal_result[:total_count]})"
    puts "   目標達成: #{normal_result[:target_met] ? '✅ YES' : '❌ NO'} (目標: 70%以上)"
    
    puts "\n🎨 設計レビュー（リクエストから3日以内）:"
    puts "   レビュー率: #{design_result[:rate]}% (#{design_result[:on_time_count]}/#{design_result[:total_count]})"
    puts "   目標達成: #{design_result[:target_met] ? '✅ YES' : '❌ NO'} (目標: 70%以上)"
    
    overall_success = normal_result[:target_met] && design_result[:target_met]
    puts "\n🎯 総合評価: #{overall_success ? '✅ 両方の目標を達成' : '❌ 改善が必要'}"
    
    unless overall_success
      puts "\n💡 改善提案:"
      puts "   - 通常PRはレビューリクエストから当日中のレビューを心がけましょう" unless normal_result[:target_met]
      puts "   - 設計レビューはレビューリクエストから3日以内のレビューを心がけましょう" unless design_result[:target_met]
    end
  end

  # 指定期間内のPRを取得
  def fetch_prs_in_period(repository, start_date, end_date)
    prs = []
    page = 1
    per_page = 100

    loop do
      response = make_request("/repos/#{repository}/pulls", {
        state: 'all',
        sort: 'created',
        direction: 'desc',
        page: page,
        per_page: per_page
      })

      break if response.empty?

      page_prs = response.select do |pr|
        pr_created = Time.parse(pr['created_at'])
        pr_created >= start_date && pr_created <= end_date
      end

      prs.concat(page_prs)

      # 作成日時が期間外になったら終了
      break if response.last && Time.parse(response.last['created_at']) < start_date

      page += 1
    end

    prs
  end

  # PRにレビュー者がアサインされているかチェック
  def pr_has_reviewer?(pr, reviewer)
    # PR作成者は除外
    return false if pr['user']['login'] == reviewer

    repository = pr['base']['repo']['full_name']
    
    # 1. 明示的なレビューリクエストをチェック
    events = make_request("/repos/#{repository}/issues/#{pr['number']}/events")
    review_requested = events.any? do |event|
      event['event'] == 'review_requested' && 
      event['requested_reviewer'] && 
      event['requested_reviewer']['login'] == reviewer
    end
    
    return true if review_requested
    
    # 2. 実際にレビューを行った場合もレビュー者とみなす
    reviews = make_request("/repos/#{repository}/pulls/#{pr['number']}/reviews")
    reviewed = reviews.any? { |review| review['user']['login'] == reviewer }
    
    reviewed
  end

  # GitHub Personal Access Tokenの有効性を検証
  def validate_token
    response = make_request("/user")
    !response.nil? && !response.empty? && response.is_a?(Hash) && response.key?('login')
  rescue => e
    puts "トークン検証エラー: #{e.message}"
    false
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
      []
    when '404'
      puts "エラー: リソースが見つかりません (HTTP 404)"
      []
    when '403'
      puts "エラー: API制限またはアクセス権限がありません (HTTP 403)"
      []
    else
      puts "エラー: HTTP #{response.code} - #{response.body}"
      []
    end
  rescue => e
    puts "リクエストエラー: #{e.message}"
    []
  end
end

# コマンドライン引数の解析
def parse_arguments
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "使用方法: ruby pr_review_speed_analyzer.rb [options]"
    
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
    
    opts.on("-d", "--design-keywords KEYWORDS", Array, "設計レビュー判定キーワード (カンマ区切り)") do |keywords|
      options[:design_keywords] = keywords
    end
    
    opts.on("-h", "--help", "ヘルプを表示") do
      puts opts
      puts "\n使用例:"
      puts "  ruby pr_review_speed_analyzer.rb -r owner/repo -u reviewer -s 2025-06-01 -e 2025-06-30"
      puts "  ruby pr_review_speed_analyzer.rb -r owner/repo -u reviewer -s 2025-06-01 -e 2025-06-30 -d \"design,architecture,設計\""
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
    puts "使用方法: ruby pr_review_speed_analyzer.rb --help"
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
  
  options = parse_arguments
  options[:token] ||= ENV['GITHUB_TOKEN']
  options[:design_keywords] ||= []
  
  validate_options(options)
  
  # 日付をTimeオブジェクトに変換
  start_time = Time.new(options[:start_date].year, options[:start_date].month, options[:start_date].day)
  end_time = Time.new(options[:end_date].year, options[:end_date].month, options[:end_date].day, 23, 59, 59)
  
  begin
    analyzer = PrReviewSpeedAnalyzer.new(options[:token])
    result = analyzer.analyze_review_speed(
      options[:repository],
      options[:reviewer], 
      start_time,
      end_time,
      options[:design_keywords]
    )
    
    puts "\n処理が完了しました。"
    
  rescue => e
    puts "エラーが発生しました: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end
