# create_se モジュール仕様書

## ターゲット情報

### ターゲット名
`obj_se_raw`

### 目的
このモジュールは、RNA-seq解析パイプラインの開始点として、指定されたカウントデータファイルとサンプルメタデータファイルから基本的な`SummarizedExperiment` (SE) オブジェクトを作成します。また、`biomaRt`を使用して遺伝子アノテーション情報を取得し、SEオブジェクトに付加します。

### 入力ターゲット
- **依存ターゲット名**: なし (パイプラインの最初のモジュール)
- **SE オブジェクトの期待状態**: なし
- **その他の入力ファイル**:
  - `params$counts_file_path`: カウントデータファイルへのパス（CSV形式を想定、遺伝子ID列とサンプル列を含む）。`_targets.R`で`experiment_id`に基づいて決定される想定。
  - `params$metadata_file_path`: サンプルメタデータファイルへのパス（CSV形式を想定、サンプルID列を含む）。`_targets.R`で`experiment_id`に基づいて決定される想定。

### 実行コマンド/処理
- **関連する Rmd ファイル名**: `Rmd/create_se.Rmd`
- **主要な処理ステップ**:
  1. 入力ファイル（カウントデータ、メタデータ）の存在確認と読み込み (`readr::read_csv`)。
  2. データの整合性チェック（必須列の存在、サンプルIDの一致確認）。
  3. メタデータのサンプル順序をカウントデータの列順序に合わせる。
  4. カウントデータから遺伝子IDを抽出し、バージョン情報を削除 (`stringr::str_replace`)。
  5. `biomaRt`に接続し、指定された遺伝子ID (`params$biomart_dataset`, `params$biomart_attributes`) のアノテーション情報を取得 (`biomaRt::useMart`, `biomaRt::getBM`)。
  6. 取得したアノテーション情報を前処理し、元の遺伝子IDにマッピング (`dplyr::left_join`)、`rowData`用の`DataFrame`を作成 (`S4Vectors::DataFrame`)。
  7. `SummarizedExperiment`オブジェクトを作成 (`SummarizedExperiment::SummarizedExperiment`)。
  8. SEオブジェクトのメタデータに実験ID (`params$experiment_id`) とパイプライン実行履歴を記録 (`record_pipeline_history`ユーティリティ関数)。
  9. SEオブジェクトの基本情報と内容を表示。
  10. 遺伝子タイプ (gene_biotype) の分布を集計・可視化。
  11. protein_coding遺伝子の詳細分析を実施。
  12. サンプルごとのprotein_coding遺伝子のライブラリサイズをbar plotで比較。
  13. サンプル間の発現量分布をdensity plotで比較し、データの品質とばらつきを視覚的に評価。
  14. セッション情報の表示。
- **主要なパッケージ/関数**:
  - `SummarizedExperiment`, `S4Vectors`
  - `readr`, `dplyr`, `stringr`, `tibble`
  - `fs`, `here`
  - `futile.logger`, `cli`
  - `biomaRt`
  - `knitr`, `DT`, `ggplot2` (レポート表示・可視化用)
  - `R/utility.R` 内の関数 (`setup_logger`, `record_pipeline_history`)
- **主要パラメータ**:
  - `params$experiment_id`: 実験ID (必須、レポートタイトル、ログファイルパス、メタデータ記録に使用)
  - `params$counts_file_path`: カウントデータファイルパス (必須)
  - `params$metadata_file_path`: メタデータファイルパス (必須)
  - `params$gene_id_column`: カウントデータ内の遺伝子ID列名 (デフォルト: "gene_id")
  - `params$sample_id_column`: メタデータ内のサンプルID列名 (デフォルト: "sample_id")
  - `params$biomart_host`: biomaRtホストURL (デフォルト: "https://ensembl.org")
  - `params$biomart_dataset`: biomaRtデータセット名 (必須)
  - `params$biomart_attributes`: biomaRtで取得する属性リスト (デフォルトは "ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype")
  - `params$module_name`: モジュール名（"create_se"、ログと履歴記録に使用）
- **SE オブジェクトのメタデータ更新**:
  - `metadata(se)$experiment_id`: `params$experiment_id` を記録。
  - `metadata(se)$pipeline_history[['create_se']]` に以下の情報を記録 (`record_pipeline_history`経由):
    - `module_name`: "create_se"
    - `description`: "SummarizedExperiment オブジェクト作成"
    - `execution_time`: 実行日時
    - `parameters`: 上記の主要パラメータのリスト

### 必須ロギング要件
- **ロガー名**: `create_se`
- **ログファイル**: `logs/{experiment_id}/create_se.log`
- **ログ設定**:
  - セットアップチャンクで`setup_logger`関数を用いてロガー設定（`include=FALSE`）。
  - `futile.logger`パッケージを使用。
  - ログはファイルにのみ出力し、レンダリング出力には表示しない。
- **ログレベル**:
  - `TRACE`: パラメータ詳細、データの一部（head）、デバッグ中の変数内容。
  - `DEBUG`: ファイルパス確認、データ読み込み/操作のステップ、列名変更、biomaRt接続、DataFrame変換など。
  - `INFO`: モジュール/処理ブロックの開始/終了、読み込んだデータの次元、サンプルID一致状況、biomaRt取得レコード数、SEオブジェクト作成成功、メタデータ記録完了。
  - `WARN`: サンプルID不一致、biomaRtアノテーションのNA値。
  - `ERROR`: ファイルが見つからない、ファイルの読み込み失敗、必須列の欠損、biomaRt接続/取得エラー、SEオブジェクト作成失敗。
- **記録すべき主要情報**:
  - 実行開始/終了、PID
  - 入力パラメータ値
  - 入力ファイルの存在確認結果とパス
  - 読み込んだカウントデータとメタデータの次元
  - カウントデータとメタデータのサンプルIDの一致/不一致状況
  - biomaRt接続先、クエリに使用する遺伝子ID数、取得したアノテーションのレコード数と列名
  - rowDataのマッピングと作成結果、NA値の存在状況
  - 作成されたSEオブジェクトの次元、assay/colData/rowDataの列名
  - メタデータへの履歴記録の実行

## 出力情報

### 出力ターゲット
- **生成されるオブジェクト名**: `obj_se_raw`
- **出力される SE オブジェクトの期待状態**:
  - **assays**: `counts` (数値マトリックス、行名はバージョン付き遺伝子ID、列名はサンプルID)
  - **colData**: `DataFrame` (行名はサンプルID)。`params$metadata_file_path` から読み込まれた情報を含み、列順序は `assays$counts` の列順序と一致。`params$sample_id_column` を含む。
  - **rowData**: `DataFrame` (行名はバージョン付き遺伝子ID)。`biomaRt`から取得された遺伝子アノテーション情報を含む。最低限 `ensembl_gene_id` (バージョンなし) を含み、`params$biomart_attributes` で指定された他の属性 (例: `gene_name`、`gene_length`、`gene_biotype`) も含む。
  - **metadata**:
    - `experiment_id`: `params$experiment_id` の値。
    - `pipeline_history`: `create_se` の実行履歴を含むリスト。

### 生成ファイル
- **プロット**:
  - 遺伝子タイプ (gene_biotype) の分布を示すバープロット
  - サンプルごとのprotein_coding遺伝子のライブラリサイズを比較するバープロット
  - サンプル間の発現量分布を比較するdensity plot (log2スケール)
- **テーブル**:
  - カウントデータの基本情報
  - サンプルメタデータの基本情報
  - 作成されたSEオブジェクトの概要
  - 遺伝子タイプの分布テーブル
  - protein_coding遺伝子の統計情報
  - サンプルごとのprotein_coding遺伝子のライブラリサイズ
  - protein_coding遺伝子のライブラリサイズの統計情報
- **レポート**:
  - `results/{experiment_id}/reports/create_se.html` (HTMLレポート)
  - `results/{experiment_id}/reports/create_se.md` (Markdownレポート、HTMLと共に生成)
  - **出力形式**: `_targets.R`で定義された共通出力設定が適用される想定。

## レポート要件
- **出力形式**:
  - `knitr::opts_chunk$set` で以下のオプションを設定: `echo = FALSE`, `warning = FALSE`, `message = FALSE`, `fig.width = 10`, `fig.height = 6`, `dpi = 300`
  - 処理チャンクは基本的に `include=FALSE` に設定し、レポートには結果のみを表示
- **含めるべき図表**:
  - 遺伝子タイプ (gene_biotype) の分布バープロット
  - サンプルごとのprotein_coding遺伝子のライブラリサイズ比較バープロット
  - サンプル間の発現量分布を比較するdensity plot (生データおよびlog2変換データ)
  - DT::datatableによるインタラクティブテーブル表示
    - カウントデータの最初の10行
    - サンプルメタデータの最初の10行
    - assay("counts")の最初の10行
    - colData全体
    - rowDataの最初の20行
- **含めるべき統計情報**:
  - 入力カウントデータとメタデータの基本情報（次元、ID列名など）
  - 作成されたSEオブジェクトの概要（次元、assay/colData/rowData列名、メタデータ項目）
  - 遺伝子タイプの分布統計
  - protein_coding遺伝子の統計（数、割合、アノテーション欠損状況）
  - サンプルごとのライブラリサイズと統計情報
  - 発現量分布の統計的比較（分布の中央値、四分位範囲など）
- **テキスト概要**:
  - モジュールの目的と処理概要の説明。
  - 入力ファイルのパス。
  - 実行した処理の各ステップの説明。
  - サンプル間の発現量分布比較の解釈と品質評価。
  - `sessionInfo()` による再現性のための情報。

## テスト要件
- **テストファイル**: `tests/test-create_se.R` (想定)
- **テスト方法**: `testrmd`パッケージを使用 (推奨)
- **テスト内容**:
  - 正常な入力に対するSEオブジェクト作成の成功確認。
  - 出力SEオブジェクトの構造検証 (`assays`, `colData`, `rowData` の存在と次元、期待される列名)。
  - `colData`と`assays`のサンプル順序の一致確認。
  - `rowData`と`assays`の遺伝子順序の一致確認。
  - `metadata` (`experiment_id`, `pipeline_history`) が正しく記録されているかの検証。
  - 不正な入力（ファイル欠損、列名不一致、サンプルID不一致）に対するエラーハンドリングのテスト。
  - biomaRt接続失敗時のエラーハンドリングテスト。
- **テスト実装手順**:
  1. Red: 失敗するテストコード (`testrmd::test_rmd`) を記述。
  2. Green: テストをパスする最小限のコードを `Rmd/create_se.Rmd` に実装。
  3. Refactor: コードを最適化。

## その他
- **エラーハンドリング**:
  - 入力ファイルの欠損、読み込みエラー、必須列の欠損、サンプルIDの不一致（`stop()`または`flog.error()`で処理）。
  - biomaRt接続・取得エラー (`tryCatch()`を使用し、エラー時は`stop()`または`flog.error()`で処理)。
  - SEオブジェクト作成時のエラー (`tryCatch()`を使用し、エラー時は詳細なログを出力して`stop()`で処理)。
  - アノテーションデータのNA値に対する警告と処理の継続。
- **特別な制約**:
  - インターネット接続が必要 (`biomaRt`を使用するため)。
  - `R/utility.R` 内の関数 (`setup_logger`, `record_pipeline_history`) に依存。
- **注意事項**:
  - `_targets.R` でファイルパス (`counts_file_path`, `metadata_file_path`) や `biomart_dataset` が適切に設定されている必要がある。
  - コード内のコメントは日本語で記述されている。
  - `sessionInfo()` はレポートの最後に含まれる。
  - 複数のデータ整合性チェックと警告が実装されている（サンプルID不一致、アノテーションのNA値など）。
  - protein_coding遺伝子の分析は条件に応じて実行され、gene_biotypeが存在しない場合は適切なメッセージが表示される。
  - サンプル間の発現量分布比較は、データ品質評価の重要な指標となり、バッチ効果の初期判定にも役立つ。 