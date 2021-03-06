#' Delete Credentials
#'
#' Delete all the credentials according to a specific user. The credentials
#' are saved in the path `rgee::ee_get_earthengine_path()` after running
#' successfully at least once  `ee_Initialize(...)`. However, if you run
#' `ee_Initialize(...)` with the same email argument the new credentials
#' will be overwritten.
#' @param email Character (optional, e.g. `data.colec.fbf@gmail.com`).
#' The directory (all user credentials) to delete.
#' @param quiet Logical (optional). Suppress info messages.
#' @examples {
#' \dontrun{
#' ee_remove_credentials()
#' ee_remove_credentials('data.colec.fbf@gmail.com')
#' }
#' }
#' @export
ee_remove_credentials <- function(email='not_defined', quiet=FALSE) {
  ee_path <- path.expand("~/.config/earthengine")
  email_clean <- gsub("@gmail.com", "", email)
  if (email == 'not_defined') {
    email_clean <- 'ndef'
  }

  path_to_delete <- sprintf("%s/%s", ee_path, email_clean)

  if (!dir.exists(path_to_delete)) {
    cat('The path:', path_to_delete, ' does not exist!\n')
  }

  if (!quiet && dir.exists(path_to_delete)) {
    cat(
      sprintf("Credentials in %s has been deleted.\n",
              sprintf("%s/%s", ee_path, email_clean)))
  }

  unlink(x = path_to_delete, recursive = TRUE, force = TRUE)
  unlink(list.files(ee_path, "@gmail.com", full.names = TRUE))
  unlink(list.files(ee_path, ".json", full.names = TRUE))
  unlink(list.files(ee_path, "credentials", full.names = TRUE))
  unlink(list.files(ee_path, "rgee_sessioninfo.txt", full.names = TRUE))

  invisible(TRUE)
}


#' Delete chromedriver
#'
#' @param quiet Logical (optional). Suppress info messages.
#' @examples
#' \dontrun{
#' library(rgee)
#' ee_remove_ChromeDriver()
#' }
#' @export
ee_remove_ChromeDriver <- function(quiet = FALSE) {
  ee_path <- path.expand("~/.config/earthengine/")
  gecko_driver_linux <- sprintf("%s/chromedriver", ee_path)
  gecko_driver_win <- sprintf("%s/chromedriver.exe", ee_path)
  if (file.exists(gecko_driver_win)) file.remove(gecko_driver_win)
  if (file.exists(gecko_driver_linux)) file.remove(gecko_driver_linux)
  condition_exist <- file.exists(gecko_driver_linux) |
    file.exists(gecko_driver_win)
  if (!quiet & condition_exist) {
    cat(sprintf("GoogleDrive driver in %s has been removed.\n", ee_path))
  } else {
    cat("The file chromedriver does not exist.\n")
  }
  invisible(TRUE)
}

#' Remove reticulate system variables from .Renviron
#'
#' @examples
#' \dontrun{
#' library(rgee)
#' ee_remove_driver()
#' }
#' @export
ee_clean_pyenv <- function() {
  # Read line by line .Renviron
  home <- Sys.getenv("HOME")
  renv <- file.path(home, ".Renviron")
  if (file.exists(renv)) {
    # Backup original .Renviron before doing anything else here.
    file.copy(renv, file.path(home, ".Renviron_backup"))

    con <- file(renv, open = "r")
    lines <- as.character()
    ii <- 1

    while (TRUE) {
      line <- readLines(con, n = 1, warn = FALSE)
      if (length(line) == 0) {
        break()
      }
      lines[ii] <- line
      ii <- ii + 1
    }

    # Remove system variables
    # RETICULATE_PYTHON & RETICULATE_PYTHON_ENV
    system_vars <- lines[!grepl("RETICULATE_PYTHON", lines)]
    fileConn <- file(renv)
    writeLines(system_vars, fileConn)
    close(fileConn)
  }
  invisible(TRUE)
}
