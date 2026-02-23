# ssh-select

`ssh-select` は、`~/.ssh/config` の `Host` 一覧から接続先を選び、`ssh` または `sftp` で接続するコマンドです。

## 前提条件

- `bash`
- `fzf`（任意。未導入時は番号選択にフォールバック）
- `ssh`（OpenSSH クライアント）
- `sftp`（OpenSSH クライアント）

## 設定ファイル

設定ファイルは固定で `~/.ssh/config` を参照します。
フォーマットは OpenSSH の設定形式です。

`Host` 行に定義されたホスト別名（エイリアス）が選択候補になります。

次のような具体的なホスト名のみ候補になります。

### 設定例

```sshconfig
Host staging
  HostName ec2-xx-xx-xx-xx.ap-northeast-1.compute.amazonaws.com
  User ec2-user
  IdentityFile ~/.ssh/staging.pem

Host prod
  HostName prod.example.com
  User ubuntu
  IdentityFile ~/.ssh/prod.pem
```

`Host *` や `Host web-*` のようなワイルドカード定義は候補から除外されます。

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

1. `~/.ssh/config` を読み込む
2. `Host` 一覧を選択 UI で表示（`fzf` 優先、未導入時は番号選択）
3. 選択したホスト別名で `ssh` または `sftp` を実行

実行されるコマンド形式:

- SSH: `ssh host_alias`
- SFTP: `sftp host_alias`

## 終了とエラー

- 設定ファイルが存在しない: エラー終了
- 選択可能な `Host` 定義がない: 正常終了
- 選択をキャンセル: 正常終了（接続しない）
- `fzf` でキャンセル（`Esc` / `Ctrl-C`）: 正常終了
- `fzf` 異常終了: エラー終了

## 備考

- `User`、`HostName`、`IdentityFile` などの解決は OpenSSH (`ssh`/`sftp`) 側に委ねています。
