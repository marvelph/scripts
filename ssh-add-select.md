# ssh-add-select

`ssh-add-select` は、`~/.ssh/config` の `IdentityFile` 一覧から鍵ファイルを選択して `ssh-add` を実行する `zsh` コマンドです。

## 前提条件

- `zsh`
- `ssh-add`（OpenSSH クライアント）
- `fzf`

## 設定ファイル

設定ファイルは固定で `~/.ssh/config` を参照します。
`IdentityFile` 行に定義された鍵ファイルパスが選択候補になります。

## 使い方

```zsh
ssh-add-select
```

## 動作仕様

1. `~/.ssh/config` を読み込む
2. `IdentityFile` 一覧を抽出する
3. パスを正規化して重複を除去する
4. 候補を `fzf` で表示して選択
5. 選択した鍵ファイルで `ssh-add <key_path>` を実行

## 終了とエラー

- `ssh-add` コマンドがない: エラー終了
- `fzf` コマンドがない: エラー終了
- 設定ファイルが存在しない: エラー終了
- `IdentityFile` が見つからない: 正常終了
- 選択をキャンセル: 正常終了（`ssh-add` しない）
- `fzf` 異常終了: エラー終了

## 備考

- `%` を含む `IdentityFile`（OpenSSH トークンを使うパス）は候補から除外します。
- `~` で始まるパスは `HOME` に展開します。
- 相対パスは `HOME` 基準に正規化して扱います。
