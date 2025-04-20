# RNA-seqパイプラインのためのユーティリティ関数仕様書

## 共通ユーティリティモジュール仕様

### パッケージ依存関係
- futile.logger: ロギング機能
- fs: ファイルシステム操作
- here: プロジェクトルートからの相対パス
- SummarizedExperiment: 実験データの管理

## 1. appender_tee_custom - 複数ファイルへのログ出力

### 機能概要
2つのファイルアペンダーに同時にログを書き込むカスタムアペンダー関数。
futile.logger はデフォルトで複数のファイルアペンダーを直接サポートしないため、
この関数を介して複数のログファイルに同じメッセージを書き込む。

### 引数
- file1_appender: 1つ目の appender.file() で作成されたアペンダー関数
- file2_appender: 2つ目の appender.file() で作成されたアペンダー関数

### 戻り値
- function: futile.logger が期待するアペンダー関数

### 使用例
```r
module_appender <- futile.logger::appender.file("module.log")
targets_appender <- futile.logger::appender.file("_targets.log")
tee_appender <- appender_tee_custom(module_appender, targets_appender)
futile.logger::flog.appender(tee_appender)
```

### エラー処理
- いずれかのファイルへの書き込みが失敗した場合は警告を発し、他方のファイルへの
  書き込みは継続する
- 引数が関数でない場合はエラーを発生させる

## 2. setup_logger - Rmdモジュール用ロガー設定

### 機能概要
Rmdモジュール用のロガーを設定する関数。モジュール固有のログファイルと
_targets.log の両方にログを出力するよう設定する。モジュール名はログメッセージの
一部として含まれ、ソースを識別しやすくする。

### 引数
- module_name: モジュール名 (例: "create_se")
- experiment_id: 実験ID (例: "250418_RNA-seq")
- log_level: ログレベル (デフォルト: "TRACE")

### 戻り値
- list: ロガー設定を含むリスト
  - appender: 設定済みのアペンダー関数
  - layout: 設定済みのレイアウト関数
  - threshold: 設定されたログレベル閾値
  - module_log_path: モジュールログファイルの絶対パス

### 使用例
```r
# Rmd内での使用例
logger_settings <- setup_logger("create_se", params$experiment_id)
futile.logger::flog.appender(logger_settings$appender)
futile.logger::flog.layout(logger_settings$layout)
futile.logger::flog.threshold(logger_settings$threshold)
futile.logger::flog.info("ロガー設定適用完了")
```

### ログ出力形式
- 標準形式: "[タイムスタンプ] [ログレベル] [モジュール名] メッセージ"
  例: "[2023-05-01 12:34:56] [INFO] [create_se] 処理を開始します"

### ログファイルパス
- モジュールログ: logs/{experiment_id}/{module_name}.log
- ターゲットログ: logs/{experiment_id}/_targets.log

### エラー処理
- 無効なログレベルが指定された場合は警告を発し、TRACEレベルを使用
- ログディレクトリが存在しない場合は自動作成

## 3. record_pipeline_history - パイプライン実行履歴の記録

### 機能概要
SummarizedExperiment オブジェクトのパイプライン履歴にモジュール実行情報を記録する。
各モジュールの実行状況、パラメータ、実行時間等を追跡するために使用する。

### 引数
- se: SummarizedExperiment オブジェクト
- module_name: モジュール名
- description: モジュールの説明
- parameters: パラメータのリスト

### 戻り値
- SummarizedExperiment: 更新されたSEオブジェクト

### 使用例
```r
# Rmd内での使用例
se <- record_pipeline_history(se, "create_se", "SEオブジェクト作成", params)
```

### 記録内容
metadata(se)$pipeline_history に以下の情報を記録:
- module: モジュール名
- timestamp: 実行日時
- description: モジュールの説明
- parameters: 使用されたパラメータ
- session_info: 実行環境情報(sessionInfo()の出力)

### 特記事項
- 初回実行時はpipeline_historyリストを初期化
- 同一モジュール名での複数回実行時は上書き 