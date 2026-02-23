# ssh-add-select

`ssh-add-select` は、`~/.ssh/config` の `IdentityFile` 一覧から鍵ファイルを選択して `ssh-add` を実行するコマンドです。

## 前提条件

- `bash`
- `ssh-add`（OpenSSH クライアント）
- `fzf`（任意。未導入時は番号選択にフォールバック）

## 設定ファイル

設定ファイルは固定で `~/.ssh/config` を参照します。
フォーマットは OpenSSH の設定形式です。

`IdentityFile` 行に定義された鍵ファイルパスが選択候補になります。

## 使い方

```bash
ssh-add-select
```

## 動作仕様

1. `~/.ssh/config` を読み込む
2. `IdentityFile` 一覧を抽出する
3. `~` で始まるパスを展開し、重複を除去して候補化
4. 候補を選択 UI で表示（`fzf` 優先、未導入時は番号選択）
5. 選択した鍵ファイルで `ssh-add <key_path>` を実行

## 終了とエラー

- `ssh-add` コマンドがない: エラー終了
- 設定ファイルが存在しない: エラー終了
- `IdentityFile` が見つからない: 正常終了
- 選択をキャンセル: 正常終了（`ssh-add` しない）
- `fzf` 異常終了: エラー終了

## 備考

- `%` を含む `IdentityFile`（OpenSSH トークンを使うパス）は候補から除外します。
- 相対パスの `IdentityFile` は `HOME` 基準に正規化して扱います。
