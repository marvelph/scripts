# mysql-switch 仕様書

`mysql-switch` は、ローカル MySQL のデータベース状態をブランチ単位で切り替えるための CLI です。  
主な目的は、`master` と `develop` のようにスキーマ進化が異なる作業を、テーブル再作成なしで往復できるようにすることです。

## 想定ユースケース
- 開発途中で `develop` 側にスキーマ変更を入れた。
- その最中に `master` 側でバグ修正が必要になった。
- ブランチを行き来するたびにマイグレーションや初期データ投入をやり直したくない。

このとき、ブランチごとの「スキーマ + データ」を保持して即時に切り替える運用を行います。

## 用語
- 論理DB名: アプリが通常接続する DB 名。例: `app_db`
- current ブランチ: 現在 `論理DB名` に割り当てられているブランチ
- 退避DB: 非 current ブランチの実体。命名規則は `論理DB名__<branch>`

## ブランチ名の制約
- 使用可能文字は英数字、`-`、`_` のみ。
- 退避DB名（`論理DB名__<branch>`）が MySQL のDB名上限（64文字）を超える場合はエラー。

## データベース再作成時の属性
- `init` / `switch` / `branch-add` の再作成では、元DBの `DEFAULT CHARACTER SET` と `DEFAULT COLLATE` を引き継ぐ。
- これにより、再作成時にサーバ既定値へ意図せず戻ることを防ぐ。

## 基本方針
- 論理DB名は固定で運用する。
- ブランチ切替時も、アプリ設定上の DB 名は変えない。
- ブランチごとの差分は退避DB側に保持する。

## 前提
- macOS / Linux で Python 3 が利用可能
- ローカル MySQL サーバが動作している
- `mysqldump` と `mysql` コマンドが利用可能
- `mysql-switch` を実行可能にしている
  - `chmod +x mysql-switch`

## 接続情報
- 既定では接続情報を引数で渡さない。
- そのため、`mysql` / `mysqldump` の通常解決（例: `~/.my.cnf`）を利用できる。
- 接続先を明示したい場合のみ、次の任意引数を使う。
  - `--host`
  - `--port`
  - `--user`
  - `--password`

## 設定ファイル
- パス: `~/.mysql-switch.json`
- 役割: 論理DB名ごとの current ブランチと管理ブランチ一覧を保持
- 手書き編集は不要。`init` / `branch-add` / `switch` / `branch-remove` / `reset` の実行時に自動で作成・更新される
- 保存は一時ファイル経由の置換で行い、部分書き込みによる破損を避ける

```json
{
  "databases": {
    "app_db": {
      "current": "master",
      "branches": ["master", "develop"]
    }
  }
}
```

## コマンド仕様
### `init --database <database> --branch <branch>`
- 既存の論理DB名を管理下に追加する。
- 途中導入を想定したコマンド。
- `論理DB名__<branch>` の初期退避DBを作成し、論理DBの内容をコピーする。
- 初期退避DBが既に存在する場合は中止する。
- 例: `mysql-switch init --database app_db --branch master`

### `branch-add --database <database> --branch <branch>`
- ブランチを追加する。
- 追加時の起点は「空DB」ではなく current 状態のコピーを基本とする。
- 追加後は `論理DB名__<branch>` の退避DBとして保持する。
- コピーに失敗した場合は、作成途中の退避DBを削除して中断する。
- 例: `mysql-switch branch-add --database app_db --branch develop`

### `switch --database <database> --branch <branch>`
- current ブランチを切り替える。
- 切替イメージ:
  - 現在の `論理DB名` を `論理DB名__<current>` として退避
  - `論理DB名__<target>` を `論理DB名` に昇格
  - 設定ファイルの current を更新
- `論理DB名__<current>` と `論理DB名__<target>` が存在しない場合は中止する。
- 例: `mysql-switch switch --database app_db --branch develop`

### `branch-remove --database <database> --branch <branch>`
- 指定ブランチを管理対象から削除する。
- current ブランチは削除不可。
- 実行前に確認プロンプトを表示する。
- 例: `mysql-switch branch-remove --database app_db --branch develop`

### `reset --database <database>`
- 指定DBの管理情報を削除する。
- 原則として退避DBは残す（必要に応じて別途削除）。
- 実行前に確認プロンプトを表示する。
- 例: `mysql-switch reset --database app_db`

### `status --database <database>`
- 指定した論理DBの管理状態（current / branches）を表示する。
- 例: `mysql-switch status --database app_db`

### `list`
- 管理対象の論理DB名のみを一覧表示する。
- 例: `mysql-switch list`

## 運用イメージ
### 初期状態 (`master`)
- `app_db` が `master` の状態を保持
- current = `master`

### `develop` 追加
- `mysql-switch branch-add --database app_db --branch develop`
- `app_db__develop` は `app_db` のコピーから作成
- これで両ブランチの作業開始点を揃えられる

### `develop` へ切替
- `mysql-switch switch --database app_db --branch develop`
- `app_db` は `develop` の状態になる
- `master` 側の状態は `app_db__master` として保持される

## 設計上の意図
- 開発の最初から厳密分離するためのツールではなく、途中導入して運用を分岐させるためのツール。
- `master` / `develop` を往復しても、毎回の再構築を避けて作業効率を維持する。

## 障害時の扱い（実運用メモ）
- `switch` 失敗時は、まずディスク容量や接続状態を解消してから再実行する。
- 前段（`current` の退避コピー）で失敗した場合:
  - 論理DB（current）は通常そのまま残る。
  - 退避DBは壊れている可能性があるが、再実行で再作成できる。
- 後段（切替先退避DBから論理DBへのコピー）で失敗した場合:
  - 論理DBが空/不完全になる可能性がある。
  - 仕組みを理解した上での復旧が難しければ、管理情報を削除してデータベースを再作成する。

## 復旧手順（最小）
1. 管理状態を確認する。  
   `mysql-switch status --database <database>`
2. 論理DBと退避DBの存在を確認する。  
   `mysql -N -e "SHOW DATABASES LIKE '<database>%';"`
3. 失敗要因（容量不足・接続不良など）を解消する。
4. 同じ `switch` を再実行する。  
   `mysql-switch switch --database <database> --branch <target>`
5. 再実行で復旧できない場合は、管理情報を外して再初期化する。  
   `mysql-switch reset --database <database> --yes`  
   `mysql-switch init --database <database> --branch <branch>`
