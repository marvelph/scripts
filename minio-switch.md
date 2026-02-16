# minio-switch 仕様書

`minio-switch` は、MinIO の論理バケットを固定したまま、ブランチ単位でオブジェクト状態を切り替える CLI です。  
`main` と `develop` の作業状態をバケットごとに保持し、再同期コストを下げます。

## 想定ユースケース
- `develop` 側で検証用オブジェクトを追加している。
- 途中で `main` 側の障害調査に戻る必要がある。
- バケットを毎回手作業で作り直したくない。

## 用語
- 論理バケット名: アプリが通常アクセスする固定バケット名。例: `app-assets`
- current ブランチ: 現在、論理バケットに割り当てられているブランチ
- 退避バケット: 非 current ブランチの実体バケット。命名規則は `<bucket>--<branch>`

## 基本方針
- 論理バケット名は固定運用する。
- 切替後もアプリ側のバケット設定は変えない。
- ブランチごとの差分は退避バケット側に保持する。

## 前提
- macOS / Linux で Python 3 が利用可能
- MinIO サーバが動作している
- `mc` (MinIO Client) が利用可能
- `mc alias set` で接続先 alias を作成済み
- `minio-switch` を実行可能にしている
  - `chmod +x minio-switch`

## ブランチ名制約
- 許可文字: 小文字英字 (`a-z`), 数字 (`0-9`), ハイフン (`-`)
- 正規表現: `^[a-z0-9-]+$`
- `/` や `_` は使用不可
- 文字数: 1 文字以上
- 退避バケット名は `<bucket>--<branch>` で生成され、全体で 63 文字以内が必要
- そのため実効上の `branch` 最大長は `63 - len(bucket) - 2`

## 接続情報
- `--alias` で `mc` の alias 名を指定する（既定: `local`）。
- コマンド例: `minio-switch --alias local list`

## 設定ファイル
- パス: `~/.minio-switch.json`
- 役割: `alias/bucket` ごとの current / branches を保持
- 手編集は不要。各コマンド実行時に自動更新される

```json
{
  "version": 1,
  "buckets": {
    "local/app-assets": {
      "current": "main",
      "branches": ["main", "develop"]
    }
  }
}
```

## コマンド仕様
### `init --bucket <bucket> --branch <branch>`
- 既存の論理バケットを管理下に追加する。
- 退避バケット `<bucket>--<branch>` を作成し、現在の論理バケット内容をコピーする。
- 退避バケットが既に存在する場合は安全のため中止する。
- 例: `minio-switch --alias local init --bucket app-assets --branch main`

### `branch-add --bucket <bucket> --branch <branch>`
- ブランチを追加する。
- 追加時は current 状態を退避バケットにコピーする。
- 例: `minio-switch --alias local branch-add --bucket app-assets --branch develop`

### `switch --bucket <bucket> --branch <branch>`
- current ブランチを切り替える。
- 切替イメージ:
  - 現在の論理バケットを `論理バケット--<current>` に退避
  - `論理バケット--<target>` を論理バケットへ復元
  - 設定ファイルの current を更新
- 例: `minio-switch --alias local switch --bucket app-assets --branch develop`

### `branch-remove --bucket <bucket> --branch <branch>`
- 指定ブランチを管理対象から削除する。
- current ブランチは削除不可。
- 実行前に確認プロンプトを表示する。
- 例: `minio-switch --alias local branch-remove --bucket app-assets --branch main`

### `reset --bucket <bucket>`
- 指定バケットの管理情報を削除する。
- 退避バケットは残す。
- 実行前に確認プロンプトを表示する。
- 例: `minio-switch --alias local reset --bucket app-assets`

### `status --bucket <bucket>`
- 指定した `alias/bucket` の管理状態（current / branches）を表示する。
- 例: `minio-switch --alias local status --bucket app-assets`

### `list`
- 管理対象キー（`alias/bucket`）を一覧表示する。
- 例: `minio-switch --alias local list`

## 実装上の注意
- オブジェクトコピーは `mc mirror --overwrite --remove` を使用。
- `switch` / `branch-add` ではバケットを再作成しない（既存バケット設定を維持する）。
- `switch` は次の順序で実行する。
  1. current 側退避バケットの存在を確認
  2. target 側退避バケットの存在を確認
  3. 論理バケット -> current 退避へミラー
  4. target 退避 -> 論理バケットへミラー
- 途中失敗時は、論理バケットが空/不完全になる可能性があるため、`status` と `mc ls` で状態確認して再実行する。

## 運用イメージ
1. `main` で初期化  
   `minio-switch --alias local init --bucket app-assets --branch main`
2. `develop` を追加  
   `minio-switch --alias local branch-add --bucket app-assets --branch develop`
3. `develop` へ切替  
   `minio-switch --alias local switch --bucket app-assets --branch develop`
4. 不要ブランチを削除  
   `minio-switch --alias local branch-remove --bucket app-assets --branch main --yes`
