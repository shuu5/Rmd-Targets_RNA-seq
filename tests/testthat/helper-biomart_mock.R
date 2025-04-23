# biomaRtのモック関数を定義するヘルパーファイル
# testthatは自動的にtests/testthat/helper-*というファイルを読み込みます

#' biomaRt::useMartのモック関数
#' 
#' Mart型のオブジェクトを返すだけのモック関数
#' @param biomart biomart名
#' @param dataset データセット名
#' @param host ホスト名
#' @param ... その他のパラメータ
#' @return Mart型のオブジェクト
mock_useMart <- function(biomart, dataset, host, ...) {
  structure(
    list(
      biomart = biomart,
      dataset = dataset,
      version = "mock_version",
      host = host,
      martdb = list()
    ),
    class = c("Mart", "list")
  )
}

#' biomaRt::getBMのモック関数
#' 
#' テスト用の固定データを返すモック関数
#' @param attributes 取得する属性
#' @param filters フィルタ
#' @param values フィルタ値
#' @param mart Martオブジェクト
#' @param ... その他のパラメータ
#' @return 固定されたテストデータのデータフレーム
mock_getBM <- function(attributes, filters, values, mart, ...) {
  # 両方の遺伝子がprotein_codingになるように設定
  data.frame(
    ensembl_gene_id = c("ENSG000001", "ENSG000002"),
    external_gene_name = c("GENE1", "GENE2"),
    transcript_length = c(1000, 2000),
    gene_biotype = c("protein_coding", "protein_coding")
  )
}

#' biomaRtモックを適用してコードブロックを実行するヘルパー関数
#' 
#' @param expr 実行する式
#' @return exprの評価結果
with_biomart_mock <- function(expr) {
  testthat::with_mock(
    "biomaRt::useMart" = mock_useMart,
    "biomaRt::getBM" = mock_getBM,
    expr
  )
}

#' biomaRtモックを使用してRmdをレンダリングし結果を取得
#' 
#' @param input_rmd_path 入力Rmdファイルのパス
#' @param output_file_path 出力HTMLファイルのパス
#' @param params_list パラメータリスト
#' @param debug デバッグモードフラグ
#' @param test_condition テスト条件名（ログディレクトリの作成に使用）
#' @return Rmdの最後の値またはseオブジェクト
render_with_biomart_mock <- function(input_rmd_path, output_file_path, params_list, debug = FALSE, test_condition = NULL) {
  # モジュール名を取得
  rmd_filename <- basename(input_rmd_path)
  module_name <- tools::file_path_sans_ext(rmd_filename)
  
  # テスト条件名が指定されていない場合は、出力ファイル名から推測
  if (is.null(test_condition)) {
    # 出力ファイル名からテスト条件を推測（ファイル名自体をテスト条件として使用）
    test_condition <- tools::file_path_sans_ext(basename(output_file_path))
  }
  
  # プロジェクトルートを取得 - テストファイルは tests/testthat/ にあるため2階層上がルート
  project_root <- normalizePath(file.path(getwd(), "..", ".."))
  
  # experiment_idをパラメータから取得（デフォルトはtest_experiment）
  experiment_id <- if (!is.null(params_list$experiment_id)) params_list$experiment_id else "test_experiment"
  
  # テスト環境であることを示す環境変数を設定
  Sys.setenv(TEST_MODE = "TRUE")
  Sys.setenv(TEST_MODULE_NAME = module_name)
  Sys.setenv(TEST_CONDITION_NAME = test_condition)
  Sys.setenv(TEST_EXPERIMENT_ID = experiment_id)
  
  # テストデータディレクトリを作成
  test_data_dir <- file.path(project_root, "tests", "testdata", module_name)
  dir.create(test_data_dir, recursive = TRUE, showWarnings = FALSE)
  
  # テスト用のダミーデータを作成
  create_test_dummy_files(test_data_dir)
  
  # ログディレクトリを取得 - 一本化したパスを使用
  log_dir <- file.path(project_root, "logs", experiment_id)
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  
  # プロット出力などの結果ディレクトリ
  results_dir <- file.path(project_root, "results", experiment_id)
  dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
  
  # 出力ファイルパスの処理 - 一本化したパスを使用
  if (!is.absolute_path(output_file_path)) {
    # 絶対パスでない場合は、results/{experiment_id}/に配置
    log_friendly_name <- paste0(module_name, "-", test_condition)
    output_filename <- paste0(log_friendly_name, ".", tools::file_ext(output_file_path))
    output_file_path <- file.path(results_dir, output_filename)
  }
  
  # ヘルパー関数: Rmdをレンダリングして結果を取得
  render_rmd_and_get_last_value <- function(input_rmd_path, output_file_path, params_list, debug = FALSE) {
    render_env <- new.env(parent = globalenv())
    
    # 元のappenderを保存
    if (requireNamespace("futile.logger", quietly = TRUE)) {
      old_appender <- futile.logger::flog.appender()
      
      # ログファイルパス - モジュール名とテスト条件を組み合わせた名前を使用
      log_filename <- paste0(module_name, "-", test_condition, ".log")
      log_file <- file.path(log_dir, log_filename)
      
      # 一時的にログをファイルに出力するよう設定
      futile.logger::flog.appender(futile.logger::appender.file(log_file))
      
      # Rmd内からのログ出力にも適用するための環境変数設定
      # これによりRmd内でfutile.loggerが初期化される際にもこのパスを使用する
      old_test_module <- Sys.getenv("TEST_MODULE_NAME", "")
      old_test_condition <- Sys.getenv("TEST_CONDITION_NAME", "")
      old_test_experiment_id <- Sys.getenv("TEST_EXPERIMENT_ID", "")
      Sys.setenv(TEST_MODULE_NAME = module_name)
      Sys.setenv(TEST_CONDITION_NAME = test_condition)
      Sys.setenv(TEST_EXPERIMENT_ID = experiment_id)
      
      # 後でリセットするため一時変数にセット
      on.exit({
        futile.logger::flog.appender(old_appender)
        Sys.setenv(TEST_MODULE_NAME = old_test_module)
        Sys.setenv(TEST_CONDITION_NAME = old_test_condition)
        Sys.setenv(TEST_EXPERIMENT_ID = old_test_experiment_id)
      }, add = TRUE)
    }
    
    # utility.R をソースして必要な関数を読み込む
    utility_path <- file.path(project_root, "R", "utility.R")
    if (file.exists(utility_path)) {
      source(utility_path, local = render_env)
      # ログに記録
      if (requireNamespace("futile.logger", quietly = TRUE)) {
        futile.logger::flog.info("ユーティリティ関数を読み込みました: %s", utility_path)
      }
    } else {
      warning(sprintf("ユーティリティファイルが見つかりません: %s", utility_path))
    }
    
    # setup_logger関数をオーバーライド - テスト用の一本化されたパスを使用
    render_env$setup_logger <- function(experiment_id, module_name, log_level = "TRACE") {
      # テスト実行時は、experiment_idに関わらず、TEST_EXPERIMENT_IDを使用
      if (Sys.getenv("TEST_MODE") == "TRUE") {
        test_experiment_id <- Sys.getenv("TEST_EXPERIMENT_ID")
        if (test_experiment_id != "") {
          experiment_id <- test_experiment_id
        }
      }
      
      # library(futile.logger) # 関数内でロードする必要はなくなる
      library(fs)
      library(here)
      
      # ログディレクトリを確認・作成
      log_dir <- fs::path("logs", experiment_id)
      
      if (!fs::dir_exists(log_dir)) {
        fs::dir_create(log_dir, recurse = TRUE)
      }
      
      # テスト実行時は、モジュール名とテスト条件を組み合わせた名前を使用
      if (Sys.getenv("TEST_MODE") == "TRUE") {
        test_condition <- Sys.getenv("TEST_CONDITION_NAME")
        if (test_condition != "") {
          module_log_file <- fs::path(log_dir, paste0(module_name, "-", test_condition, ".log"))
        } else {
          module_log_file <- fs::path(log_dir, paste0(module_name, ".log"))
        }
      } else {
        module_log_file <- fs::path(log_dir, paste0(module_name, ".log"))
      }
      
      # 残りは元の関数と同じ
      # （以下略、既存の関数の内容を維持）
      # モジュール固有のログは上書きモードで（既存ファイルを削除）
      if (fs::file_exists(module_log_file)) {
        fs::file_delete(module_log_file)
      }
      
      # モジュール固有のログファイルへのアペンダー（上書きモード）
      appender_module <- futile.logger::appender.file(module_log_file)
      
      # _targets.log への出力はテスト時には行わない
      if (Sys.getenv("TEST_MODE") == "TRUE") {
        final_appender <- appender_module
      } else {
        # 通常の実行時は _targets.log にも出力
        targets_log_file <- fs::path(log_dir, "_targets.log")
        
        # _targets.log へのアペンダー（追記モード）- _targets.Rで初期化される前提
        appender_targets <- if (fs::file_exists(targets_log_file)) {
          # 追記モードのアペンダー
          function(line) {
            cat(line, file = targets_log_file, append = TRUE)
          }
        } else {
          # ファイルが存在しない場合はディレクトリを作成して新規作成
          if (!fs::dir_exists(fs::path_dir(targets_log_file))) {
            fs::dir_create(fs::path_dir(targets_log_file), recurse = TRUE)
          }
          function(line) {
            cat(line, file = targets_log_file, append = FALSE)
          }
        }
        
        # カスタムTeeアペンダーを使用して両方のファイルに書き込む
        final_appender <- appender_tee_custom(appender_module, appender_targets)
      }
      
      # レイアウト関数を定義（layout.format の代わりに直接関数を定義）
      final_layout <- function(level, msg, ...) {
        # level: ログレベル（INFO, ERROR など）
        # msg: ログメッセージ
        # ...: その他のパラメータ
        
        # メッセージ内の書式指定子を処理
        if (length(list(...)) > 0) {
          # flog.debug などに渡された追加パラメータがある場合、それらを使ってフォーマット
          msg <- do.call(sprintf, c(list(msg), list(...)))
        }
        
        # 最終的なログメッセージ形式を作成
        formatted_msg <- sprintf("[%s] [%s] [%s] %s\n", 
                                format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                                level,
                                module_name,
                                msg)
        return(formatted_msg)
      }
      
      # ログレベル (文字列を返す)
      log_level_upper <- toupper(log_level)
      valid_levels <- c("TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL")
      if (!(log_level_upper %in% valid_levels)) {
        warning(sprintf("無効なログレベル '%s' が指定されました。デフォルトの 'TRACE' を使用します。", log_level))
        log_level_upper <- "TRACE"
      }
      
      # 設定をリストで返す
      return(
        list(
          appender = final_appender,
          layout = final_layout,
          threshold = log_level_upper,
          module_log_path = module_log_file # 呼び出し元で参照できるようにパスも返す
        )
      )
    }
    
    # record_pipeline_history関数をレンダリング環境に追加
    # Rmdファイル内で定義された関数と同じ実装
    render_env$record_pipeline_history <- function(se, module_name, description, parameters) {
      # パイプライン履歴リストが存在しない場合は初期化
      if (is.null(metadata(se)$pipeline_history)) {
        metadata(se)$pipeline_history <- list()
      }
      
      # モジュール実行情報を記録
      metadata(se)$pipeline_history[[module_name]] <- list(
        module = module_name,
        timestamp = format(Sys.time(), '%Y-%m-%d %H:%M:%S'),
        description = description,
        parameters = parameters,
        session_info = capture.output(sessionInfo())
      )
      
      return(se)
    }
    
    rmarkdown::render(
      input = normalizePath(input_rmd_path, mustWork = TRUE),
      output_file = normalizePath(output_file_path, mustWork = FALSE),
      params = params_list,
      envir = render_env,
      quiet = !debug,
      output_format = "html_document",
      knit_root_dir = project_root
    )
    
    # Rmdの最後のチャンクがオブジェクトを返すと仮定
    if (exists("last_value", envir = render_env, inherits = FALSE)) {
      return(render_env$last_value)
    } else if (exists("se", envir = render_env, inherits = FALSE)) {
      # create_se.Rmdは最後に`return(se)`しているので、last_valueではなくseで取得できるはず
      return(render_env$se)
    } else if (exists("output_se", envir = render_env, inherits = FALSE)) {
      # subset_se.Rmdでは output_se という名前で返す
      return(render_env$output_se)
    } else {
      warning("Rmd did not return an object named 'last_value', 'se', or 'output_se'.")
      return(NULL)
    }
  }
  
  # biomaRtのモックを適用しながらレンダリング
  with_biomart_mock({
    render_rmd_and_get_last_value(input_rmd_path, output_file_path, params_list, debug)
  })
}

# パスが絶対パスかどうかを判定する関数
is.absolute_path <- function(path) {
  if (is.null(path) || path == "") return(FALSE)
  substr(path, 1, 1) == "/" || 
  substr(path, 1, 1) == "~" || 
  grepl("^[A-Za-z]:", path)
}

#' テスト用protein_coding遺伝子のライブラリサイズを計算する関数
#' 
#' @param se SummarizedExperimentオブジェクト
#' @return ライブラリサイズのベクトル、またはNULL
calculate_protein_coding_library_size <- function(se) {
  if (!"gene_biotype" %in% colnames(rowData(se))) {
    warning("rowDataに'gene_biotype'列が存在しません")
    return(NULL)
  }
  
  # protein_coding遺伝子の抽出
  is_protein_coding <- rowData(se)$gene_biotype == "protein_coding"
  
  # NA値をFALSEに変換
  is_protein_coding[is.na(is_protein_coding)] <- FALSE
  
  # protein_coding遺伝子が0件の場合は分析終了
  if (sum(is_protein_coding) == 0) {
    warning("protein_coding遺伝子が0件のため、ライブラリサイズを計算できません")
    return(NULL)
  }
  
  # protein_coding遺伝子のみのカウントを取得
  # drop = FALSEを指定して確実に行列として保持
  protein_coding_counts <- assay(se, "counts")[is_protein_coding, , drop = FALSE]
  
  # サンプルごとの合計カウントを計算
  library_sizes <- colSums(protein_coding_counts)
  return(library_sizes)
}

# テスト用のダミーデータファイル作成
# この関数はテスト開始時に必要なテストデータを全て作成する
create_test_dummy_files <- function(test_data_dir) {
  # ダミーデータのパス (プロジェクトルート基準)
  dummy_counts_path <- file.path(test_data_dir, "counts_test.csv")
  dummy_metadata_path <- file.path(test_data_dir, "metadata_test.csv")
  dummy_counts_mismatch_path <- file.path(test_data_dir, "counts_mismatch.csv")
  dummy_metadata_mismatch_path <- file.path(test_data_dir, "metadata_mismatch.csv")
  
  # 基本的なテストデータ作成
  if (!file.exists(dummy_counts_path)) {
    readr::write_csv(
      data.frame(gene_id = c("ENSG000001", "ENSG000002"), sample1 = c(10L, 20L), sample2 = c(30L, 40L)),
      dummy_counts_path
    )
  }
  
  if (!file.exists(dummy_metadata_path)) {
    readr::write_csv(
      data.frame(sample_id = c("sample1", "sample2"), condition = c("control", "treatment"), extra_col = c("A", "B")),
      dummy_metadata_path
    )
  }
  
  # サンプルIDが一致しないデータ
  if (!file.exists(dummy_counts_mismatch_path)) {
    readr::write_csv(
      data.frame(gene_id = c("ENSG000001", "ENSG000002"), sample1 = c(10L, 20L), sample3 = c(30L, 40L)),
      dummy_counts_mismatch_path
    )
  }
  
  if (!file.exists(dummy_metadata_mismatch_path)) {
    readr::write_csv(
      data.frame(sample_id = c("sample1", "sample2"), condition = c("control", "treatment"), extra_col = c("A", "B")),
      dummy_metadata_mismatch_path
    )
  }
} 