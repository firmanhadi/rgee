#' Is x a vector or a raster?
#' @noRd
image_or_vector <- function(x) {
  isvector <- try(st_read(x), silent = T)
  if (any(class(isvector) %in% "try-error")) {
    israster <- try(read_stars(x), silent = T)
    if (any(class(israster) %in% "try-error")) {
      return(NULL)
    }
    return("stars")
  }
  return("sf")
}

#' Pass a foreign Image format to GEOTIFF
#' @param gee_asset_file filename in google earth engine asset
#' @noRd
ee_raster_to_tif <- function(x) {
  # is_a_tif <- mapply(grepl, x ,MoreArgs = list(pattern = "\\.tif$"))
  tif <- grepl(pattern = "\\.tif$", x)
  if (tif) {
    return(x)
  } else {
    if (!requireNamespace("raster", quietly = TRUE)) {
      stop("The image (", x, ") is not a GEOTIFF file, The raster package",
        " is required to fix it internally.",
        call. = FALSE
      )
    } else {
      tif_file <- tempfile()
      newtif <- paste0(tif_file, ".tif")
      raster::writeRaster(raster::raster(x), newtif)
      return(newtif)
    }
  }
}

#' Pass a foreign vector format to ESRI shapefile
#' @param gee_asset_file filename in google earth engine asset
#' @noRd
ee_vector_to_shapefile <- function(x) {
  # is_a_tif <- mapply(grepl, x ,MoreArgs = list(pattern = "\\.shp$"))
  shp <- grepl(pattern = "\\.shp$", x)
  if (shp) {
    return(x)
  } else {
    shp_file <- tempfile()
    newshp <- paste0(shp_file, ".shp")
    write_sf(st_read(x), newshp)
    return(newshp)
  }
}

#' Create a zip file from a ESRI shapefile
#' @param x .shp fullname
#' @param SHP_EXTENSIONS are suffix: c("dbf", "prj", "shp", "shx")
#' @noRd
create_shp_zip <- function(x, SHP_EXTENSIONS = c("dbf", "prj", "shp", "shx")) {
  temp_dir <- tempdir()
  shp_basename <- gsub("\\.shp$", "", x)
  shp_filenames <- sprintf("%s.%s", shp_basename, SHP_EXTENSIONS)
  zipname <- sprintf("%s.zip", shp_basename)
  zip(zipfile = zipname, files = shp_filenames, flags = "-j")
  temp_zip <- sprintf("%s/%s", temp_dir, basename(zipname))
  if (getwd() != dirname(zipname)) {
    file.copy(from = zipname, to = temp_zip, overwrite = TRUE)
    file.remove(zipname)
  }
  return(temp_zip)
}

#' Upload local files to google cloud storage
#'
#' Upload images or tables into google cloud storage for EE asset ingestion
#' tasks.
#'
#' @param x filename (character), sf or stars object.
#' @param bucket bucketname you are uploading to
#' @param selenium_params List. Optional parameters when bucket is NULL.
#' Parameters for setting selenium. See details.
#' @param clean Logical; Whether is TRUE cache will cleaned, see Details.
#' @param reinit Logical; run ee_Initialize(gcs=TRUE) before start to upload
#' @param quiet Logical. Suppress info message.
#' @importFrom getPass getPass
#' @details
#' It is necessary, for uploading process, get authorization to read & write
#' into a Google Cloud Storage (GCS) bucket. Earth Engine provides a provisional
#' for free space into GCS through gs://earthengine-uploads/. If the bucket
#' argument is absent, this function will use Selenium driver for getting access
#' to the URI mentioned bellow. The process for getting access to
#' gs://earthengine-uploads/ was written entirely in Python and is as follow:
#' \itemize{
#'  \item{1. }{Connecting to https://code.earthengine.google.com/
#'  through selenium.}
#'  \item{2. }{Download all the cookies and saved in a request object.}
#'  \item{3. }{Get the URL for ingest the data  temporarily.}
#'  \item{4. }{Create the request headers.}
#'  \item{5. }{Upload the x argument to GCS via POST request.}
#' }
#' @importFrom rgdal showWKT
#' @return Character indicating the full name of the x argument inside
#' gs://earthengine-uploads/
#' @export
ee_upload_file_to_gcs <- function(x,
                                  bucket = NULL,
                                  selenium_params = getOption(
                                    "rgee.selenium.params"
                                  ),
                                  clean = FALSE,
                                  reinit = FALSE,
                                  quiet = FALSE) {
  if (selenium_params$check_driver) {
    check_warning <- tryCatch(
      expr = ee_check_drivers(),
      warning = function(w) w
    )

    if (is(check_warning, "warning")) {
      stop(
        "'chromedriver' executable needs to be in the path: ",
        rgee::ee_get_earthengine_path(),
        ".The appropriate version of chromedriver depends on your GoogleChrome",
        "version. \n\n>>> Figure out GoogleChrome version of their system  on:",
        "chrome://settings/help\n >>> After that choose a stable version of",
        "chromedriver on:",
        "https://sites.google.com/a/chromium.org/chromedriver/downloads \n\n",
        "Once you are sure of the version of Google Chrome and chromedriver ",
        "of their system,\ntry rgee::ee_install_drivers(version=...). ",
        "For instance, if you are using Google Chrome v76.x might use ",
        "rgee::ee_install_drivers(version='76.0.3809.126') to fix the error"
      )
    }
  }

  if (image_or_vector(x) == "sf") {
    x %>%
      ee_vector_to_shapefile() %>%
      create_shp_zip() -> x
    x_type <- "shapefile"
  } else {
    x <- ee_raster_to_tif(x)
    x_type <- "tif"
  }

  if (is.null(bucket)) {
    oauth_func_path <- system.file("python/ee_selenium_functions.py",
      package = "rgee"
    )
    ee_selenium_functions <- ee_source_python(oauth_func_path)

    tempdir_gee <- tempdir()
    session_temp <- sprintf("%s/rgee_session_by_selenium.Rdata", tempdir_gee)

    # Geeting cookies from https://code.earthengine.google.com/
    if (file.exists(session_temp) && clean) {
      session <- ee_selenium_functions$load_py_object(session_temp)
    } else {
      if (!quiet) {
        cat(sprintf("GMAIL ACCOUNT: %s\n", selenium_params$email))
      }
      if (nchar(selenium_params$email_password) > 4) {
        password <- selenium_params$email_password
      } else {
        password <- getPass("GMAIL PASSWORD:")
      }
      if (!quiet) {
        if (!selenium_params$showpassword) {
          cat(
            "GMAIL PASSWORD:",
            paste(rep("*", nchar(password)), collapse = ""),
            "\n"
          )
        } else {
          cat("GMAIL PASSWORD:", password, "\n")
        }
      }
      if (!quiet) cat("Acquiring uploading permissions ... please wait\n")
      ee_path <- path.expand("~/.config/earthengine")
      session <- ee_selenium_functions$ee_get_google_auth_session_py(
        username = selenium_params$email,
        password = password,
        dirname = ee_path
      )
      cookies_names <- names(ee_py_to_r(session$cookies$get_dict()))
      if (!quiet) {
        cat(
          sprintf(
            "cookies catched: [%s]\n",
            paste0(cookies_names, collapse = ", ")
          )
        )
      }
      if (length(cookies_names) > 7) {
        ee_selenium_functions$save_py_object(session, session_temp)
      } else {
        warnings("The number of cookies is suspiciously low.")
      }
    }
    expected_cookies_name <- c(
      "APISID", "CONSENT", "HSID", "NID", "SACSID",
      "SAPISID", "SID", "SIDCC", "SSID"
    )
    # Geting URL ingestion
    upload_url <- tryCatch(expr = {
      upload_url <- ee_py_to_r(
        ee_selenium_functions$ee_get_upload_url_py(session)
      )
      count <- 1
      while (is.null(upload_url) & count < 5) {
        upload_url <- ee_py_to_r(
          ee_selenium_functions$ee_get_upload_url_py(session)
        )
        count <- count + 1
      }
      if (is.null(upload_url)) {
        stop(
          "Maybe due slow internet connection or a wrong google account ",
          "password. Expected cookies names need similar to this: \n [",
          paste0(expected_cookies_name, collapse = ", "), "]"
        )
      } else {
        if (nchar(upload_url) > 500) {
          stop(
            "Maybe due slow internet connection or a wrong google account ",
            "password. Expected cookies names need similar to this: \n [",
            paste0(expected_cookies_name, collapse = ", "), "]"
          )
        }
      }
      upload_url
    }, error = function(e) {
      message(
        "Error: Cleaning cache ... , was not possible get the URL to upload",
        " the data, run rgee::ee_upload_file_to_gcs again."
      )
      file.remove(session_temp)
    })

    if (!quiet) cat(sprintf("Uploading %s to gs://earthengine-uploads/ \n", x))
    gcs_uri <- ee_selenium_functions$ee_file_to_gcs_py(
      session, x, x_type,
      upload_url
    )
    return(gcs_uri)
  } else {
    if (!requireNamespace("googleCloudStorageR", quietly = TRUE)) {
      stop(
        "The googleCloudStorageR package is required to use ",
        "rgee::ee_download_gcs",
        call. = FALSE
      )
    } else {
      if (reinit) {
        ee_path <- path.expand("~/.config/earthengine")
        user <- read.table(
          file = sprintf("%s/rgee_sessioninfo.txt", ee_path),
          header = TRUE
        )[["user"]]
        ee_Initialize(email = user, gcs = TRUE)
      }

      googleCloudStorageR::gcs_global_bucket(bucket = bucket)
      googleCloudStorageR::gcs_auth(getOption("rgee.gcs.auth")) # init?
      googleCloudStorageR::gcs_upload(x, name = basename(x))
      gcs_uri <- sprintf("gs://%s/%s", bucket, basename(x))
      return(gcs_uri)
    }
  }
}

#' Pass a file of gcs to ee asset
#' @noRd
ee_gcs_to_asset <- function(x,
                            gs_uri,
                            filename,
                            type = "table",
                            properties = NULL,
                            start_time = "1970-01-01",
                            end_time = "1970-01-01",
                            pyramiding_policy = "MEAN") {
  oauth_func_path <- system.file(
    "python/ee_selenium_functions.py",
    package = "rgee"
  )
  ee_selenium_functions <- ee_source_python(oauth_func_path)
  tempdir_gee <- tempdir()

  if (type == "image") {
    # Creating affine_transform params
    affine_transform <- attr(x, "dimensions")
    shear <- x %>%
      attr("dimensions") %>%
      attr("raster")
    nbands <- (affine_transform$band$to - affine_transform$band$from) + 1L
    if (length(nbands) == 0) nbands <- 1
    band_names <- affine_transform$band$values
    if (is.null(band_names)) band_names <- sprintf("b%s", 1:nbands)
    name <- sprintf("projects/earthengine-legacy/assets/%s", filename)

    # Creating tileset
    tilesets <- list(
      crs = showWKT(st_crs(x)$proj4string),
      sources = list(
        list(
          uris = gs_uri,
          affine_transform = list(
            scale_x = affine_transform$x$delta,
            shear_x = shear$affine[1],
            translate_x = affine_transform$x$offset,
            shear_y = shear$affine[2],
            scale_y = affine_transform$y$delta,
            translate_y = affine_transform$y$offset
          )
        )
      )
    )

    # from R date to JS timestamp: time_start + time_end
    if (!is.null(start_time)) {
      time_start <- rdate_to_eedate(start_time, eeobject = FALSE)
    }

    if (!is.null(end_time)) {
      time_end <- rdate_to_eedate(end_time, eeobject = FALSE)
    }

    # Adding bands
    bands <- list()
    for (b in seq_len(length(band_names))) {
      bands[[b]] <- list(
        id = band_names[b],
        tileset_band_index = as.integer((b - 1))
      )
    }

    # Putting all together
    manifest <- list(
      name = name,
      tilesets = list(tilesets),
      bands = bands,
      pyramiding_policy = pyramiding_policy,
      properties = properties,
      start_time = list(seconds = time_start / 1000),
      end_time = list(seconds = time_end / 1000)
    )

    if (length(properties) == 0) manifest[["properties"]] <- NULL
    json_path <- sprintf("%s/manifest.json", tempdir_gee)
    ee_selenium_functions$ee_create_json_py(
      towrite = json_path,
      manifest = manifest
    )
    system(sprintf("earthengine upload image --manifest '%s'", json_path))
  } else if (type == "table") {
    system(sprintf(
      "earthengine upload table --asset_id %s '%s'",
      filename, gs_uri
    ))
  }
}
