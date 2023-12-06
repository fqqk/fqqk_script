# slack内のリアクション芸人を抽出するRuby Script

1. create slack app and get slack api token

ref: [Slack API 推奨Tokenについて](https://qiita.com/ykhirao/items/3b19ee6a1458cfb4ba21)

2. add scopes

setting User Token Scopes on AOuth & Permissions

- `reactions:read`
- [https://api.slack.com/methods/conversations.list](https://api.slack.com/methods/conversations.history)
    - `channels:history`
    - `groups:history`
    - `im:history`
    - `mpim:history`
- https://api.slack.com/methods/conversations.list
    - `channels:read`
    - `groups:read`
    - `im:read`
    - `mpim:read`
- https://api.slack.com/methods/users.info
    - `users:read`


3. install to workspace

you can get token if install success!

4. replace 'your_slack_user_oauth_token'

reaction.rb
```
SLACK_USER_OAUTH_TOKEN = 'your_slack_user_oauth_token'.freeze
```

5. execute script
```
cd your_dir/fqqk_script/slack
$ chmod +x script.sh
$ ./script.sh
```

6. result
```
【No.1】user1 is reaction_counts: 11, most_often_used_emoji: white_check_mark is 4 times
【No.2】user2 is reaction_counts: 8, most_often_used_emoji: smile is 3 times
【No.3】user3 is reaction_counts: 2, most_often_used_emoji: bow is 3 times
```