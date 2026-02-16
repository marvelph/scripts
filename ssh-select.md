# ssh-select

`ssh-select` は、`~/.ssh-select` に定義したサーバ一覧から `fzf` で接続先を選び、`ssh` または `sftp` で接続するコマンドです。

## 前提条件

- `python3`
- `fzf`
- `ssh`（OpenSSH クライアント）
- `sftp`（OpenSSH クライアント）

## 設定ファイル

設定ファイルは固定で `~/.ssh-select` を参照します。
フォーマットは INI 形式です。

### 必須キー

- `host`
- `user`

### 任意キー

- `identity_file`: 秘密鍵ファイルパス
- `aws_profile`: 接続時に `AWS_PROFILE` 環境変数へ設定

### 設定例

```ini
[staging]
host = ec2-xx-xx-xx-xx.ap-northeast-1.compute.amazonaws.com
user = ec2-user
identity_file = ~/.ssh/staging.pem
aws_profile = my-stg

[prod]
host = prod.example.com
user = ubuntu
identity_file = ~/.ssh/prod.pem
```

## 使い方

### SSH 接続（デフォルト）

```bash
ssh-select
```

### SFTP 接続

```bash
ssh-select --mode sftp
# または
ssh-select -m sftp
```

### モード指定

- `-m ssh`
- `-m sftp`

## 動作仕様

1. `~/.ssh-select` を読み込む
2. セクション名一覧を `fzf` で表示
3. 選択したセクションの設定で `ssh` または `sftp` を実行

実行されるコマンド形式:

- SSH: `ssh [-i identity_file] user@host`
- SFTP: `sftp [-i identity_file] user@host`

`aws_profile` が設定されている場合、実行時に `AWS_PROFILE` を付与します。

## 終了とエラー

- 設定ファイルが存在しない: エラー終了
- 設定にサーバ定義がない: 正常終了
- `host` または `user` が欠けている: エラー終了
- `fzf` が未インストール: エラー終了
- `fzf` でキャンセル（`Esc` / `Ctrl-C`）: 正常終了
- `fzf` 異常終了: エラー終了

## 備考

- INI の補間は無効化されているため、値に `%` を含んでもそのまま扱われます。
