# aws-login

`aws-login` は、AWS プロファイルを選択して `aws sso login` を実行する `zsh` コマンドです。

## 前提条件

- `zsh`
- `aws`（AWS CLI）
- `fzf`

## 使い方

```zsh
aws-login
```

## 動作仕様

1. `aws configure list-profiles` でプロファイル一覧を取得
2. 空行を除外して候補化
3. 候補を `fzf` で選択
4. 選択したプロファイルで `AWS_PROFILE=<profile> aws sso login` を実行

## 終了とエラー

- `aws` コマンドがない: エラー終了
- `fzf` コマンドがない: エラー終了
- プロファイルが見つからない: エラー終了
- 選択をキャンセル: 正常終了（ログインしない）
- `fzf` 異常終了: エラー終了
