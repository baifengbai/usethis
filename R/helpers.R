#' Use a usethis-style template
#'
#' Creates a file from data and a template found in a package. Provides control
#' over file name, the addition to `.Rbuildignore`, and opening the file for
#' inspection.
#'
#' This function can be used as the engine for a templating function in other
#' packages. The `template` argument is used along with the `package` argument
#' to determine the path to your template file; it will be expected at
#' `system.file("templates", template, package = package)`.
#'
#' To interpolate your data into the template, supply a list using
#' the `data` argument. Internally, this function uses
#' [whisker::whisker.render()] to combine your template file with your data.
#'
#' @param template Path to template file relative to `"templates"` directory
#'   within `package`; see details.
#' @param save_as Name of file to create. Defaults to `template`
#' @param data A list of data passed to the template.
#' @param ignore Should the newly created file be added to `.Rbuildignore`?
#' @param open Open the newly created file for editing? Happens in RStudio, if
#'   applicable, or via [utils::file.edit()] otherwise.
#' @param package Name of the package where the template is found.
#' @return A logical vector indicating if file was modified.
#' @export
#' @examples
#' \dontrun{
#'   # Note: running this will write `NEWS.md` to your working directory
#'   use_template(
#'     template = "NEWS.md",
#'     data = list(Package = "acme", Version = "1.2.3"),
#'     package = "usethis"
#'   )
#' }
use_template <- function(template,
                         save_as = template,
                         data = list(),
                         ignore = FALSE,
                         open = FALSE,
                         package = "usethis") {

  template_contents <- render_template(template, data, package = package)
  new <- write_over(proj_get(), save_as, template_contents)

  if (ignore) {
    use_build_ignore(save_as)
  }

  if (open) {
    edit_file(proj_get(), save_as)
  }

  invisible(new)
}

render_template <- function(template, data = list(), package = "usethis") {
  template_path <- find_template(template, package = package)
  strsplit(whisker::whisker.render(readLines(template_path), data), "\n")[[1]]
}

find_template <- function(template_name, package = "usethis") {
  path <- system.file("templates", template_name, package = package)
  if (identical(path, "")) {
    stop(
      "Could not find template ", value(template_name),
      " in package ", value(package),
      call. = FALSE
    )
  }
  path
}

project_data <- function(base_path = proj_get()) {
  if (is_package(base_path)) {
    package_data(base_path)
  } else {
    list(Project = basename(base_path))
  }
}

package_data <- function(base_path = proj_get()) {
  desc <- desc::description$new(base_path)

  out <- as.list(desc$get(desc$fields()))
  if (uses_github(base_path)) {
    out$github <- gh::gh_tree_remote(base_path)
  }
  out
}

project_name <- function(base_path = proj_get()) {
  desc_path <- file.path(base_path, "DESCRIPTION")

  if (file.exists(desc_path)) {
    desc::desc_get("Package", base_path)[[1]]
  } else {
    basename(normalizePath(base_path, mustWork = FALSE))
  }
}

use_description_field <- function(name,
                                  value,
                                  base_path = proj_get(),
                                  overwrite = FALSE) {
  curr <- desc::desc_get(name, file = base_path)[[1]]
  if (identical(curr, value)) {
    return(invisible())
  }

  if (!is.na(curr) && !overwrite) {
    stop(
      field(name), " has a different value in DESCRIPTION. ",
      "Use overwrite = TRUE to overwrite.",
      call. = FALSE
    )
  }

  done("Setting ", field(name), " field in DESCRIPTION to ", value(value))
  desc::desc_set(name, value, file = base_path)
  invisible()
}

use_dependency <- function(package, type, version = "*") {
  stopifnot(is_string(package))
  stopifnot(is_string(type))

  if (package != "R" && !requireNamespace(package, quietly = TRUE)) {
    stop(package, " must be installed before you can take a dependency on it",
      call. = FALSE)
  }

  types <- c("Imports", "Depends", "Suggests", "Enhances", "LinkingTo")
  names(types) <- tolower(types)
  type <- types[[match.arg(tolower(type), names(types))]]

  deps <- desc::desc_get_deps(proj_get())

  matching_dep <- deps$package == package & deps$type == type
  to_add <- !any(matching_dep)
  to_set <- any(matching_dep & deps$version != version)

  if (to_add) {
    done("Adding ", value(package), " to ", field(type), " field in DESCRIPTION")
    desc::desc_set_dep(package, type, version = version, file = proj_get())
  } else if (to_set) {
    done("Setting ", value(package), " version to ", field(version), " field in DESCRIPTION")
    desc::desc_set_dep(package, type, version = version, file = proj_get())
  }

  invisible()
}

#' Use a directory.
#'
#' `use_directory()` creates a directory (if it does not already exist) in the
#' package root dir. This function powers many of the other `use_` functions
#' such as [use_data()] and [use_vignette()].
#'
#' @param path Path of the directory to create (relative to `base_path`).
#' @inheritParams use_template
#'
#' @export
#' @examples
#' \dontrun{
#' use_directory("inst")
#' }
use_directory <- function(path,
                          ignore = FALSE) {


  if (!file.exists(proj_path(path))) {
    done("Creating ", value(path, "/"))
  }
  create_directory(proj_get(), path)

  if (ignore) {
    use_build_ignore(path)
  }

  invisible(TRUE)
}

create_directory <- function(base_path, path) {
  if (!file.exists(base_path)) {
    stop(value(base_path), " does not exist", call. = FALSE)
  }
  target_path <- file.path(base_path, path)

  if (file.exists(target_path)) {
    if (!is_dir(target_path)) {
      stop(value(path), " exists but is not a directory.", call. = FALSE)
    }
  } else {
    ok <- dir.create(target_path, showWarnings = FALSE, recursive = TRUE)

    if (!ok) {
      stop("Failed to create path", call. = FALSE)
    }
  }

  target_path
}

edit_file <- function(base_path, path) {
  full_path <- path.expand(file.path(base_path, path))

  ## example: path = ".R/snippets/r.snippets" but .R doesn't exist yet
  if (dirname(path) != ".") {
    create_directory(base_path, dirname(path))
  }

  if (!file.exists(full_path)) {
    file.create(full_path)
  }

  if (!interactive() || is_testing()) {
    todo("Edit ", value(path))
  } else {
    todo("Modify ", value(path))

    if (rstudioapi::isAvailable() && rstudioapi::hasFun("navigateToFile")) {
      rstudioapi::navigateToFile(full_path)
    } else {
      utils::file.edit(full_path)
    }
  }
  invisible()
}

view_url <- function(..., open = interactive()) {
  url <- paste(..., sep = "/")
  if (open) {
    done("Opening url")
    utils::browseURL(url)
  } else {
    todo("Open url ", url)
  }
  invisible(url)
}

bump_version <- function(ver, which) {
  types <- c("major", "minor", "patch", "dev")

  choice <- pmatch(which, types)

  ver <- as.character(ver)
  string_text <- paste0("Version: ", ver)

  ver_out <- suppressMessages(
    desc::desc(text = string_text)$bump_version(types[choice])$get("Version")[[1]]
  )

  package_version(ver_out)
}

