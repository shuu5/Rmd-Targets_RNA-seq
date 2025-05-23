#!/usr/bin/env Rscript

# コマンドライン引数を解析
args <- commandArgs(trailingOnly = TRUE)

# ヘルプメッセージ
print_usage <- function() {
  message("Usage: Rscript generate_vis_png.R --output <output_png_file> [tar_visnetwork_options...]")
  message("Example: Rscript generate_vis_png.R --output network.png targets_only=TRUE label=\"branches\"")
  message("\nOptions for tar_visnetwork:")
  message("  Pass any valid argument for targets::tar_visnetwork() as key=value pairs.")
  message("  Example: targets_only=TRUE, label=\"name\", level_separation=200")
  message("\nRequired argument:")
  message("  --output <filename> : Specify the output PNG file name.")
  quit(status = 1)
}

# --output 引数を探す
output_file_index <- which(args == "--output")
if (length(output_file_index) == 0 || output_file_index == length(args)) {
  message("Error: --output argument is missing or has no value.")
  print_usage()
}
output_png_file <- args[output_file_index + 1]
# --output とその値を args から削除
args <- args[-c(output_file_index, output_file_index + 1)]

# 残りの引数を tar_visnetwork オプションとして解析
visnetwork_args_str <- paste(args, collapse = ", ")

# デバッグ用: 引数を表示
message("Output file: ", output_png_file)
message("Arguments for tar_visnetwork: ", visnetwork_args_str)

# 必要なパッケージをロード
# rmd_rule.mdc ルール 6 に従い、必要なライブラリを明示的に読み込む
# suppressPackageStartupMessages で読み込み時のメッセージを抑制
suppressPackageStartupMessages({
  library(targets)
  library(visNetwork)
  library(webshot2)
  library(chromote)
})

# tar_visnetwork() を呼び出して visNetwork オブジェクトを取得
message("Calling targets::tar_visnetwork()...")
vis_obj <- tryCatch({
  eval(parse(text = paste0("targets::tar_visnetwork(", visnetwork_args_str, ")")))
}, error = function(e) {
  message("Error calling tar_visnetwork: ", e$message)
  quit(status = 1)
})
message("tar_visnetwork() successful.")

# visNetwork オブジェクトを一時的な HTML ファイルとして保存
html_file <- tempfile(fileext = ".html")
message("Saving visNetwork object to temporary HTML: ", html_file)
tryCatch({
  visNetwork::visSave(vis_obj, file = html_file, selfcontained = TRUE)
}, error = function(e) {
  message("Error saving visNetwork to HTML: ", e$message)
  quit(status = 1)
})
message("HTML saved successfully.")


# HTML ファイルを PNG 画像としてスクリーンショット撮影
message("Initializing ChromoteSession...")
b <- tryCatch({
  # 環境変数やオプションでポートを指定できるようにするなど、将来的な改善の余地あり
  ChromoteSession$new()
}, error = function(e) {
  message("Error initializing ChromoteSession: ", e$message)
  message("Ensure Chromium is installed and accessible.")
  # webshot (PhantomJS) fallback を試す場合はここにコードを追加
  quit(status = 1) # Chromote が使えなければ終了
})
message("ChromoteSession initialized.")

# --- 追加: on.exit による確実なクリーンアップ ---
# セッションが正常に作成されたら、関数の終了時に必ず close するように登録
if (!is.null(b) && b$is_active()) {
    on.exit( {
        message("Ensuring ChromoteSession is closed via on.exit()...")
        # on.exit が呼ばれる時点でもう一度アクティブか確認するのがより安全
        if (!is.null(b) && b$is_active()) {
            tryCatch({ # close 自体でエラーが起きる可能性も考慮
                b$close()
                message("ChromoteSession closed successfully via on.exit().")
            }, error = function(close_e) {
                message("Error closing ChromoteSession during on.exit(): ", close_e$message)
            })
        } else {
            message("ChromoteSession was already inactive or null upon on.exit().")
        }
    }, add = TRUE)
    message("Registered ChromoteSession cleanup via on.exit().")
}
# --- ここまで ---

# セッションがアクティブか確認
if (!b$is_active()) {
    message("Error: ChromoteSession is not active.")
    quit(status = 1)
}


tryCatch({
  message("Navigating to HTML file: ", paste0("file://", html_file))
  # ページナビゲーションと読み込み完了待ち
  b$Page$navigate(paste0("file://", html_file), wait_ = FALSE)
  message("Waiting for page load event (timeout 120s)...") # タイムアウトを延長
  load_event <- b$Page$loadEventFired(wait_ = TRUE, timeout = 120) # タイムアウトを120秒に設定

  if (is.null(load_event)) {
      message("Error: Page load timed out after 120 seconds.")
      b$close()
      quit(status = 1)
  }
  message("Page loaded successfully.")

  # 少し待機時間を設ける (レンダリングのため)
  Sys.sleep(5) # 5秒待機

  message("Taking screenshot and saving to: ", output_png_file)
  # スクリーンショットを撮る (セレクターを明示的に指定)
  screenshot_result <- b$screenshot(output_png_file, selector = "html", wait_ = TRUE)

  # screenshot の結果を確認 (成功すれば TRUE or ファイルパス、失敗すれば FALSE or NULL)
  if (is.logical(screenshot_result) && !screenshot_result) {
      message("Error: Screenshot failed.")
      b$close()
      quit(status = 1)
  }

  message("Network graph saved successfully to '", output_png_file, "'.")

}, error = function(e) {
  message("Error during screenshot process: ", e$message)
  # webshot (PhantomJS) fallback を試す場合はここにコードを追加
  # 現状では Chromote でのエラーはスクリプト失敗とする
  # on.exit がクリーンアップを行うため、ここでの close 処理は不要
  # if (!is.null(b) && b$is_active()) {
  #     b$close()
  # }
  quit(status = 1)
})

# --- 削除: on.exit に処理を移譲 ---
# ChromoteSession を閉じる
# message("Closing ChromoteSession...")
# if (!is.null(b) && b$is_active()) { # on.exitで処理されるため不要
#   b$close()
# }
# --- ここまで ---

# 一時 HTML ファイルを削除 (任意)
# unlink(html_file) # デバッグ中は残しておくと便利

message("Script finished successfully.")
quit(status = 0) # 正常終了
