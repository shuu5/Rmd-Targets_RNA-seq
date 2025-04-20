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
#' @return Rmdの最後の値またはseオブジェクト
render_with_biomart_mock <- function(input_rmd_path, output_file_path, params_list, debug = FALSE) {
  # ヘルパー関数: Rmdをレンダリングして結果を取得
  render_rmd_and_get_last_value <- function(input_rmd_path, output_file_path, params_list, debug = FALSE) {
    render_env <- new.env(parent = globalenv())
    rmarkdown::render(
      input = fs::path_abs(input_rmd_path),
      output_file = fs::path_abs(output_file_path),
      params = params_list,
      envir = render_env,
      quiet = !debug,
      output_format = "html_document",
      knit_root_dir = here::here()
    )
    
    # Rmdの最後のチャンクがオブジェクトを返すと仮定
    if (exists("last_value", envir = render_env, inherits = FALSE)) {
      return(render_env$last_value)
    } else if (exists("se", envir = render_env, inherits = FALSE)) {
      # create_se.Rmdは最後に`return(se)`しているので、last_valueではなくseで取得できるはず
      return(render_env$se)
    } else {
      warning("Rmd did not return an object named 'last_value' or 'se'.")
      return(NULL)
    }
  }
  
  # biomaRtのモックを適用しながらレンダリング
  with_biomart_mock({
    render_rmd_and_get_last_value(input_rmd_path, output_file_path, params_list, debug)
  })
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