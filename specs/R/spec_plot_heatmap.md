# R関数仕様書: plot_heatmap

## 1. 概要
- **目的:** SummarizedExperiment オブジェクトのカウントデータからサンプル間の関係性を視覚化するためのヒートマップを作成する。
- **機能:** 指定されたアッセイのカウントデータに対し、ログ変換とスケーリングを行い、`pheatmap` を用いてヒートマップを描画し、指定されたディレクトリにPNGファイルとして保存する。オプションで列アノテーションを追加できる。
- **作成日:** 2025-04-25
- **更新日:** 2025-04-25

## 2. 機能詳細
- `SummarizedExperiment` オブジェクトから指定されたアッセイデータを抽出する。
- オプションで `log2(count + 1)` 変換を行う。
- オプションで行方向 (遺伝子ごと) のZ-scoreスケーリングを行う。
- `pheatmap::pheatmap` 関数を使用してヒートマップを描画する。
    - クラスタリングは行・列ともにデフォルトで有効。
    - 色は `RColorBrewer` の `RdYlBu` パレットを使用。
- `colData` から指定された列を抽出し、ヒートマップの列アノテーションとして使用する。
- 描画されたヒートマップを指定されたパスにPNGファイルとして保存する。
- この関数は、主に探索的データ解析 (EDA) や QC のステップで使用されることを想定する (`project-rule.md`)。

## 3. 入力 (Arguments)
- **se:**
    - データ型: `SummarizedExperiment`
    - 説明: 入力データオブジェクト。`assay` スロットにカウントデータ、`colData` スロットにサンプル情報が含まれている必要がある。
    - 必須/任意: 必須
- **assay_name:**
    - データ型: `character` (length 1)
    - 説明: 使用するアッセイ名 (例: `"counts"`)。`assayNames(se)` に含まれている必要がある。
    - 必須/任意: 必須
- **annotation_cols:**
    - データ型: `character` (vector) or `NULL`
    - 説明: `colData(se)` の列名のうち、ヒートマップの列アノテーションに使用する列名のベクトル。`NULL` の場合はアノテーションなし。
    - 必須/任意: 任意
    - デフォルト値: `NULL`
- **log_transform:**
    - データ型: `logical` (length 1)
    - 説明: `log2(count + 1)` 変換を行うかどうか。
    - 必須/任意: 任意
    - デフォルト値: `TRUE`
- **scale_rows:**
    - データ型: `logical` (length 1)
    - 説明: 行方向 (遺伝子ごと) にZ-scoreスケーリングを行うかどうか。`pheatmap` の `scale = "row"` に対応。
    - 必須/任意: 任意
    - デフォルト値: `TRUE`
- **cluster_rows:**
    - データ型: `logical` (length 1)
    - 説明: 行のクラスタリングを行うかどうか。
    - 必須/任意: 任意
    - デフォルト値: `TRUE`
- **cluster_cols:**
    - データ型: `logical` (length 1)
    - 説明: 列のクラスタリングを行うかどうか。
    - 必須/任意: 任意
    - デフォルト値: `TRUE`
- **output_dir:**
    - データ型: `fs::path` or `character` (length 1)
    - 説明: プロット画像を保存するディレクトリの**絶対パス**。`results/{experiment_id}/plots` などが想定される。
    - 必須/任意: 必須
- **filename_prefix:**
    - データ型: `character` (length 1)
    - 説明: 保存するファイル名のプレフィックス。`heatmap` など。
    - 必須/任意: 必須
- **logger_name:**
    - データ型: `character` (length 1)
    - 説明: `futile.logger` で使用するロガー名。`run_with_logging` ラッパーから渡される。
    - 必須/任意: 必須

## 4. 出力 (Return Value)
- データ型: `fs::path`
- 説明: 生成されたヒートマップPNGファイルの**絶対パス**。
- **ファイル出力:**
    - **ファイルパス:** `{output_dir}/{filename_prefix}{annotation_suffix}.png`
        - `{annotation_suffix}` は `_annot_{paste(annotation_cols, collapse="_")}` の形式。`annotation_cols` が `NULL` の場合は空文字列。
        - 例: `/path/to/results/exp01/plots/heatmap_annot_condition_batch.png`
    - **ファイル形式:** `PNG`
    - **ファイル内容:** `pheatmap` によって生成されたヒートマップのグラフィック。

## 5. 処理フロー / 主要ステップ
1. **入力検証:**
   - `se` が `SummarizedExperiment` であることを確認。
   - `assay_name` が `assayNames(se)` に存在することを確認。
   - `annotation_cols` が `NULL` でない場合、それらが `colnames(colData(se))` に存在することを確認。
   - `output_dir` が存在し、書き込み可能であることを確認。
2. **データ抽出:** `assay(se, assay_name)` で指定されたカウントデータを抽出。
3. **ログ変換:** `log_transform = TRUE` の場合、`log2(counts + 1)` を計算。
4. **アノテーション準備:**
   - `annotation_cols` が指定されている場合、`colData(se)` から該当する列を選択し、`data.frame` を作成。
5. **ヒートマップ描画と保存:**
   - `pheatmap::pheatmap()` を呼び出す。
     - `mat`: ログ変換後のデータ。
     - `annotation_col`: 準備したアノテーションデータフレーム (指定されている場合)。
     - `scale`: `scale_rows` が `TRUE` なら `"row"`、`FALSE` なら `"none"`。
     - `cluster_rows`, `cluster_cols`: 引数で指定された値。
     - `color`: `RColorBrewer::brewer.pal(n = 9, name = "RdYlBu")` などでカラースケールを指定。
     - `filename`: 生成するファイルパス (`{output_dir}/{filename_prefix}{annotation_suffix}.png`) を指定。**絶対パスを使用する。**
     - `width`, `height`: 必要に応じて調整。
6. **戻り値:** 生成されたPNGファイルの絶対パス (`fs::path` オブジェクト) を返す。

## 6. 副作用 (Side Effects)
- **ファイルI/O:** 指定された `output_dir` にヒートマップのPNGファイルを書き込む。
- **`SummarizedExperiment` のメタデータ更新:** この関数は入力 `se` オブジェクトを変更しないため、`pipeline_history` の更新は行わない。
- **ログ出力:** `futile.logger` を使用して、指定された `logger_name` で処理の進行状況や警告、エラーをログファイル (`logs/{experiment_id}/{logger_name}.log`) に記録する。

## 7. ログ仕様 (`futile.logger`)
- **ログファイル名:** `logs/{experiment_id}/{logger_name}.log` (例: `logs/exp01/plot_heatmap.log`)
- **主要ログメッセージ:**
    - `INFO`: 関数開始、使用するパラメータ (assay名, アノテーション列など)、データ抽出、ログ変換/スケーリングの実施、ファイル保存パス、関数終了。
    - `DEBUG`: 抽出したデータの次元数、`pheatmap` に渡すパラメータ詳細。
    - `WARN`: 指定されたアノテーション列が存在しない場合 (スキップ)、`output_dir` が存在しない場合に作成した旨など。
    - `ERROR`: 必須アッセイが存在しない、`output_dir` に書き込めない、`pheatmap` 実行中のエラーなど。
- **ログ実装例:**
  ```R
  flog.info("関数 plot_heatmap 開始: assay='%s', annotation_cols='%s'", 
            assay_name, paste(annotation_cols, collapse=", "), name = logger_name)
  # ... データ抽出 ...
  flog.debug("抽出データ: %d 行 x %d 列", nrow(mat), ncol(mat), name = logger_name)
  if (log_transform) {
    flog.info("log2(count + 1) 変換を実行します。", name = logger_name)
    mat <- log2(mat + 1)
  }
  # ... アノテーション準備 ...
  if (!is.null(annotation_cols)) {
      flog.info("列アノテーションを準備: %s", paste(annotation_cols, collapse=", "), name = logger_name)
      # ... data.frame作成 ...
  }
  output_path <- file.path(output_dir, filename) # filename は構築済みとする
  flog.info("ヒートマップをファイルに保存: %s", output_path, name = logger_name)
  tryCatch({
      pheatmap::pheatmap(mat, ..., filename = output_path)
  }, error = function(e) {
      flog.error("pheatmap描画中にエラーが発生: %s", conditionMessage(e), name = logger_name)
      stop(e)
  })
  flog.info("関数 plot_heatmap 終了", name = logger_name)
  ```

## 8. テストケース (`testthat`)
- **テストファイル:** `tests/testthat/test-plot_heatmap.R`
- **テスト項目:**
    - **正常系:**
        - アノテーションなしで実行し、PNGファイルが生成されることを確認。
        - 1つまたは複数の有効な `annotation_cols` を指定し、アノテーション付きPNGファイルが生成されることを確認。
        - `log_transform = FALSE`, `scale_rows = FALSE` で実行した場合の結果を確認 (目視またはスナップショットテスト)。
        - `cluster_rows = FALSE`, `cluster_cols = FALSE` で実行した場合の結果を確認。
    - **異常系:**
        - `assay_name` が存在しない場合にエラーが発生することを確認。
        - `annotation_cols` に存在しない列名が含まれる場合に警告が出て、処理は続行される (またはエラーにするか要検討) ことを確認。
        - `output_dir` が存在しない場合にエラーが発生する (または作成するか要検討) ことを確認。
        - 入力 `se` が `SummarizedExperiment` でない場合にエラー。
        - カウントデータが数値でない場合にエラー。
    - **副作用:**
        - 指定されたパスに期待されるファイル名のPNGファイルが実際に生成されていることを確認 (`expect_true(file.exists(...))`)。
        - 返り値が生成されたファイルの絶対パス (`fs::path`) であることを確認。
- **テストデータ:** `tests/testdata/plot_heatmap/` に、少数の遺伝子とサンプルを含む `SummarizedExperiment` オブジェクト (RDS形式) と、期待される出力ファイル名のパターンを用意する。

## 9. 依存関係
- **R パッケージ:** `SummarizedExperiment`, `pheatmap`, `RColorBrewer`, `futile.logger`, `fs`, `dplyr` (アノテーション処理用)
- **自作関数:** なし
- `renv` で管理される。 