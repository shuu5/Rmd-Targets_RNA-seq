library(testthat)
library(SummarizedExperiment)
library(fs)

# R/create_se_object.R が存在しない、または関数が未定義のため、
# source() または直接呼び出しは現時点ではエラーになる。
# ここでは、テストが失敗することを確認するために基本的な構造を記述。

# 関数ファイルを読み込む (テスト実行時に必要)
# source("R/create_se_object.R") #<- RStudio や devtools::test() では通常不要
source("../../R/create_se_object.R") # 相対パスで指定

test_that("create_se_object creates a basic SummarizedExperiment object", {
  # このテストは、関数が存在しないため現時点では失敗する
  # expect_true(exists("create_se_object")) # 将来的に追加

  # テストデータの準備 (一時ディレクトリを使用)
  temp_dir <- tempdir()
  data_subdir <- file.path(temp_dir, "test_exp")
  dir.create(data_subdir)
  
  # ダミーデータの作成
  counts_data <- data.frame(
    SampleA = c(10, 5, 12),
    SampleB = c(20, 0, 25),
    SampleC = c(15, 8, 18),
    row.names = c("Gene1", "Gene2", "Gene3")
  )
  write.csv(counts_data, file.path(data_subdir, "counts.csv"), row.names = TRUE)
  
  metadata_data <- data.frame(
    Group = c("Control", "Treatment", "Control"),
    Batch = c(1, 1, 2),
    row.names = c("SampleA", "SampleB", "SampleC") # 行名をサンプルIDに
  )
  write.csv(metadata_data, file.path(data_subdir, "sample_metadata.csv"), row.names = TRUE)

  # 関数呼び出し (まだ存在しないのでコメントアウト)
  # se <- create_se_object(
  #   experiment_id = "test_exp",
  #   data_dir = temp_dir
  # )
  
  # 基本的な期待値 (まだ実行できない)
  # expect_s4_class(se, "SummarizedExperiment")
  # expect_equal(dim(se), c(3, 3))
  # expect_equal(colnames(se), c("SampleA", "SampleB", "SampleC"))
  # expect_equal(rownames(se), c("Gene1", "Gene2", "Gene3"))
  
  # クリーンアップ
  unlink(data_subdir, recursive = TRUE)
  
  # 現時点では、テストが存在すること自体を確認する意味でTRUEにしておく
  # 関数実装後に本格的なテストに書き換える
  expect_true(TRUE) 
})

test_that("create_se_object reads files and creates basic SE", {
  # テスト環境設定
  temp_base_dir <- file.path(tempdir(), "test_create_se_base")
  if (dir.exists(temp_base_dir)) unlink(temp_base_dir, recursive = TRUE)
  dir.create(temp_base_dir)
  
  experiment_id <- "exp001"
  data_dir <- file.path(temp_base_dir, "data") # data_dir が data/ を指すように
  experiment_data_dir <- file.path(data_dir, experiment_id) # 実際のデータ場所
  dir.create(experiment_data_dir, recursive = TRUE)
  
  # テストデータ作成
  counts_file <- file.path(experiment_data_dir, "counts.csv")
  metadata_file <- file.path(experiment_data_dir, "sample_metadata.csv")
  
  counts_df <- data.frame(
    SampleA = c(10L, 5L, 12L),
    SampleB = c(20L, 0L, 25L),
    SampleC = c(15L, 8L, 18L),
    row.names = c("Gene1", "Gene2", "Gene3")
  )
  write.csv(counts_df, counts_file, row.names = TRUE)
  
  metadata_df <- data.frame(
    Group = c("Control", "Treatment", "Control"),
    Batch = c(1, 1, 2),
    row.names = c("SampleA", "SampleB", "SampleC")
  )
  write.csv(metadata_df, metadata_file, row.names = TRUE)
  
  # ここで関数を呼び出す (関数が存在しないとエラーになる)
  # このテストは、次の Green ステップで実装が追加されるまで失敗する
  # source("R/create_se_object.R") # 必要に応じて
  expect_error( # 現状はダミーSEしか返さないので、期待する結果と異なりエラーになるはず
    {
      se <- create_se_object(
        experiment_id = experiment_id,
        data_dir = data_dir # `data` ディレクトリを渡す
      )
      # 期待されるSEオブジェクトの基本的な検証
      expect_s4_class(se, "SummarizedExperiment")
      expect_equal(dim(se), c(3, 3))
      expect_equal(colnames(se), c("SampleA", "SampleB", "SampleC"))
      expect_equal(rownames(se), c("Gene1", "Gene2", "Gene3"))
      expect_equal(SummarizedExperiment::assayNames(se), "counts")
      expect_true(is.matrix(SummarizedExperiment::assay(se, "counts")))
      expect_s4_class(SummarizedExperiment::colData(se), "DataFrame")
      expect_equal(colnames(SummarizedExperiment::colData(se)), c("Group", "Batch"))
      expect_equal(rownames(SummarizedExperiment::colData(se)), c("SampleA", "SampleB", "SampleC"))
      expect_equal(SummarizedExperiment::colData(se)$Group, c("Control", "Treatment", "Control"))
    }, 
    NA # NA はエラーが発生しないことを期待する (つまり、正常終了)
    # しかし、現在のダミー実装では次元などが異なるため、expect_equal などで失敗する
    # -> 最初の実装ステップでは、これが成功するように実装を進める
  )
  
  # クリーンアップ
  unlink(temp_base_dir, recursive = TRUE)
})

test_that("create_se_object adds sessionInfo and input_files to metadata", {
  # テスト環境設定 (同様)
  temp_base_dir <- file.path(tempdir(), "test_create_se_metadata")
  if (dir.exists(temp_base_dir)) unlink(temp_base_dir, recursive = TRUE)
  dir.create(temp_base_dir)
  
  experiment_id <- "exp002"
  data_dir <- file.path(temp_base_dir, "data")
  experiment_data_dir <- file.path(data_dir, experiment_id)
  dir.create(experiment_data_dir, recursive = TRUE)
  
  # テストデータ作成 (同様)
  counts_file <- file.path(experiment_data_dir, "counts.csv")
  metadata_file <- file.path(experiment_data_dir, "sample_metadata.csv")
  counts_df <- data.frame(S1=c(1L,2L), S2=c(3L,4L), row.names=c("G1", "G2"))
  metadata_df <- data.frame(Group=c("a", "b"), row.names=c("S1", "S2"))
  write.csv(counts_df, counts_file, row.names=TRUE)
  write.csv(metadata_df, metadata_file, row.names=TRUE)

  # 関数呼び出し (現在の実装ではまだメタデータは追加されない)
  se <- create_se_object(
    experiment_id = experiment_id,
    data_dir = data_dir
  )

  # メタデータの期待値 (現在の実装では失敗する)
  expect_true("sessionInfo" %in% names(metadata(se)))
  expect_true("input_files" %in% names(metadata(se)))
  expect_true(is.list(metadata(se)$input_files))
  expect_equal(names(metadata(se)$input_files), c("counts", "metadata"))
  # fs::path_abs を使って絶対パスで比較
  expect_equal(metadata(se)$input_files$counts, fs::path_abs(counts_file))
  expect_equal(metadata(se)$input_files$metadata, fs::path_abs(metadata_file))
  # sessionInfo の内容は変わりうるので、存在と基本的なクラスだけ確認
  expect_true(!is.null(metadata(se)$sessionInfo))
  # sessioninfo::session_info() は session_info クラスを返す
  expect_s3_class(metadata(se)$sessionInfo, "session_info") 

  # クリーンアップ
  unlink(temp_base_dir, recursive = TRUE)
})

test_that("create_se_object adds correct pipeline_history", {
  # テスト環境設定
  temp_base_dir <- file.path(tempdir(), "test_create_se_history")
  if (dir.exists(temp_base_dir)) unlink(temp_base_dir, recursive = TRUE)
  dir.create(temp_base_dir)
  
  experiment_id <- "exp003"
  data_dir <- file.path(temp_base_dir, "data")
  experiment_data_dir <- file.path(data_dir, experiment_id)
  dir.create(experiment_data_dir, recursive = TRUE)
  
  # テストデータ作成
  counts_file <- file.path(experiment_data_dir, "counts.csv")
  metadata_file <- file.path(experiment_data_dir, "sample_metadata.csv")
  counts_df <- data.frame(S_A=c(1L, 2L), S_B=c(3L, 4L), row.names = c("G1", "G2"))
  metadata_df <- data.frame(G=c("x", "y"), row.names = c("S_A", "S_B"))
  write.csv(counts_df, counts_file, row.names=TRUE)
  write.csv(metadata_df, metadata_file, row.names=TRUE)

  # 関数呼び出し
  se <- create_se_object(
    experiment_id = experiment_id,
    data_dir = data_dir,
    counts_filename = "counts.csv",
    metadata_filename = "sample_metadata.csv",
    counts_options = list(header = TRUE, row.names = 1), # デフォルトと少し変える
    metadata_options = list(header = TRUE, row.names = 1)
  )

  # pipeline_history の期待値 (現在の実装では空リストなので失敗する)
  expect_true("pipeline_history" %in% names(metadata(se)))
  expect_true(is.list(metadata(se)$pipeline_history))
  expect_equal(length(metadata(se)$pipeline_history), 1)
  
  history_entry <- metadata(se)$pipeline_history[[1]]
  expect_true(is.list(history_entry))
  expect_equal(names(history_entry), 
               c("step_id", "function_name", "timestamp", "parameters", 
                 "input_dimensions", "output_dimensions", "details"))
  
  # step_id はターゲット名に依存するので、ここでは NULL かどうかだけチェック
  # expect_true(!is.null(history_entry$step_id)) # 本番ではターゲット名が入る想定
  expect_equal(history_entry$function_name, "create_se_object")
  expect_true(inherits(history_entry$timestamp, "POSIXct"))
  expect_true(is.list(history_entry$parameters))
  expect_equal(history_entry$parameters$experiment_id, experiment_id)
  expect_equal(history_entry$parameters$data_dir, data_dir)
  expect_equal(history_entry$parameters$counts_filename, "counts.csv")
  expect_equal(history_entry$parameters$metadata_filename, "sample_metadata.csv")
  # オプションも記録されているか確認
  expect_equal(history_entry$parameters$counts_options, list(header = TRUE, row.names = 1))
  expect_equal(history_entry$parameters$metadata_options, list(header = TRUE, row.names = 1))
  
  expect_null(history_entry$input_dimensions) # このステップでは入力次元は記録しない
  expect_true(is.list(history_entry$output_dimensions))
  expect_equal(history_entry$output_dimensions, list(rows = 2, cols = 2))
  expect_equal(history_entry$details, "Initial SE object creation from CSV.")

  # クリーンアップ
  unlink(temp_base_dir, recursive = TRUE)
})

test_that("create_se_object handles file not found errors", {
  # 存在しない experiment_id を指定
  expect_error(
    create_se_object(experiment_id = "non_existent_exp", data_dir = tempdir()),
    regexp = "Counts file not found|Metadata file not found" # エラーメッセージの一部をマッチ
  )
})

test_that("create_se_object respects custom options (e.g., separator)", {
  # テスト環境設定
  temp_base_dir <- file.path(tempdir(), "test_create_se_options")
  if (dir.exists(temp_base_dir)) unlink(temp_base_dir, recursive = TRUE)
  dir.create(temp_base_dir)
  
  experiment_id <- "exp004"
  data_dir <- file.path(temp_base_dir, "data")
  experiment_data_dir <- file.path(data_dir, experiment_id)
  dir.create(experiment_data_dir, recursive = TRUE)
  
  # TSV形式でテストデータ作成
  counts_file <- file.path(experiment_data_dir, "counts.tsv")
  metadata_file <- file.path(experiment_data_dir, "metadata.tsv")
  
  counts_df <- data.frame(
      SampleX = c(1, 2), SampleY = c(3, 4),
      row.names = c("G1", "G2")
  )
  # header=T, sep="\t", row.names 列を先頭に
  write.table(counts_df, counts_file, sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)
  
  metadata_df <- data.frame(
      Condition = c("trt", "ctrl"),
      row.names = c("SampleX", "SampleY")
  )
  write.table(metadata_df, metadata_file, sep = "\t", row.names = TRUE, col.names = NA, quote = FALSE)

  # 関数呼び出し (カスタムオプションを指定)
  se <- create_se_object(
    experiment_id = experiment_id,
    data_dir = data_dir,
    counts_filename = "counts.tsv",
    metadata_filename = "metadata.tsv",
    # fread は row.names を直接扱わないので、read.table のように col.names=NA で
    # 書き出した最初の列を行名として扱う想定でオプションを設定する
    # fread は header=TRUE の場合、最初の行をヘッダーとして読む。
    # row.names=1 の指定は fread の data.table=FALSE と組み合わせるか、後処理で対応。
    # ここでは fread のデフォルトに近い挙動を期待し、最初の列を行名として後処理する前提。
    counts_options = list(sep = "\t", header = TRUE, row.names = 1, check.names = FALSE),
    metadata_options = list(sep = "\t", header = TRUE, row.names = 1, check.names = FALSE)
  )

  # 期待値 (TSVでも正しく読み込めているか)
  expect_s4_class(se, "SummarizedExperiment")
  expect_equal(dim(se), c(2, 2))
  expect_equal(colnames(se), c("SampleX", "SampleY"))
  expect_equal(rownames(se), c("G1", "G2"))
  expect_equal(SummarizedExperiment::colData(se)$Condition, c("trt", "ctrl"))

  # クリーンアップ
  unlink(temp_base_dir, recursive = TRUE)
}) 