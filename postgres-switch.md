# postgres-switch 仕様書

`postgres-switch` は、ローカル PostgreSQL の論理DB名を固定したまま、ブランチ単位でデータベース状態を切り替える CLI です。  
`main` と `develop` のように並行作業する際、毎回の再構築を避けて往復できます。

## 想定ユースケース
- `develop` 側でマイグレーションを進めている。
- 途中で `main` 側の緊急修正が必要になった。
- ブランチ往復のたびに DB を作り直したくない。

## 用語
- 論理DB名: アプリが常に接続する固定 DB 名。例: `app_db`
- current ブランチ: 現在 `論理DB名` に割り当てられているブランチ
- 退避DB: 非 current ブランチの実体。命名規則は `論理DB名__<branch>`

## ブランチ名の制約
- 使用可能文字は英数字、`-`、`_` のみ
- 退避DB名（`論理DB名__<branch>`）は PostgreSQL 識別子上限（63バイト）以内

## データベース再作成時の属性
`init` / `switch` / `branch-add` の再作成では、元DBから以下を引き継ぎます。

- `ENCODING`
- `LC_COLLATE`
- `LC_CTYPE`
- `LOCALE_PROVIDER`（利用可能な場合）
- `ICU_LOCALE`（利用可能な場合）
- `TABLESPACE`
- `OWNER`

作成時は `TEMPLATE template0` を利用し、属性を明示指定します。

## 基本方針
- 論理DB名は固定運用
- 切替後もアプリ設定上の DB 名は変更しない
- ブランチ差分は退避DB側に保持する

## 前提
- macOS / Linux で Python 3 が利用可能
- ローカル PostgreSQL サーバが動作している
- `pg_dump` と `psql` が利用可能
- `postgres-switch` を実行可能にしている
  - `chmod +x postgres-switch`

## 接続情報
- 既定では接続情報を引数で渡さない（`psql` / `pg_dump` の通常解決を利用）
- 接続先を明示する場合のみ任意引数を使う
  - `--host`
  - `--port`
  - `--user`
  - `--password`

## 設定ファイル
- パス: `~/.postgres-switch.json`
- 役割: 論理DB名ごとの current と branches を保持
- 各コマンド実行時に自動更新（手編集不要）
- 保存は一時ファイル経由の置換で実施

```json
{
  "version": 1,
  "databases": {
    "app_db": {
      "current": "main",
      "branches": ["main", "develop"]
    }
  }
}
```

## コマンド仕様
### `init --database <database> --branch <branch>`
- 既存の論理DBを管理下に追加
- `論理DB名__<branch>` を作成し、論理DB内容をコピー
- 退避DBが既に存在する場合は中止

### `branch-add --database <database> --branch <branch>`
- ブランチ追加
- current 状態を `論理DB名__<branch>` にコピー
- コピー失敗時は作成途中DBを削除して中断

### `switch --database <database> --branch <branch>`
- current ブランチ切替
- 流れ:
  - `論理DB名` を `論理DB名__<current>` に退避
  - `論理DB名__<target>` を `論理DB名` に復元
  - 設定ファイルの current 更新

### `branch-remove --database <database> --branch <branch>`
- 指定ブランチを管理対象から削除
- current ブランチは削除不可
- 実行前に確認プロンプトを表示

### `reset --database <database>`
- 指定DBの管理情報を削除
- 退避DBは残す
- 実行前に確認プロンプトを表示

### `status --database <database>`
- 指定DBの管理状態（current / branches）を表示

### `list`
- 管理対象の論理DB名を一覧表示

### `verify --database <database>`
- 設定と実DBの整合性を読み取り専用で検証
- 問題がある場合は `ERROR` を表示して非ゼロ終了

## 実装上の注意
- DBコピーは `pg_dump | psql` を使用
- PostgreSQL の DB リネーム運用に依存せず、コピー方式で一貫運用
- 再作成時に `template0` + 属性明示で、ロケールやエンコーディングの意図しない変化を防止
- `DROP DATABASE` 前に対象DBへの接続を `pg_terminate_backend` で切断

## 復旧手順（最小）
1. 管理状態と整合性を確認する。  
   `postgres-switch status --database <database>`  
   `postgres-switch verify --database <database>`
2. 論理DBと退避DBの存在を確認する。  
   `psql -d postgres -At -c "SELECT datname FROM pg_database WHERE datname LIKE '<database>%';"`
3. 失敗要因（接続・権限・容量など）を解消する。
4. 同じ `switch` を再実行する。  
   `postgres-switch switch --database <database> --branch <target>`
5. 再実行で復旧できない場合は管理情報を外して再初期化する。  
   `postgres-switch reset --database <database> --yes`  
   `postgres-switch init --database <database> --branch <branch>`
