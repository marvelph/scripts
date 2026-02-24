# aws-switch.sh

`aws-switch.sh` は、`aws-switch` 関数を定義して `AWS_PROFILE` を切り替えるための `zsh` 用スクリプトです。

このファイルは **実行ではなく `source` 前提** です。

## 前提条件

- `zsh`
- `aws`（AWS CLI）
- `fzf`

## 使い方

```zsh
source /Users/marvelph/Developer/Projects/scripts/aws-switch.sh
aws-switch
```

## 動作仕様

1. `aws configure list-profiles` でプロファイル一覧を取得
2. 空行を除外して候補化
3. 候補を `fzf` で選択
4. 選択したプロファイルを `AWS_PROFILE` に `export`

## 終了とエラー

- `aws` コマンドがない: エラー終了（関数は `return 1`）
- `fzf` コマンドがない: エラー終了（関数は `return 1`）
- プロファイル一覧の取得に失敗: エラー終了（関数は `return 1`）
- プロファイルが見つからない: エラー終了（関数は `return 1`）
- 選択をキャンセル: 正常終了（`AWS_PROFILE` は変更しない）
- `fzf` 異常終了: エラー終了（関数は `return 1`）
