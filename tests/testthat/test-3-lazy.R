drake_context("lazy")

test_with_dir("no overt errors lazy load for the debug example", {
  skip_on_cran() # CRAN gets essential tests only (check time limits).
  config <- dbug()
  config$verbose <- FALSE
  config$settings$lazy_load <- TRUE
  if ("parLapply" %in% tail(config$settings$parallelism, 1)) {
    config$settings$jobs <- 1
  }
  expect_equal(sort(outdated_impl(config)), sort(config$plan$target))

  testrun(config)
  config <- testconfig(config)
  expect_equal(sort(justbuilt(config)), sort(config$plan$target))
  expect_equal(outdated_impl(config), character(0))

  unload_these <- intersect(config$plan$target, ls(envir = config$envir))
  remove(list = unload_these, envir = config$envir)

  testrun(config)
  config <- testconfig(config)
  expect_equal(sort(justbuilt(config)), character(0))
  expect_equal(outdated_impl(config), character(0))

  unload_these <- intersect(config$plan$target, ls(envir = config$envir))
  remove(list = unload_these, envir = config$envir)

  config$plan$command[config$plan$target == "combined"] <-
    "nextone + yourinput + 1"
  testrun(config)
  config <- testconfig(config)
  expect_equal(sort(justbuilt(config)), sort(c(
    "combined", "final", "drake_target_1"
  )))
  expect_equal(outdated_impl(config), character(0))
})

test_with_dir("lazy loading is actually lazy", {
  skip_on_cran() # CRAN gets essential tests only (check time limits).
  lazily_loaded <- c("nextone", "yourinput")
  eagerly_loaded <- "combined"
  config <- dbug()
  unload_these <- c(lazily_loaded, eagerly_loaded)
  unload_these <- intersect(unload_these, ls(envir = config$envir_targets))
  remove(list = unload_these, envir = config$envir_targets)
  eval <- config$envir_targets
  config <- drake_config(
    lazy_load = TRUE,
    plan = config$plan,
    targets = "combined",
    envir = config$envir,
    verbose = 0L,
    session_info = FALSE
  )
  for (x in names(eval)) {
    config$envir_targets[[x]] <- eval[[x]]
  }
  config$graph <- subset_graph(config$graph, all_targets(config))
  config$ht_dynamic <- ht_new()
  config$envir_graph <- ht_new()
  config$envir_graph$graph <- config$graph
  config$logger$set_progress_total(igraph::gorder(config$graph))
  drake_backend_loop(config)
  loaded <- ls(envir = config$envir_targets)
  expect_true(all(lazily_loaded %in% loaded))
  expect_false(any(eagerly_loaded %in% loaded))
})

test_with_dir("active bindings", {
  skip_on_cran() # CRAN gets essential tests only (check time limits).
  skip_if_not_installed("bindr")
  config <- dbug()
  if (identical(globalenv(), config$envir)) {
    skip("Testing active bindings on a global environment mangles other tests.") # nolint
  }
  testrun(config)

  if ("final" %in% ls(config$envir)) {
    rm(final, envir = config$envir)
  }
  expect_false("final" %in% ls(config$envir))
  loadd(final, envir = config$envir, lazy = "bind", cache = config$cache)

  # `final` should be loaded when it is referenced.
  tmp <- config$envir$final
  expect_true(is.numeric(tmp))
  expect_equal(config$envir$final, readd(final, cache = config$cache))

  # Allow active bindings to overwrite existing variables.
  expect_message(
    loadd(
      final, envir = config$envir, lazy = "bind",
      verbose = 0L, cache = config$cache),
    regexp = "active binding"
  )

  # Needed for the tests on parallel backends.
  e <- new.env(parent = globalenv())
  loadd(
    final, envir = e, lazy = "bind",
    verbose = 0L, cache = config$cache)

  # Active bindings react to make()
  old_final <- e$final
  config$plan$command[[6]] <- parse(text = paste0(sum(old_final), "+ 1"))[[1]]
  testrun(config)
  expect_equal(e$final, sum(old_final) + 1)

  expect_false("nextone" %in% ls(config$envir))
  loadd(envir = config$envir, lazy = "bind", cache = config$cache)
  tmp <- config$envir$nextone
  expect_true("nextone" %in% ls(config$envir))
  expect_equal(config$envir$nextone, readd(nextone, cache = config$cache))
})
