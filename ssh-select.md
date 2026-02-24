# ssh-select

`ssh-select` は、`~/.ssh/config` の `Host` 一覧から接続先を選び、`ssh` または `sftp` で接続する `zsh` コマンドです。

## 前提条件

- `zsh`
- `fzf`
- `ssh`（OpenSSH クライアント）
- `sftp`（OpenSSH クライアント）

## 設定ファイル

設定ファイルは固定で `~/.ssh/config` を参照します。
`Host` 行に定義されたホスト別名（エイリアス）が選択候補になります。

`Host *` や `Host web-*` のようなワイルドカード定義は候補から除外されます。

## 使い方

```zsh
ssh-select
ssh-select --mode sftp
ssh-select -m sftp
```

## オプション

- `-m ssh|sftp`, `--mode ssh|sftp`: 接続モード指定（デフォルト: `ssh`）
- `-h`, `--help`: ヘルプ表示

## 動作仕様

1. 引数を解析（`zparseopts`）
2. `~/.ssh/config` を読み込み、接続可能な `Host` 候補を抽出
3. 候補を `fzf` で選択
4. 選択したホスト別名で `ssh` または `sftp` を `exec` 実行

## 終了とエラー

- 設定ファイルが存在しない: エラー終了
- `fzf` コマンドがない: エラー終了
- 不正なモード指定: エラー終了
- 不明な引数: エラー終了
- 選択可能な `Host` 定義がない: 正常終了
- 選択をキャンセル: 正常終了（接続しない）
- `fzf` 異常終了: エラー終了

## 備考

- `User`、`HostName`、`IdentityFile` などの解決は OpenSSH (`ssh`/`sftp`) 側に委ねています。
