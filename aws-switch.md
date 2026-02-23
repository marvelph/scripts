# aws-switch.sh

`aws-switch.sh` は、`aws-switch` シェル関数を定義して `AWS_PROFILE` を切り替えるためのスクリプトです。

## 前提条件

- `bash` または `zsh`
- `aws`（AWS CLI）
- `fzf`（任意。未導入時は番号選択にフォールバック）

## 使い方

```bash
source /Users/marvelph/Developer/Projects/scripts/aws-switch.sh
aws-switch
```

## 動作仕様

1. `aws configure list-profiles` でプロファイル一覧を取得
2. 候補を選択 UI で表示（`fzf` 優先、未導入時は番号選択）
3. 選択したプロファイルを `AWS_PROFILE` に `export`

## 終了とエラー

- `aws` コマンドがない: エラー終了（関数は `return 1`）
- プロファイルが見つからない: エラー終了（関数は `return 1`）
- 選択をキャンセル: 正常終了（`AWS_PROFILE` は変更しない）
- `fzf` 異常終了: エラー終了（関数は `return 1`）

