# R関数仕様書: plot_library_size

## 1. 概要
- **目的:** SummarizedExperiment オブジェクトの指定されたアッセイデータからサンプルごとのライブラリサイズ (合計カウント数) を計算し、バープロットとして可視化してファイルに保存する。
- **機能:** ライブラリサイズの計算、ggplot2によるバープロット作成、プロットのファイル保存、ファイルパスの返却。
- **作成日:** 2024-08-01
- **更新日:** 2024-08-01

## 2. 機能詳細
- 指定されたアッセイ (通常は raw counts) の列合計を計算し、ライブラリサイズとする。
- サンプル名を x軸、ライブラリサイズを y軸 とするバープロットを `ggplot2` で作成する。
- プロットのテーマは `theme_classic()` を基本とし、テキストは英語表記とする (`project-rule.md` 準拠)。
- 生成されたプロットを指定されたディレクトリにPNGファイルとして保存する。
- `project-rule.md` のデータQCステップにおける基本的な品質評価に対応する。

## 3. 入力 (Arguments)
- **引数名:** `se`
    - **データ型:** `SummarizedExperiment`
    - **説明:** 解析対象のSEオブジェクト。`assay()` で指定されたアッセイデータを含む必要がある。
    - **必須/任意:** 必須
    - **デフォルト値:** なし
- **引数名:** `experiment_id`
    - **データ型:** `character`
    - **説明:** 実験ID。出力ファイルパスの生成に使用される。`run_with_logging` から渡される想定。
    - **必須/任意:** 必須
    - **デフォルト値:** なし
- **引数名:** `assay_name`
    - **データ型:** `character`
    - **説明:** ライブラリサイズの計算に使用するアッセイ名。`assayNames(se)` に含まれている必要がある。
    - **必須/任意:** 必須
    - **デフォルト値:** なし
- **引数名:** `output_dir`
    - **データ型:** `character` (パス)
    - **説明:** プロットファイルを保存するディレクトリ。通常は `results/{experiment_id}/plots`。
    - **必須/任意:** 必須
    - **デフォルト値:** なし
- **引数名:** `logger_name`
    - **データ型:** `character`
    - **説明:** ログ出力に使用するロガー名。`run_with_logging` から渡される想定。
    - **必須/任意:** 必須
    - **デフォルト値:** `"default"` (ただし `run_with_logging` 経由での呼び出しが前提)
- **引数名:** `target_name`
    - **データ型:** `character`
    - **説明:** この関数を実行する `targets` ターゲット名。`add_pipeline_history` で使用する。`run_with_logging` から渡される想定。
    - **必須/任意:** 必須
    - **デフォルト値:** `"unknown_target"`

## 4. 出力 (Return Value)
- **データ型:** `fs::path` (または `character`)
- **説明:** 生成されたプロットファイルの**絶対パス**。
- **ファイル出力:**
    - **ファイルパス:** `{output_dir}/library_size_{assay_name}_{experiment_id}.png`
    - **ファイル形式:** PNG
    - **ファイル内容:** サンプルごとのライブラリサイズを示したバープロット。

## 5. 処理フロー / 主要ステップ
1.  入力引数の検証 (`se` が `SummarizedExperiment` か、`assay_name` が存在するか等)。
2.  `flog.info` で関数開始と主要パラメータをログ記録。
3.  `assay(se, assay_name)` で指定アッセイデータを取得。
4.  `colSums()` でライブラリサイズを計算。
5.  計算結果を `data.frame` または `tibble` に整形 (サンプル名とライブラリサイズ)。
6.  `ggplot()` を使用してバープロットオブジェクト (`gg`) を作成。
    - `aes(x = sample_name, y = library_size)`
    - `geom_bar(stat = "identity")`
    - `theme_classic()` + `theme(plot.title = element_text(hjust = 0.5))`
    - `labs(title = "Library Size per Sample", x = "Sample", y = "Total Counts")`
7.  `flog.debug` でプロットオブジェクト作成完了をログ記録。
8.  出力ファイルパスを生成 (`fs::path()` と `glue::glue()` または `file.path()` を使用)。絶対パスにする。
9.  `ggplot2::ggsave()` でプロットをPNGファイルとして保存。解像度 (例: 300 dpi) とサイズを指定。
10. `flog.info` でファイル保存完了とパスをログ記録。
11. (オプションだが推奨) `add_pipeline_history` を呼び出し、SEオブジェクトのメタデータに処理履歴を追記（入力SEオブジェクトを返す必要があるため、この関数では直接行わず、呼び出し元 (`_targets.R`) で実施するか、SEを返すように変更する必要がある。今回はSEを返さないため、メタデータ更新は行わない。）
12. `flog.info` で関数終了をログ記録。
13. 生成されたファイルの絶対パスを返す。

## 6. 副作用 (Side Effects)
- 指定された `output_dir` にプロットファイル (`library_size_{assay_name}_{experiment_id}.png`) を書き込む。
- SEオブジェクトのメタデータ更新は行わない (SEオブジェクトを返さないため)。

## 7. ログ仕様 (`futile.logger`)
- **ログレベル:** INFO, DEBUG, WARN, ERROR
- **ログ内容:**
    - 関数開始 (INFO, 引数)
    - アッセイデータ取得成功/失敗 (DEBUG/ERROR)
    - ライブラリサイズ計算完了 (DEBUG)
    - プロットオブジェクト作成完了 (DEBUG)
    - ファイル保存試行 (DEBUG, パス)
    - ファイル保存成功 (INFO, パス)
    - ファイル保存失敗 (ERROR)
    - 関数終了 (INFO)
- **ログファイル名:** `logs/{experiment_id}/plot_library_size.log` (`run_with_logging` が設定)

## 8. テストケース (`testthat`)
- **テストファイル:** `tests/testthat/test-plot_library_size.R`
- **テスト項目:**
    - **正常系:**
        - 正しい入力 (SE, exp_id, assay_name, output_dir) で関数がエラーなく実行される。
        - 戻り値が期待されるファイルパス (文字列) である。
        - 期待されるパスに実際にPNGファイルが生成されている。
        - (発展) 生成された `ggplot` オブジェクトが期待通りか (例: `geom_bar` を含むか)。
    - **異常系:**
        - `se` が `SummarizedExperiment` でない場合にエラー。
        - 指定された `assay_name` が `se` に存在しない場合にエラー。
        - `output_dir` が存在しない場合にエラー (または `ggsave` がエラーを出す)。
- **テストデータ:** `tests/testdata/plot_library_size/` またはテスト内で簡単なSEオブジェクトを作成。

## 9. 依存関係
- `SummarizedExperiment`
- `ggplot2`
- `dplyr` (データ整形用、任意)
- `tibble` (データ整形用、任意)
- `futile.logger`
- `fs` (パス操作用)
- `glue` (パス生成用、任意) 