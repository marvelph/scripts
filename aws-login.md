# aws-login

`aws-login` は、AWS プロファイルを選択して `aws sso login` を実行するコマンドです。

## 前提条件

- `bash`
- `aws`（AWS CLI）
- `fzf`（任意。未導入時は番号選択にフォールバック）

## 使い方

```bash
aws-login
```

## 動作仕様

1. `aws configure list-profiles` でプロファイル一覧を取得
2. `AWS_CONFIG_FILE`（未設定時は `~/.aws/config`）を読み、SSO 設定を持つプロファイルを優先抽出
3. 候補を選択 UI で表示（`fzf` 優先、未導入時は番号選択）
4. 選択したプロファイルで `AWS_PROFILE=<profile> aws sso login` を実行

## 終了とエラー

- `aws` コマンドがない: エラー終了
- プロファイルが見つからない: エラー終了
- 選択をキャンセル: 正常終了（ログインしない）
- `fzf` 異常終了: エラー終了

