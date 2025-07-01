# GitHub PR レビューコメント収集スクリプト

このスクリプトは、指定したリポジトリ・レビュー者・期間において、レビュー者がレビュワーとしてアサインされたPRにおけるPRレビューコメント数を収集します。

## 機能

- 指定期間内のPRを取得
- レビュー者がアサインされたPRのみを対象
- コードに対する純粋なレビューコメントのみをカウント（approve時の自動コメント等は除外）
- 詳細な統計情報を表示

## 必要な要件

- Ruby 2.7以上
- GitHub Personal Access Token
- インターネット接続

## セットアップ

1. **GitHub Personal Access Tokenを取得**
   - GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
   - "Generate new token (classic)" をクリック
   - Note（説明）を入力（例: "PR Review Comment Collector"）
   - 有効期限を選択
   - 必要な権限を選択:
     - ✅ `repo` (プライベートリポジトリの場合)
     - ✅ `public_repo` (パブリックリポジトリの場合)
   - "Generate token" をクリック
   - ⚠️ **重要**: 生成されたトークンをコピーして安全な場所に保存（再表示されません）

2. **環境変数を設定（推奨）**
   
   **方法1: .envファイルを使用（推奨）**
   ```bash
   # プロジェクトルートに.envファイルを作成
   echo "GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx" > .env
   ```
   
   **方法2: シェルの環境変数として設定**
   ```bash
   # .bashrc または .zshrc に追加
   export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
   
   # 現在のセッションで設定
   export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
   ```

3. **トークンの動作確認**
   ```bash
   # APIが正常に動作するか確認
   curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user
   ```

## 使用方法

```bash
ruby pr_review_comment_collector.rb \
  --repository owner/repo-name \
  --reviewer username \
  --start-date 2025-06-01 \
  --end-date 2025-06-30 \
  --token your_github_token
```

### パラメータ

- `--repository` または `-r`: 対象リポジトリ（例: `facebook/react`）
- `--reviewer` または `-u`: レビュー者のGitHubユーザー名
- `--start-date` または `-s`: 開始日（YYYY-MM-DD形式）
- `--end-date` または `-e`: 終了日（YYYY-MM-DD形式）
- `--token` または `-t`: GitHub Personal Access Token（環境変数 `GITHUB_TOKEN` でも設定可能）

### 使用例

```bash
# .envファイルでトークンを設定している場合（推奨）
ruby pr_review_comment_collector.rb \
  -r myorg/myrepo \
  -u johndoe \
  -s 2025-06-01 \
  -e 2025-06-30

# 環境変数でトークンを設定している場合
ruby pr_review_comment_collector.rb \
  -r myorg/myrepo \
  -u johndoe \
  -s 2025-06-01 \
  -e 2025-06-30

# トークンを直接指定する場合
ruby pr_review_comment_collector.rb \
  --repository myorg/myrepo \
  --reviewer johndoe \
  --start-date 2025-06-01 \
  --end-date 2025-06-30 \
  --token ghp_xxxxxxxxxxxxxxxxxxxx
```

## 出力例

```
=== PR レビューコメント収集開始 ===
リポジトリ: myorg/myrepo
レビュー者: johndoe
期間: 2025-06-01 00:00:00 +0900 ～ 2025-06-30 23:59:59 +0900
========================================
期間内のPR数: 25
PR #123: Add new feature - 3件のコメント
PR #124: Fix bug in authentication - 1件のコメント
PR #125: Update dependencies - 2件のコメント
========================================
結果:
対象PR数: 3
総レビューコメント数: 6
平均コメント数/PR: 2.00

処理が完了しました。
```

## 注意事項

- GitHub APIのレート制限（1時間あたり5000リクエスト）に注意してください
- 大きなリポジトリや長期間の場合、処理に時間がかかる場合があります
- プライベートリポジトリにアクセスする場合は、適切な権限を持つトークンが必要です

## トラブルシューティング

### エラー: HTTP 401 - Bad credentials
このエラーはGitHub Personal Access Tokenの認証に問題があることを示しています。

**解決方法:**
1. **トークンの確認**
   ```bash
   # 環境変数が設定されているか確認
   echo $GITHUB_TOKEN
   ```

2. **新しいトークンを作成**
   - GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
   - "Generate new token (classic)" をクリック
   - 必要な権限を選択:
     - `repo` (プライベートリポジトリの場合)
     - `public_repo` (パブリックリポジトリの場合)
   - 有効期限を設定
   - "Generate token" をクリック

3. **トークンの設定方法**
   ```bash
   # 環境変数で設定
   export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
   
   # または実行時に直接指定
   ruby pr_review_comment_collector.rb \
     --repository owner/repo \
     --reviewer username \
     --start-date 2025-06-01 \
     --end-date 2025-06-30 \
     --token ghp_xxxxxxxxxxxxxxxxxxxx
   ```

4. **トークンの検証**
   ```bash
   # トークンが有効か確認
   curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user
   ```

### エラー: API制限またはアクセス権限がありません
- トークンの権限を確認してください
- レート制限に達している可能性があります（1時間待ってから再実行）

### エラー: リソースが見つかりません
- リポジトリ名が正しいか確認してください
- プライベートリポジトリの場合、アクセス権限があるか確認してください

### 期間内のPR数が0の場合
- 指定した期間に更新されたPRが存在しない可能性があります
- 期間を広げて再実行してみてください
- リポジトリ名が正しいか確認してください

## ライセンス

MIT License
