# --- 必要なライブラリの読み込み ---
# 注: 関数内で読み込むことで targets にとって自己完結型になるが、
# 一般的な使用では外部での読み込みが望ましい場合がある。
library(SummarizedExperiment)
library(readr)
library(dplyr)
library(fs)
library(futile.logger)
library(cli)
library(stringr)
library(biomaRt)
library(tibble)
library(S4Vectors)

#' カウントファイルとメタデータファイルからSummarizedExperimentオブジェクトを作成する。
#'
#' この関数は、指定された実験IDのカウントデータとサンプルメタデータを読み込み、
#' 基本的な整合性チェックを実行し、`biomaRt` を使用して遺伝子アノテーションを取得し、
#' SummarizedExperimentオブジェクトを作成します。
#'
#' @param experiment_id 実験を識別する文字列。
#' @param counts_file_path カウントデータファイルへの**絶対パス**。
#' @param metadata_file_path サンプルメタデータファイルへの**絶対パス**。
#' @param gene_id_column カウントファイル内の遺伝子ID列名 (rownamesとして使用)。
#'        `readr::read_csv` では列名で指定、`data.table::fread` では列番号でも可。
#'        **注意:** この関数内では現在 `readr` を使用しているため、列名が必要です。
#'        デフォルトは1列目を想定し、`readr` が自動で "..." を付与することがあるため、
#'        呼び出し元で適切な名前 (例: "gene_id") を指定するか、`readr` の仕様を確認してください。
#'        *仕様書推奨は「最初の列」、ここでは暫定で 'gene_id' としておくが、呼び出し側での指定を推奨。*
#' @param sample_id_column メタデータファイル内のサンプルID列名。
#' @param biomart_host `biomaRt` で使用するホスト URL。
#' @param biomart_dataset `biomaRt` で使用するデータセット名 (例: "hsapiens_gene_ensembl")。
#' @param biomart_attributes `biomaRt` で取得する属性リスト。
#'
#' @return \code{SummarizedExperiment} オブジェクト。
#' @export
#'
#' @examples
#' \dontrun{
#' # ロガーの設定 (通常は _targets.R またはメインスクリプトで行う)
#' library(futile.logger)
#' flog.threshold(INFO)
#' flog.appender(appender.console())
#'
#' # パラメータの定義
#' exp_id <- "MyExperiment"
#' counts_path <- fs::path_abs("path/to/counts.csv")
#' meta_path <- fs::path_abs("path/to/metadata.csv")
#' bm_dataset <- "hsapiens_gene_ensembl" # ヒトの例
#' bm_host <- "https://ensembl.org"
#'
#' # 例のためのダミーファイル作成
#' counts_df <- data.frame(
#'   gene_id = paste0("ENSG", sprintf("%011d", 1:10)),
#'   sampleA = rpois(10, 10),
#'   sampleB = rpois(10, 20)
#' )
#' meta_df <- data.frame(
#'   sample_id = c("sampleA", "sampleB"),
#'   condition = c("control", "treatment")
#' )
#' temp_dir <- tempdir()
#' write.csv(counts_df, file.path(temp_dir, "counts.csv"), row.names = FALSE)
#' write.csv(meta_df, file.path(temp_dir, "metadata.csv"), row.names = FALSE)
#' counts_path <- file.path(temp_dir, "counts.csv")
#' meta_path <- file.path(temp_dir, "metadata.csv")
#'
#' # 関数の実行
#' se <- create_se_object(
#'   experiment_id = exp_id,
#'   counts_file_path = counts_path,
#'   metadata_file_path = meta_path,
#'   gene_id_column = "gene_id", # 異なる場合は調整
#'   sample_id_column = "sample_id",
#'   biomart_host = bm_host,
#'   biomart_dataset = bm_dataset
#' )
#' print(se)
#' print(rowData(se))
#' print(metadata(se))
#'
#' # ダミーファイルのクリーンアップ
#' unlink(temp_dir, recursive = TRUE)
#' }
create_se_object <- function(experiment_id,
                             counts_file_path,
                             metadata_file_path,
                             gene_id_column = "gene_id", # @param の注釈を参照
                             sample_id_column = "sample_id",
                             biomart_host = "https://ensembl.org",
                             biomart_dataset, # デフォルトなし、指定必須
                             biomart_attributes = c("ensembl_gene_id", "external_gene_name", "transcript_length", "gene_biotype")) {

  # --- 0. セットアップ ---
  process_start <- cli_process_start("実験 {.val {experiment_id}} のSEオブジェクトを作成中...",
                                      on_exit = "done")

  # 入力パラメータのログ記録 (絶対パス)
  flog.info("実験ID: %s のSEオブジェクト作成を開始します。", experiment_id)
  flog.info("カウントファイルパス: %s", counts_file_path)
  flog.info("メタデータファイルパス: %s", metadata_file_path)
  flog.info("遺伝子ID列: %s", gene_id_column)
  flog.info("サンプルID列: %s", sample_id_column)
  flog.info("biomaRt ホスト: %s", biomart_host)
  flog.info("biomaRt データセット: %s", biomart_dataset)
  flog.info("biomaRt 属性: %s", paste(biomart_attributes, collapse=", "))


  # 入力ファイルの存在確認
  if (!fs::file_exists(counts_file_path)) {
    msg <- sprintf("カウントファイルが見つかりません: %s", counts_file_path)
    flog.error(msg)
    cli_process_failed(process_start)
    stop(msg)
  }
  if (!fs::file_exists(metadata_file_path)) {
    msg <- sprintf("メタデータファイルが見つかりません: %s", metadata_file_path)
    flog.error(msg)
    cli_process_failed(process_start)
    stop(msg)
  }
  flog.info("入力ファイルが存在します。")

  # --- 1. 入力ファイルの読み込み ---
  cli_alert_info("入力ファイルを読み込んでいます...")
  counts_data <- tryCatch(
    # gene_id_column が明示的に 'gene_id' と名付けられていない場合、最初の列だと仮定するのは不安定かもしれない。
    # `readr::read_csv` はデフォルトで最初の行をヘッダーとして使用する。
    # gene_id_column パラメータで特定の名前を指定する方が安全。
    readr::read_csv(counts_file_path, show_col_types = FALSE, name_repair = "minimal"),
    error = function(e) {
      msg <- sprintf("カウントファイル '%s' の読み込みに失敗しました: %s", counts_file_path, e$message)
      flog.error(msg)
      cli_process_failed(process_start)
      stop(msg)
    }
  )
  flog.info("カウントファイルを正常に読み込みました。")

  sample_metadata <- tryCatch(
    readr::read_csv(metadata_file_path, show_col_types = FALSE, name_repair = "minimal"),
    error = function(e) {
      msg <- sprintf("メタデータファイル '%s' の読み込みに失敗しました: %s", metadata_file_path, e$message)
      flog.error(msg)
      cli_process_failed(process_start)
      stop(msg)
    }
  )
  flog.info("メタデータファイルを正常に読み込みました。")

  # --- 2. データ整合性チェック ---
  cli_alert_info("データ整合性をチェックしています...")

  # counts_data に gene_id_column が存在するか確認
  if (!gene_id_column %in% colnames(counts_data)) {
      msg <- sprintf("指定された遺伝子ID列 '%s' がカウントファイルの列に見つかりません: %s",
                     gene_id_column, paste(colnames(counts_data), collapse=", "))
      flog.error(msg)
      cli_process_failed(process_start)
      stop(msg)
  }

  # sample_metadata に sample_id_column が存在するか確認
  if (!sample_id_column %in% colnames(sample_metadata)) {
      msg <- sprintf("指定されたサンプルID列 '%s' がメタデータファイルの列に見つかりません: %s",
                     sample_id_column, paste(colnames(sample_metadata), collapse=", "))
      flog.error(msg)
      cli_process_failed(process_start)
      stop(msg)
  }


  count_sample_ids <- colnames(counts_data)[colnames(counts_data) != gene_id_column]
  meta_sample_ids <- sample_metadata[[sample_id_column]]

  # 重複サンプルIDのチェック
  if (any(duplicated(count_sample_ids))) {
      msg <- sprintf("カウントファイルのヘッダーに重複したサンプルIDが見つかりました: %s",
                     paste(unique(count_sample_ids[duplicated(count_sample_ids)]), collapse=", "))
      flog.error(msg)
      cli_process_failed(process_start)
      stop(msg)
  }
  if (any(duplicated(meta_sample_ids))) {
      msg <- sprintf("メタデータ列 '%s' に重複したサンプルIDが見つかりました: %s",
                     sample_id_column,
                     paste(unique(meta_sample_ids[duplicated(meta_sample_ids)]), collapse=", "))
      flog.error(msg)
      cli_process_failed(process_start)
      stop(msg)
  }


  # 欠損サンプルのチェック (厳密なチェック: 完全に一致する必要あり)
  if (!setequal(count_sample_ids, meta_sample_ids)) {
      missing_in_meta <- setdiff(count_sample_ids, meta_sample_ids)
      missing_in_counts <- setdiff(meta_sample_ids, count_sample_ids)
      error_msgs <- c()
      if (length(missing_in_meta) > 0) {
          error_msgs <- c(error_msgs, sprintf("カウントファイルにあるサンプルIDがメタデータに見つかりません: %s", paste(missing_in_meta, collapse=", ")))
      }
      if (length(missing_in_counts) > 0) {
          # 仕様書では不一致の場合は停止。以前の実装の警告から調整。
          error_msgs <- c(error_msgs, sprintf("メタデータにあるサンプルIDがカウントファイルに見つかりません: %s", paste(missing_in_counts, collapse=", ")))
      }
      full_error_msg <- paste(error_msgs, collapse="; ")
      flog.error("サンプルIDの不一致: %s", full_error_msg)
      cli_process_failed(process_start)
      stop(full_error_msg)
  }

  flog.info("サンプルIDはカウントヘッダーとメタデータ列 '%s' で一致します。", sample_id_column)

  # カウントデータの列に合わせてメタデータを並べ替え
  sample_metadata <- sample_metadata[match(count_sample_ids, meta_sample_ids), ]
  flog.info("サンプルメタデータをカウントデータの列に合わせて並べ替えました。")

  # colData のために、サンプルメタデータのサンプルID列を行名に変換
  sample_metadata <- tryCatch({
        tibble::column_to_rownames(sample_metadata, var = sample_id_column)
    }, error = function(e) {
        # これは、上記でチェックしたにもかかわらず sample_id_column が一意でない場合に発生する可能性がある。
        msg <- sprintf("メタデータ列 '%s' から行名を設定できませんでした: %s", sample_id_column, e$message)
        flog.error(msg)
        cli_process_failed(process_start)
        stop(msg)
  })


  # カウントマトリックスの準備 (遺伝子IDを行名とする)
  # 行名を設定する前に重複遺伝子IDをチェック
  gene_ids_with_version <- counts_data[[gene_id_column]]
  if (any(duplicated(gene_ids_with_version))) {
      msg <- sprintf("カウント列 '%s' に重複した遺伝子IDが見つかりました: %s",
                     gene_id_column,
                     paste(unique(gene_ids_with_version[duplicated(gene_ids_with_version)]), collapse=", "))
      flog.warn(msg) # 今のところ警告。エラーにするかどうかは要検討。
      # ポリシーによっては、ここで停止するか、重複を除去することができる。
      # 今のところ、SummarizedExperiment に処理を任せるか、最初の出現を使用させる。
  }

  count_matrix <- tryCatch({
        counts_data |>
        # 行名を設定する前に遺伝子ID列が文字型であることを確認
        dplyr::mutate({{gene_id_column}} := as.character(.data[[gene_id_column]])) |>
        tibble::column_to_rownames(var = gene_id_column) |>
        # 列が（並べ替えられた可能性のある）メタデータの行名と一致することを確認
        dplyr::select(all_of(rownames(sample_metadata))) |>
        as.matrix()
    }, error = function(e) {
        msg <- sprintf("列 '%s' からカウントマトリックスを作成できませんでした: %s", gene_id_column, e$message)
        flog.error(msg)
        cli_process_failed(process_start)
        stop(msg)
    })

  flog.info("カウントマトリックスを準備しました。次元: %d 行, %d 列。", nrow(count_matrix), ncol(count_matrix))

  # --- 3. biomaRt を用いた遺伝子アノテーション --- 
  cli_alert_info("biomaRt を使用して遺伝子アノテーションを取得しています...")

  # 遺伝子IDの取得 (ENSEMBL IDを想定、バージョン付きの可能性あり)
  ensembl_ids_versioned <- rownames(count_matrix)
  flog.info("カウントからのバージョン付き遺伝子IDの総数: %d", length(ensembl_ids_versioned))
  flog.debug("バージョン付き遺伝子ID (最初の10個): %s", paste(head(ensembl_ids_versioned, 10), collapse=", "))

  # biomaRtクエリのためにバージョン接尾辞を削除
  # 正規表現を修正: .区切りとそれに続く数字
  ensembl_ids_unversioned <- stringr::str_remove(ensembl_ids_versioned, "\\.\\d+$")
  unique_ensembl_ids_unversioned <- unique(ensembl_ids_unversioned)
  flog.info("バージョンを削除しました。biomaRtクエリ用の一意なバージョンなしID: %d 個。", length(unique_ensembl_ids_unversioned))
  flog.debug("バージョンなし一意遺伝子ID (最初の10個): %s", paste(head(unique_ensembl_ids_unversioned, 10), collapse=", "))

  # Ensembl に接続
  mart <- tryCatch({
    flog.info("biomaRt ホストに接続中: %s, データセット: %s", biomart_host, biomart_dataset)
    biomaRt::useMart(biomart = "ENSEMBL_MART_ENSEMBL",
                     dataset = biomart_dataset,
                     host = biomart_host)
  }, error = function(e) {
    msg <- sprintf("biomaRt ホスト '%s' (データセット '%s') への接続に失敗しました: %s", biomart_host, biomart_dataset, e$message)
    flog.error(msg)
    # アノテーションの失敗が致命的かどうかを判断
    # 今のところ、NULL の rowData を返すか停止する
    cli_process_failed(process_start)
    stop(msg) # 接続失敗時は停止
  })
  flog.info("biomaRt に接続しました。")
  flog.debug("biomaRt オブジェクト: %s", capture.output(print(mart))) # martオブジェクト情報をデバッグログに追加

  # 属性の取得
  annotation_bm <- NULL # 事前に NULL で初期化
  if (!is.null(mart)) { # mart オブジェクトが正常に作成された場合のみ実行
      annotation_bm <- tryCatch({
          # デバッグログ: getBMに渡すパラメータ
          flog.debug("biomaRt::getBM 実行前:")
          flog.debug("  - attributes: %s", paste(biomart_attributes, collapse=", "))
          flog.debug("  - filters: ensembl_gene_id")
          flog.debug("  - values (一意なバージョンなしIDの数): %d", length(unique_ensembl_ids_unversioned))
          flog.debug("  - values (最初の10個): %s", paste(head(unique_ensembl_ids_unversioned, 10), collapse=", "))
          flog.debug("  - mart host: %s", mart@host)
          flog.debug("  - mart dataset: %s", mart@dataset)
          
          flog.info("biomaRt 属性を取得中: %s", paste(biomart_attributes, collapse=", "))
          bm_result <- biomaRt::getBM(attributes = biomart_attributes,
                       filters = "ensembl_gene_id", # クエリにはバージョンなしIDを使用
                       values = unique_ensembl_ids_unversioned, # 一意なIDのみを渡す
                       mart = mart,
                       useCache = FALSE) # キャッシュは問題を引き起こすことがある
          
          # デバッグログ: getBM の結果
          flog.debug("biomaRt::getBM 実行後:")
          flog.debug("  - 返された結果 (annotation_bm) の次元: %s", paste(dim(bm_result), collapse=" x "))
          if (is.data.frame(bm_result) && nrow(bm_result) > 0) {
              flog.debug("  - 返された結果 (annotation_bm) の head():
%s", capture.output(head(bm_result)))
          } else {
              flog.debug("  - 返された結果 (annotation_bm) は空またはデータフレームではありません。")
          }
          bm_result # tryCatch の戻り値として結果を返す
      }, error = function(e) {
          msg <- sprintf("biomaRt から属性の取得に失敗しました: %s", e$message)
          flog.error(msg)
          # アノテーションなしで続行するか？停止するか？ 仕様書は rowData が必要であることを示唆。
          # 今のところ、空の rowData 構造を作成して警告を発する。
          flog.warn("エラーのため、biomaRt アノテーションなしで続行します。")
          NULL # 失敗を示すために NULL を返す
      })
  } else {
      flog.error("biomaRt マートオブジェクトが NULL のため、getBM をスキップします。")
  }


  # biomaRt 結果の処理
  annotation_df <- NULL
  if (!is.null(annotation_bm) && nrow(annotation_bm) > 0) {
      flog.info("biomaRt から %d 個の一意なバージョンなしIDに対して %d 個のアノテーションレコードを正常に取得しました。",
                length(unique_ensembl_ids_unversioned), nrow(annotation_bm))
      flog.debug("取得したアノテーション (annotation_bm) の head():
%s", capture.output(head(annotation_bm)))


      # 属性が重複を引き起こす場合、バージョンなしIDごとに複数のマッチが生じる可能性への対処
      # (例: transcript_length は異なる可能性がある)。通常、遺伝子IDごとに1行が望ましい。
      # ensembl_gene_id でグループ化し、最初の行を取得する（または必要に応じて集約する）ことを検討。
      # 簡単のため、まず完全な重複を削除する。
      original_nrow <- nrow(annotation_bm) # 重複削除前の行数を記録
      # ensembl_gene_id 列が存在するか確認してから重複削除
      if ("ensembl_gene_id" %in% colnames(annotation_bm)) {
          annotation_bm_unique <- annotation_bm[!duplicated(annotation_bm$ensembl_gene_id), ]
          removed_duplicates <- original_nrow - nrow(annotation_bm_unique)
          if (removed_duplicates > 0) {
               flog.info("ensembl_gene_id に基づいて %d 行の重複したアノテーション行を削除しました。", removed_duplicates)
               flog.debug("重複削除後のアノテーション (annotation_bm_unique) の head():
%s", capture.output(head(annotation_bm_unique)))
          }
      } else {
          flog.warn("'ensembl_gene_id' 列が biomaRt 結果に見つからないため、重複削除をスキップします。取得された列: %s", paste(colnames(annotation_bm), collapse=", "))
          annotation_bm_unique <- annotation_bm # スキップする場合は元のデータを使用
      }


      # バージョン付きIDからバージョンなしIDへのマッピングを作成
      id_map <- data.frame(ensembl_gene_id_version = ensembl_ids_versioned,
                           ensembl_gene_id = ensembl_ids_unversioned,
                           stringsAsFactors = FALSE)
      flog.debug("作成したIDマッピング (id_map) の head():
%s", capture.output(head(id_map)))
      flog.debug("IDマッピング (id_map) の次元: %s", paste(dim(id_map), collapse=" x "))


      # バージョンなしIDを使用してアノテーションをマージ
      # dplyr::left_joinの前に列が存在するか確認
      if ("ensembl_gene_id" %in% colnames(annotation_bm_unique) && "ensembl_gene_id" %in% colnames(id_map)) {
          merged_annotations <- dplyr::left_join(id_map, annotation_bm_unique, by = "ensembl_gene_id")
          flog.debug("マージ後のアノテーション (merged_annotations) の head():
%s", capture.output(head(merged_annotations)))
          flog.debug("マージ後のアノテーション (merged_annotations) の次元: %s", paste(dim(merged_annotations), collapse=" x "))
      } else {
           flog.error("マージに必要な 'ensembl_gene_id' 列が id_map または annotation_bm_unique に存在しません。アノテーションのマージをスキップします。")
           merged_annotations <- id_map # マージできない場合は id_map だけを保持 (最低限のrowDataのため)
           # マージできなかった属性列をNAで追加する方が良いかもしれない
           for (attr_col in biomart_attributes) {
               if (attr_col != "ensembl_gene_id" && !(attr_col %in% colnames(merged_annotations))) {
                   merged_annotations[[attr_col]] <- NA
               }
           }
      }


      # アノテーションが得られなかったIDをチェック
      # チェックする列名を動的に決定 (例: 2番目の属性、通常は遺伝子名)
      check_col_index <- if(length(biomart_attributes) > 1) 2 else 1 # 属性が1つしかない場合はそれをチェック
      check_col_name <- biomart_attributes[check_col_index]
      if(check_col_name %in% colnames(merged_annotations)) {
          unmatched_ids <- merged_annotations$ensembl_gene_id_version[is.na(merged_annotations[[check_col_name]])]
          if (length(unmatched_ids) > 0) {
              flog.warn("biomaRt で %d 個のバージョン付きIDがどのアノテーションにも一致しませんでした（列 '%s' でNA）。", length(unmatched_ids), check_col_name)
              flog.debug("一致しなかったバージョン付きID (最初の10個): %s", paste(head(unmatched_ids, 10), collapse=", "))
          } else {
              flog.info("すべての一意なバージョンなしIDが biomaRt で一致を見つけました。")
          }
      } else {
          flog.warn("アノテーションの一致チェックに使用する列 '%s' が merged_annotations に存在しません。", check_col_name)
      }


      # 最終的なアノテーション DataFrame の行名としてバージョン付きIDを設定
      # 順序が count_matrix の行名と一致することを確認
      # 元のバージョン付きIDを主キーとして使用
      if ("ensembl_gene_id_version" %in% colnames(merged_annotations)) {
          tryCatch({
              rownames(merged_annotations) <- merged_annotations$ensembl_gene_id_version
          }, error = function(e){
              flog.error("merged_annotations の行名設定に失敗しました: %s", e$message)
              flog.warn("重複した ensembl_gene_id_version が原因の可能性があります。")
              # 重複がある場合の対処 (例: 重複を削除、最初のものを保持)
              merged_annotations <- merged_annotations[!duplicated(merged_annotations$ensembl_gene_id_version), ]
              rownames(merged_annotations) <- merged_annotations$ensembl_gene_id_version
              flog.info("重複する ensembl_gene_id_version を削除して行名を設定しました。")
          })
          flog.debug("行名設定後の merged_annotations の head():
%s", capture.output(head(merged_annotations)))
      } else {
          flog.error("'ensembl_gene_id_version' 列が merged_annotations に存在しないため、行名を設定できません。")
          # この場合、rowData の作成は失敗する可能性が高い
      }


      # 仕様書の要件に合わせて列を選択し、必要に応じて名前を変更
      # 必要なもの: ensembl_gene_id (バージョンなし), gene_name, gene_length, gene_biotype
      # 実際の名前は使用された biomart_attributes に依存する。
      
      # 列名を選択する前に利用可能な列名を確認
      available_cols <- colnames(merged_annotations)
      flog.debug("列選択前の利用可能な列名: %s", paste(available_cols, collapse=", "))

      # dplyr::select と dplyr::rename を安全に適用
      # any_of は存在しない列名を指定してもエラーにならない
      select_cols <- c("ensembl_gene_id", # バージョンなしID (biomaRtから)
                       # 遺伝子名の候補
                       "external_gene_name", "hgnc_symbol", biomart_attributes[2], 
                       # 遺伝子長の候補
                       "transcript_length", biomart_attributes[3],
                       # 遺伝子バイオタイプの候補
                       "gene_biotype", biomart_attributes[4])
      
      # 実際に存在する列だけを選択リストに入れる
      select_cols_existing <- intersect(select_cols, available_cols)
      flog.debug("選択する列 (実際に存在する列): %s", paste(select_cols_existing, collapse=", "))

      # select で列を選択
      if (length(select_cols_existing) > 0) {
          final_annotation_selected <- dplyr::select(merged_annotations, all_of(select_cols_existing))
      } else {
          flog.warn("選択可能なアノテーション列が見つかりませんでした。空のDataFrameを作成します。")
          # 行名だけを持つ空のDataFrameを作成
          final_annotation_selected <- data.frame(row.names = rownames(merged_annotations))
      }

      # rename で列名を変更 (any_of を使用して安全に)
      final_annotation_renamed <- dplyr::rename(final_annotation_selected,
          gene_name = any_of(intersect(c("external_gene_name", "hgnc_symbol", biomart_attributes[2]), select_cols_existing)),
          gene_length = any_of(intersect(c("transcript_length", biomart_attributes[3]), select_cols_existing)),
          gene_biotype = any_of(intersect(c("gene_biotype", biomart_attributes[4]), select_cols_existing))
      )

      final_annotation_unsorted <- final_annotation_renamed
      flog.debug("列選択・リネーム後のアノテーション (final_annotation_unsorted) の head():
%s", capture.output(head(final_annotation_unsorted)))
      flog.debug("列選択・リネーム後のアノテーション (final_annotation_unsorted) の次元: %s", paste(dim(final_annotation_unsorted), collapse=" x "))

          
      # 行名が正しく設定されていることを確認 (バージョン付きID)
      # 順序はカウントマトリックスと一致する必要がある
      # パイプの外でサブセット化を実行
      target_rownames <- rownames(count_matrix)
      # final_annotation_unsorted の行名に target_rownames が全て含まれているか確認
      if (all(target_rownames %in% rownames(final_annotation_unsorted))) {
          final_annotation <- final_annotation_unsorted[target_rownames, , drop = FALSE] # 順序がカウントと一致することを確認, drop=FALSE は1列の場合にベクトルへの変換を防ぐ
          flog.debug("カウントマトリックスの行順に並べ替えたアノテーション (final_annotation) の head():
%s", capture.output(head(final_annotation)))
      } else {
          missing_rows <- setdiff(target_rownames, rownames(final_annotation_unsorted))
          flog.error("最終アノテーションに行名 '%s' が不足しているため、カウントマトリックスの順序に合わせられません。", paste(head(missing_rows, 5), collapse=", "))
          # フォールバック: 共通の行名でサブセット化し、不足分はNAで埋めるなどが必要になる可能性がある
          # ここでは、エラーをログに残し、不完全な final_annotation_unsorted を使う試みをする
          final_annotation <- final_annotation_unsorted # 順序が一致しない可能性がある
          # TODO: 不足行に対するより堅牢な処理を追加検討
      }


      # DataFrameに変換する前に final_annotation が NULL でないか確認
      if (!is.null(final_annotation)) {
         annotation_df <- tryCatch({
               S4Vectors::DataFrame(final_annotation, row.names = rownames(final_annotation))
             }, error = function(e){
                flog.error("最終アノテーションから S4Vectors::DataFrame の作成に失敗しました: %s", e$message)
                NULL # エラー時は NULL を返す
         })
         if (!is.null(annotation_df)) {
             flog.info("アノテーションを rowData 用の DataFrame にフォーマットしました。次元: %d 行, %d 列。",
                       nrow(annotation_df), ncol(annotation_df))
             flog.debug("最終的な rowData (annotation_df) の head():
%s", capture.output(head(annotation_df)))
             flog.debug("最終的な rowData (annotation_df) のクラス: %s", class(annotation_df))
         } else {
            # DataFrame 作成失敗時の処理 (空のDataFrameを作成)
             flog.warn("S4Vectors::DataFrame の作成に失敗したため、空の rowData で SE オブジェクトを作成します。")
             annotation_df <- S4Vectors::DataFrame(row.names = rownames(count_matrix))
         }
      } else {
         flog.warn("最終アノテーションオブジェクト (final_annotation) が NULL です。空の rowData で SE オブジェクトを作成します。")
         annotation_df <- S4Vectors::DataFrame(row.names = rownames(count_matrix))
      }


  } else if (is.null(annotation_bm) && !is.null(mart)) { # getBM でエラーが発生した場合 (接続は成功)
      # フェッチ中にエラーが発生
      flog.warn("biomaRt の取得エラーのため、空の rowData で SE オブジェクトを作成します。")
      annotation_df <- S4Vectors::DataFrame(row.names = rownames(count_matrix)) # 空だが、行名は一致
  } else if (is.null(mart)) { # 接続自体が失敗した場合
       flog.warn("biomaRt への接続に失敗したため、空の rowData で SE オブジェクトを作成します。")
       annotation_df <- S4Vectors::DataFrame(row.names = rownames(count_matrix))
  } else { # getBM が結果を返さなかった場合 (エラーなし)
      # biomaRt からレコードが返されなかった
      flog.warn("提供された遺伝子IDに対して biomaRt でアノテーションが見つかりませんでした。空の rowData で SE を作成します。")
      annotation_df <- S4Vectors::DataFrame(row.names = rownames(count_matrix)) # 空だが、行名は一致
  }


  # --- 4. SummarizedExperiment オブジェクトの作成 ---
  cli_alert_info("SummarizedExperiment オブジェクトを作成しています...")


  # rowData の行名がアッセイの行名と一致することを確認 (上記のステップで保証されているはず)
  if (!identical(rownames(count_matrix), rownames(annotation_df))) {
      msg <- "カウントマトリックスの行名とアノテーション DataFrame の行名が一致しません。"
      flog.error(msg)
      flog.debug("カウント行名 (head): %s", paste(head(rownames(count_matrix)), collapse=", "))
      flog.debug("アノテーション行名 (head): %s", paste(head(rownames(annotation_df)), collapse=", "))
      # フォールバックとして annotation_df を並べ替える試み（これは起こらないはず）
      # count_matrix の行名に存在するものだけを annotation_df から抽出して並べ替える
      common_rownames <- intersect(rownames(count_matrix), rownames(annotation_df))
      missing_in_annot <- setdiff(rownames(count_matrix), rownames(annotation_df))
      if(length(missing_in_annot) > 0) {
         flog.warn("%d 個の遺伝子IDがカウントマトリックスにありますが、アノテーション DataFrame にはありません。", length(missing_in_annot))
      }
      annotation_df_reordered <- annotation_df[common_rownames, , drop = FALSE]
      # 足りない行をNAで埋める必要があるか？ SEの作成時にエラーになる可能性がある
      # ここでは共通部分だけで作成を試みる（SE関数が許容するかどうかによる）
      if(nrow(annotation_df_reordered) < nrow(count_matrix)) {
         flog.warn("アノテーション DataFrame の行数がカウントマトリックスより少ないです。一部のrowDataが欠落します。")
         # SE作成はエラーになる可能性が高い。空のrowDataを使う方が安全かもしれない
         # ここでは警告のみとし、SE作成を試みる
      }
      annotation_df <- annotation_df_reordered # 並び替えたものを使用 (行数が減っている可能性あり)


      # 再度チェック
      if (!identical(rownames(count_matrix)[rownames(count_matrix) %in% rownames(annotation_df)], rownames(annotation_df))) {
          flog.error("アノテーション DataFrame の行名をカウントマトリックスに合わせて並べ替え/サブセット化しましたが、まだ一致しません。")
          cli_process_failed(process_start)
          stop(msg) # 並べ替えが失敗した場合は停止
      } else {
         flog.warn("アノテーション DataFrame の行名をカウントマトリックスに合わせて並べ替え/サブセット化しました。")
      }
  } else {
     flog.info("カウントマトリックスと rowData の行名が一致します。")
  }


  # --- 5. SummarizedExperiment オブジェクトの作成 ---
  cli_alert_info("SummarizedExperiment オブジェクトを作成しています...")

  se <- tryCatch({
    SummarizedExperiment::SummarizedExperiment(
      assays = list(counts = count_matrix),
      colData = S4Vectors::DataFrame(sample_metadata), # すでに正しい行名を持っている
      rowData = annotation_df # すでに正しい行名と目的の列を持っている (または空)
    )
  }, error = function(e) {
    msg <- sprintf("SummarizedExperiment オブジェクトの作成に失敗しました: %s", e$message)
    flog.error(msg)
    cli_process_failed(process_start)
    stop(msg)
  })

  flog.info("SummarizedExperiment オブジェクトを正常に作成しました。")


  # --- 6. SE メタデータの初期化 ---
  cli_alert_info("SE メタデータを初期化しています...")

  metadata(se)$experiment_id <- experiment_id
  metadata(se)$pipeline_history <- list() # 空のリストとして初期化

  flog.info("SE メタデータを experiment_id と空の pipeline_history で初期化しました。")

  # --- 7. 完了 ---
  # cli_process_done() は cli_process_start の on_exit で処理される
  flog.info("実験: %s のSEオブジェクト作成が完了しました。", experiment_id)
  cli_alert_success("実験: {.val {experiment_id}} のSEオブジェクトを正常に作成しました。")

  return(se)
}