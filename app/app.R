# =============================================================================
# LymphMutSig - Lymphoid cancer Mutational Signatures
# Production-ready R Shiny application
# =============================================================================

library(shiny)
library(bslib)
library(ggplot2)
library(dplyr)
library(tidyr)
library(readr)
library(markdown)  # Required for includeMarkdown()

# Null coalescing (for base R compatibility)
`%||%` <- function(a, b) if (is.null(a)) b else a

# SciLifeLab temp 5GB: 单文件上传限制 500MB，留足余量
options(shiny.maxRequestSize = 500 * 1024 * 1024)

# -----------------------------------------------------------------------------
# Global: load reference data (assume RDS files exist in data/)
# -----------------------------------------------------------------------------
data_dir <- "data"
if (!dir.exists(data_dir)) data_dir <- file.path("..", "data")

load_reference_data <- function() {
  meta_path <- file.path(data_dir, "signature_metadata.rds")
  prof_path <- file.path(data_dir, "signature_profiles.rds")
  exp_path  <- file.path(data_dir, "exposure_summary.rds")
  if (!file.exists(meta_path) || !file.exists(prof_path) || !file.exists(exp_path)) {
    stop("Reference RDS files not found. Run scripts/create_reference_rds.R first.")
  }
  list(
    signature_metadata = readRDS(meta_path),
    signature_profiles = readRDS(prof_path),
    exposure_summary  = readRDS(exp_path)
  )
}

ref_data <- tryCatch(load_reference_data(), error = function(e) NULL)

# If RDS not found, create minimal in-memory placeholders so UI still runs
if (is.null(ref_data)) {
  signature_metadata <- tibble(
    signature_id = character(), mutation_class = character(), name = character(),
    putative_etiology = character(), description = character()
  )
  signature_profiles <- list(SBS = data.frame(), DBS = data.frame(), ID = data.frame(), Kataegis = data.frame())
  exposure_summary <- tibble(signature_id = character(), entity = character(), mean_exposure = numeric(), proportion_positive = numeric(), attribution_score = numeric())
} else {
  signature_metadata <- ref_data$signature_metadata
  signature_profiles <- ref_data$signature_profiles
  exposure_summary  <- ref_data$exposure_summary
}

# Feature column name in profile matrices (first column)
feature_col <- function(prof_df) names(prof_df)[1]

# -----------------------------------------------------------------------------
# Helper: plot single signature profile (barplot)
# -----------------------------------------------------------------------------
plot_signature_profile <- function(prof_df, sig_id, feat_col = NULL) {
  if (is.null(prof_df) || nrow(prof_df) == 0 || !sig_id %in% names(prof_df)) return(NULL)
  if (is.null(feat_col)) feat_col <- feature_col(prof_df)
  d <- data.frame(
    feature = prof_df[[feat_col]],
    value   = as.numeric(prof_df[[sig_id]])
  )
  d <- d[order(d$feature), ]
  p <- ggplot(d, aes(x = .data$feature, y = .data$value, fill = .data$value)) +
    geom_col() +
    scale_fill_viridis_c(option = "plasma", begin = 0.2, end = 0.9) +
    theme_minimal(base_size = 11) +
    theme(
      axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 6),
      legend.position = "none",
      plot.margin = margin(2, 2, 2, 2, "pt")
    ) +
    labs(x = NULL, y = "Contribution")
  p
}

# Helper: exposure bubble plot
# Fixed entity order and unified scales per mutation class
entity_order <- c('U-CLL', 'M-CLL', 'cMCL', 'nnMCL', 'BL', 'FL', 'GCB-DLBCL', 'ABC-DLBCL', 'MM')

# Compute scales per mutation class (using global exposure_summary)
compute_class_scales <- function(mutation_class) {
  if (nrow(exposure_summary) == 0) {
    return(list(size_range = c(0, 1), color_range = c(0, 1)))
  }
  # Get signatures for this mutation class (use .env$ to reference function parameter)
  sig_ids <- signature_metadata %>%
    filter(.data$mutation_class == .env$mutation_class) %>%
    pull(.data$signature_id)
  # Filter exposure data for this mutation class
  class_exp <- exposure_summary %>%
    filter(.data$signature_id %in% sig_ids)
  if (nrow(class_exp) == 0) {
    return(list(size_range = c(0, 1), color_range = c(0, 1)))
  }
  size_max <- max(class_exp$proportion_positive, na.rm = TRUE)
  color_max <- max(class_exp$attribution_score, na.rm = TRUE)
  # Use 0 as color minimum so "no exposure" is consistent; max per class for better SBS contrast
  color_min <- 0
  if (color_max <= color_min) color_max <- 1
  list(
    size_range = c(0, max(size_max, 0.01)),
    color_range = c(color_min, color_max)
  )
}

plot_exposure_bubble <- function(exposure_df, sig_id, mutation_class, title = NULL) {
  if (is.null(exposure_df) || nrow(exposure_df) == 0) return(NULL)
  d <- exposure_df %>% filter(.data$signature_id == .env$sig_id)
  if (nrow(d) == 0) return(NULL)
  
  # Ensure all entities are present (fill missing with 0)
  d_full <- expand_grid(entity = entity_order, signature_id = sig_id) %>%
    left_join(d, by = c("entity", "signature_id")) %>%
    mutate(
      proportion_positive = ifelse(is.na(proportion_positive), 0, proportion_positive),
      attribution_score = ifelse(is.na(attribution_score), 0, attribution_score)
    )
  
  # Get scales for this mutation class
  class_scales <- compute_class_scales(mutation_class)
  
  p <- ggplot(d_full, aes(x = factor(.data$entity, levels = entity_order), 
                          y = 1, 
                          size = .data$proportion_positive, 
                          color = .data$attribution_score)) +
    geom_point(alpha = 0.8) +
    scale_size_continuous(range = c(2, 12), 
                         limits = class_scales$size_range,
                         name = "Proportion") +
    scale_color_viridis_c(option = "magma", 
                         limits = class_scales$color_range,
                         name = "Exposure") +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      axis.title.x = element_blank(),
      axis.title.y = element_blank(), 
      axis.text.y = element_blank(), 
      axis.ticks.y = element_blank(),
      panel.grid.major.y = element_blank(),
      legend.position = "none"
    )
  p
}

# Helper: legend plot for a mutation class (single layer: points with size + color)
# Size legend = gray circles; Exposure (%) = colour bar
plot_bubble_legend <- function(mutation_class) {
  class_scales <- compute_class_scales(mutation_class)
  n_pt <- 5
  df <- data.frame(
    x = seq_len(n_pt),
    y = 1,
    size = seq(class_scales$size_range[1], class_scales$size_range[2], length.out = n_pt),
    z  = seq(class_scales$color_range[1], class_scales$color_range[2], length.out = n_pt)
  )
  # Plot body invisible (alpha = 0); only legends are shown to avoid "double layer"
  ggplot(df, aes(x = .data$x, y = .data$y, size = .data$size, color = .data$z)) +
    geom_point(alpha = 0) +
    scale_size_continuous(
      range = c(2, 12),
      limits = class_scales$size_range,
      name = "Proportion",
      guide = guide_legend(
        order = 1,
        direction = "horizontal",
        title.position = "top",
        label.position = "bottom",
        keywidth = unit(12, "pt"),
        override.aes = list(color = "gray40", alpha = 1)
      )
    ) +
    scale_color_viridis_c(
      option = "magma",
      limits = class_scales$color_range,
      name = "Exposure (%)",
      guide = guide_colorbar(
        order = 2,
        title.position = "top",
        barwidth = unit(120, "pt"),
        barheight = unit(8, "pt"),
        direction = "horizontal"
      )
    ) +
    theme_void() +
    theme(
      legend.position = "bottom",
      legend.box = "horizontal",
      legend.direction = "horizontal",
      legend.margin = margin(4, 4, 4, 4),
      legend.spacing.x = unit(12, "pt"),
      plot.margin = margin(4, 4, 4, 4),
      legend.key.size = unit(8, "pt"),
      legend.text = element_text(size = 9),
      legend.title = element_text(size = 10)
    )
}

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
ui <- navbarPage(
  title = "LymphMutSig",
  theme = bslib::bs_theme(
    bootswatch = "flatly",
    base_font = bslib::font_google("Lato"),
    heading_font = bslib::font_google("Lato"),
    primary = "#2c3e50",
    success = "#27ae60"
  ),
  header = NULL,
  id = "main_nav",
  # Tab 1: Home
  tabPanel(
    "Home",
    fluidPage(
      includeMarkdown("www/HomePage.md")
    )
  ),
  # Tab 2: Signature Browser
  tabPanel(
    "Signature Browser",
    fluidPage(
      tabsetPanel(
        id = "browser_tabs",
        # Overview sub-tab (default)
        tabPanel(
          "Overview",
          value = "overview",
          fluidRow(
            column(4, selectInput("mutation_class", "Mutation class", choices = c("SBS", "DBS", "ID", "Kataegis"), selected = "SBS")),
            column(4, align = "left", style = "padding-top: 25px;", downloadButton("download_profiles", "Download signature matrix", class = "btn-secondary")),
            column(4, align = "right", style = "padding-top: 25px;", plotOutput("bubble_legend", height = "100px", width = "420px"))
          ),
          uiOutput("signature_rows")
        ),
        # Signature Detail sub-tab (shown when a signature is selected)
        tabPanel(
          "Signature Detail",
          value = "detail",
          uiOutput("signature_detail_ui")
        )
      )
    )
  ),
  # Tab 3: Signature Analyser
  tabPanel(
    "Signature Analyser",
    fluidPage(
      titlePanel("User Data Analysis Portal"),
      sidebarLayout(
        sidebarPanel(
          fluidRow(
            column(10, fileInput("user_file", "Upload mutation file (tab-separated .txt)", accept = c(".txt", ".tsv"), buttonLabel = "Browse...")),
            column(2, style = "padding-top: 25px;", actionButton("btn_file_help", label = NULL, icon = icon("question-circle"), class = "btn-default", title = "File format help"))
          ),
          actionButton("load_example", "Load Example Data", class = "btn-info"),
          selectInput("ref_genome", "Reference genome", choices = c("GRCh37", "GRCh38"), selected = "GRCh37"),
          selectInput("ref_signature", "Reference signatures", choices = c("LymphMutSig" = "LymphMutSig", "COSMIC v3.4" = "COSMIC"), selected = "LymphMutSig"),
          selectInput("sequencing_type", "Sequencing type", choices = c("WGS" = "WGS", "WES" = "WES"), selected = "WGS"),
          actionButton("run_analysis", "Run Signature Analysis", class = "btn-primary"),
          hr(),
          uiOutput("upload_summary"),
          uiOutput("mutation_class_counts_ui")
        ),
        mainPanel(
          uiOutput("analysis_progress_ui"),
          uiOutput("analysis_results_ui")
        )
      )
    )
  )
)

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
server <- function(input, output, session) {
  # 确保 www 目录可被正确访问（Docker/不同部署环境下图片能加载）
  www_dir <- if (dir.exists("www")) normalizePath("www", winslash = "/") else
    if (dir.exists(file.path("..", "www"))) normalizePath(file.path("..", "www"), winslash = "/") else
      file.path(getwd(), "www")
  if (dir.exists(www_dir)) addResourcePath(prefix = "www", directoryPath = www_dir)

  # ----- Signature Browser state -----
  selected_signature <- reactiveVal(NULL)

  # Pre-filter signatures by mutation class (no reactive recompute of exposure)
  sig_list <- reactive({
    req(input$mutation_class)
    signature_metadata %>%
      filter(.data$mutation_class == input$mutation_class) %>%
      pull(.data$signature_id)
  })

  # Current profile matrix for selected mutation class
  profile_matrix <- reactive({
    req(input$mutation_class)
    signature_profiles[[input$mutation_class]]
  })

  # Exposure for current mutation class (pre-filtered)
  exposure_filtered <- reactive({
    req(input$mutation_class)
    exposure_summary %>% filter(.data$signature_id %in% sig_list())
  })

  # Track which actionLink was clicked (any of the sig links)
  sig_links_trigger <- reactive({
    sigs <- sig_list()
    if (length(sigs) == 0) return(0)
    v <- vapply(sigs, function(s) {
      id <- paste0("siglink_", gsub("[^a-zA-Z0-9]", "_", s))
      as.numeric(input[[id]] %||% 0)
    }, numeric(1))
    sum(v, na.rm = TRUE)
  })

  observeEvent(sig_links_trigger(), {
    if (sig_links_trigger() == 0) return()
    sigs <- sig_list()
    for (s in sigs) {
      id <- paste0("siglink_", gsub("[^a-zA-Z0-9]", "_", s))
      if ((as.numeric(input[[id]] %||% 0)) > 0) {
        selected_signature(s)
        updateTabsetPanel(session, "browser_tabs", selected = "detail")
        break
      }
    }
  }, ignoreInit = TRUE)

  # Overview: dynamic signature rows
  output$signature_rows <- renderUI({
    req(profile_matrix(), sig_list(), exposure_filtered())
    prof <- profile_matrix()
    exp_df <- exposure_filtered()
    feat_col <- feature_col(prof)
    mut_class <- input$mutation_class
    meta <- signature_metadata %>% filter(.data$mutation_class == mut_class)

    rows <- lapply(sig_list(), function(sig_id) {
      local({
        safe_id <- gsub("[^a-zA-Z0-9]", "_", sig_id)
        link_id <- paste0("siglink_", safe_id)
        bub_out_id  <- paste0("bub_", safe_id)
        etiology <- meta %>% filter(.data$signature_id == sig_id) %>% pull(.data$putative_etiology) %>% `[`(1)
        img_src <- file.path("www","signatures", paste0(safe_id, ".png"))
        row_content <- fluidRow(
          column(3, actionLink(link_id, label = div(tags$strong(sig_id), br(), tags$small(etiology)))),
          column(4, tags$img(src = img_src,
                             style = "width: 100%; max-height: 120px; object-fit: contain;")),
          column(5, plotOutput(bub_out_id, height = "120px"))
        )
        list(row = row_content, sig_id = sig_id)
      })
    })
    # Render bubble plots for each signature (local() for dynamic UI)
    for (i in seq_along(rows)) {
      local({
        sig_id <- rows[[i]]$sig_id
        out_id_bub  <- paste0("bub_", gsub("[^a-zA-Z0-9]", "_", sig_id))
        output[[out_id_bub]] <- renderPlot({
          plot_exposure_bubble(exposure_filtered(), sig_id, mut_class, NULL)
        }, height = 120)
      })
    }
    do.call(tagList, lapply(rows, function(r) r$row))
  })

  # Render bubble legend for current mutation class
  output$bubble_legend <- renderPlot({
    req(input$mutation_class)
    plot_bubble_legend(input$mutation_class)
  }, height = 100, width = 420)

  # Download current mutation class profile matrix
  output$download_profiles <- downloadHandler(
    filename = function() paste0("LymphMutSig_", input$mutation_class, "_profiles.csv"),
    content = function(file) {
      prof <- profile_matrix()
      if (!is.null(prof) && nrow(prof) > 0) write.csv(prof, file, row.names = FALSE) else write.csv(data.frame(), file, row.names = FALSE)
    }
  )

  # Signature Detail panel
  output$signature_detail_ui <- renderUI({
    sig_id <- selected_signature()
    req(sig_id)
    meta <- signature_metadata %>% filter(.data$signature_id == sig_id)
    if (nrow(meta) == 0) return(NULL)
    etiology <- meta$putative_etiology[1]
    desc    <- meta$description[1]
    mut_class <- meta$mutation_class[1]
    prof <- signature_profiles[[mut_class]]
    exp_df <- exposure_summary %>% filter(.data$signature_id == sig_id)

    tagList(
      actionButton("back_to_overview", "← Back to Overview", class = "btn-outline-secondary"),
      br(), br(),
      h2(sig_id),
      h4("Signature profile"),
      uiOutput("detail_profile"),
      hr(),
      p(tags$strong("Putative etiology: "), etiology),
      p(tags$strong("Comment:  "), desc) ,
      hr(),
      h4("Exposure across entities"),
      plotOutput("detail_bubble", height = "320px")
    )
  })

  output$detail_profile <- renderUI({
    sig_id <- selected_signature()
    req(sig_id)
    safe_id <- gsub("[^a-zA-Z0-9]", "_", sig_id)
    img_src <- file.path("www", "signatures", paste0(safe_id, ".png"))
    tags$img(
      src = img_src,
      style = "max-width: 100%; max-height: 320px; object-fit: contain;"
    )
  })

  output$detail_bubble <- renderPlot({
    sig_id <- selected_signature()
    req(sig_id)
    meta <- signature_metadata %>% filter(.data$signature_id == sig_id)
    if (nrow(meta) == 0) return(NULL)
    mut_class <- meta$mutation_class[1]
    plot_exposure_bubble(exposure_summary, sig_id, mut_class, title = NULL)
  }, height = 320)

  observeEvent(input$back_to_overview, {
    updateTabsetPanel(session, "browser_tabs", selected = "overview")
  })

  # ----- Signature Analyser -----
  user_data <- reactiveVal(NULL)
  analysis_result <- reactiveVal(NULL)
  run_id <- reactiveVal(NULL)
  run_dir_reactive <- reactiveVal(NULL)  # 用于 session 结束时删除

  example_path <- file.path(data_dir, "example_mutations.txt")
  fitting_example_path <- file.path(data_dir, "fitting_IEI.tsv")

  # File format help modal
  observeEvent(input$btn_file_help, {
    example_lines <- "Sample\tChromosome\tPosition\tRef\tAlt
Sample1\tchr1\t757869\tT\tC
Sample1\tchr14\t974586\tG\tA
Sample2\tchr16\t1207788\tC\tA
Sample3\tchr18\t1217680\tC\tA
Sample4\tchr3\t1253522\tT\tC"
    showModal(modalDialog(
      title = "Mutation file format",
      size = "m",
      tags$p("Upload a tab-separated file with exactly 5 columns (header required):"),
      tags$ul(
        tags$li(tags$code("Sample"), " – sample identifier"),
        tags$li(tags$code("Chromosome"), " – chromosome (e.g. chr1 or 1)"),
        tags$li(tags$code("Position"), " – genomic position"),
        tags$li(tags$code("Ref"), " – reference allele"),
        tags$li(tags$code("Alt"), " – alternate allele")
      ),
      tags$p("Example (5 rows):"),
      tags$pre(example_lines, style = "font-size: 11px; background: #f5f5f5; padding: 10px; overflow-x: auto;"),
      tags$p(tags$small("Max upload: 500 MB."), style = "color: #666;"),
      easyClose = TRUE,
      footer = modalButton("Close")
    ))
  })

  observeEvent(input$load_example, {
    path <- example_path
    if (!file.exists(path)) {
      showNotification("Example file not found.", type = "error")
      return(NULL)
    }
    tryCatch({
      d <- read_tsv(path, show_col_types = FALSE)
      req_cols <- c("Sample", "Chromosome", "Position", "Ref", "Alt")
      if (!all(req_cols %in% names(d))) {
        showNotification(paste("Example file must contain columns:", paste(req_cols, collapse = ", ")), type = "error")
        return(NULL)
      }
      user_data(d)
      showNotification("Example data loaded.", type = "message")
    }, error = function(e) {
      showNotification(paste("Error loading example:", e$message), type = "error")
    })
  })

  observeEvent(input$user_file, {
    if (is.null(input$user_file)) return(NULL)
    tryCatch({
      d <- read_tsv(input$user_file$datapath, show_col_types = FALSE)
      req_cols <- c("Sample", "Chromosome", "Position", "Ref", "Alt")
      if (!all(req_cols %in% names(d))) {
        showNotification(paste("File must contain columns (exact names):", paste(req_cols, collapse = ", ")), type = "error")
        return(NULL)
      }
      user_data(d)
    }, error = function(e) {
      showNotification(paste("Invalid file:", e$message), type = "error")
    })
  })

  output$upload_summary <- renderUI({
    d <- user_data()
    if (is.null(d) || nrow(d) == 0) return(p(tags$em("Upload a file or load example data.")))
    n_samp <- n_distinct(d$Sample)
    n_mut  <- nrow(d)
    p(tags$strong("Upload ", n_samp, " sample(s), ", n_mut, " mutations."))
  })

  # Classify mutations: SBS (1bp/1bp not in pair), DBS (2bp/2bp OR two consecutive 1bp on same chr), ID (indel)
  mutation_class_counts <- reactive({
    d <- user_data()
    if (is.null(d) || nrow(d) == 0) return(list(n_sample = 0L, n_sbs = 0L, n_dbs = 0L, n_id = 0L))
    d <- d %>% mutate(
      ref_len = nchar(as.character(Ref)),
      alt_len = nchar(as.character(Alt)),
      Position_num = suppressWarnings(as.integer(Position))
    )
    # DBS: (i) ref and alt both length 2, OR (ii) two consecutive 1bp mutations on same chromosome (same sample)
    d <- d %>% group_by(.data$Sample, .data$Chromosome) %>%
      arrange(.data$Position_num) %>%
      mutate(
        is_1bp = (.data$ref_len == 1L & .data$alt_len == 1L),
        next_pos = lead(.data$Position_num),
        next_1bp = lead(.data$is_1bp),
        prev_pos = lag(.data$Position_num),
        prev_1bp = lag(.data$is_1bp),
        consecutive_pair = .data$is_1bp & (
          (.data$next_1bp %in% TRUE & .data$next_pos == .data$Position_num + 1L) |
          (.data$prev_1bp %in% TRUE & .data$prev_pos == .data$Position_num - 1L)
        )
      ) %>% ungroup()
    d <- d %>% mutate(
      is_dbs_pair = replace_na(.data$consecutive_pair, FALSE),
      class = case_when(
        .data$ref_len == 2L & .data$alt_len == 2L ~ "DBS",
        .data$is_dbs_pair ~ "DBS",
        .data$ref_len == 1L & .data$alt_len == 1L ~ "SBS",
        TRUE ~ "ID"
      )
    )
    list(
      n_sample = as.integer(n_distinct(d$Sample)),
      n_sbs = as.integer(sum(d$class == "SBS")),
      n_dbs = as.integer(sum(d$class == "DBS")),
      n_id = as.integer(sum(d$class == "ID")),
      data_with_class = d
    )
  })

  output$mutation_class_counts_ui <- renderUI({
    mc <- mutation_class_counts()
    if (is.null(mc) || mc$n_sample == 0) return(NULL)
    tagList(
      p(tags$strong("Mutation classes: "),
        "SBS ", mc$n_sbs, " | DBS ", mc$n_dbs, " | Indel ", mc$n_id, "."),
      p(tags$em("Signature fitting will run for each class with mutation count > 0."), style = "font-size: 11px; color: #666;")
    )
  })

  output$analysis_progress_ui <- renderUI({
    if (is.null(run_id())) return(NULL)
    res <- analysis_result()
    run_path <- if (!is.null(res) && nzchar(res$run_dir)) res$run_dir else file.path(tempdir(), "tmp", run_id())
    tagList(
      hr(),
      p(tags$em("Run ID: ", run_id(), ". Analysis finished.")),
      #p(tags$small("Intermediate files: ", tags$code(run_path)), style = "color: #666; font-size: 11px;")
    )
  })

  observeEvent(input$run_analysis, {
    mc <- mutation_class_counts()
    if (is.null(mc) || mc$n_sample == 0) {
      showNotification("Please upload data or load example first.", type = "warning")
      return(NULL)
    }
    d <- mc$data_with_class
    # RunID-based directory for all intermediate and cosmic_fit output files
    # Local: save under project (tmp/<run_id>) so you can find it; Docker/Serve: use tempdir()
    new_id <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", sample(10000:99999, 1))
    run_id(new_id)
    base_dir <- if (identical(normalizePath(getwd(), winslash = "/"), "/srv/shiny-server")) tempdir() else getwd()
    run_dir <- file.path(base_dir, "tmp", new_id)
    run_dir_reactive(run_dir)
    dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
    safe_name <- function(x) gsub("[^A-Za-z0-9_-]", "_", x)
    ref_label <- if (input$ref_signature == "LymphMutSig") "LymphMutSig" else "COSMICv3.4"
    script_path <- file.path(getwd(), "scripts", "run_sigprofiler.py")
    if (!file.exists(script_path)) script_path <- file.path(getwd(), "..", "scripts", "run_sigprofiler.py")
    py_exe <- Sys.which("python3"); if (py_exe == "") py_exe <- Sys.which("python")
    class_results <- list(SBS = list(activities_path = "", activities_df = NULL, run = FALSE), DBS = list(activities_path = "", activities_df = NULL, run = FALSE), ID = list(activities_path = "", activities_df = NULL, run = FALSE))
    classes_to_run <- c("SBS", "DBS", "ID")
    n_run <- sum(c(mc$n_sbs > 0, mc$n_dbs > 0, mc$n_id > 0))
    if (n_run == 0) {
      showNotification("No mutations to fit (SBS/DBS/Indel counts are 0).", type = "warning")
      return(NULL)
    }

    # each sample / per VCF （SBS+DBS+ID merged） to save storage
    vcf_dir <- file.path(run_dir, "vcf_data")
    dir.create(vcf_dir, recursive = TRUE, showWarnings = FALSE)
    for (s in unique(d$Sample)) {
      sub <- d %>% filter(.data$Sample == .env$s) %>% select(Chromosome, Position, Sample, Ref, Alt)
      f <- file.path(vcf_dir, paste0(safe_name(s), ".txt"))
      write.table(sub, f, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
    }

    for (mut_class in classes_to_run) {
      n_class <- switch(mut_class, SBS = mc$n_sbs, DBS = mc$n_dbs, ID = mc$n_id)
      if (n_class == 0) next
      out_subdir <- file.path(run_dir, paste0("Fitting_to_", ref_label, "_", mut_class))
      sig_db_path <- ""
      if (input$ref_signature == "LymphMutSig") {
        sig_file <- file.path(data_dir, paste0("MutSig.", mut_class, ".our.tsv"))
        if (mut_class == "ID") sig_file <- file.path(data_dir, "MutSig.ID.our.tsv")
        sig_db_path <- if (file.exists(sig_file)) sig_file else ""
      }
      if (file.exists(script_path) && nzchar(py_exe)) {
        withProgress(message = paste0("Fitting ", mut_class, " ..."), value = 0, {
          exome_arg <- if (input$sequencing_type == "WES") "1" else "0"
          args <- c(script_path, vcf_dir, out_subdir, input$ref_genome, input$ref_signature, mut_class, sig_db_path, exome_arg)
          tryCatch(system2(py_exe, args, stdout = TRUE, stderr = TRUE, timeout = 600), error = function(e) NULL)
        })
      }
      # Find Activities file (SPA may use different subpaths for ID, e.g. ID_83_Assignment_Solution)
      activities_path <- file.path(out_subdir, "Assignment_Solution", "Activities", "Assignment_Solution_Activities.txt")
      if (!file.exists(activities_path)) activities_path <- file.path(out_subdir, "Assignment_Solution", "Activities", "Assignment_Solution_Activities.csv")
      if (!file.exists(activities_path)) {
        found <- list.files(out_subdir, pattern = "Assignment_Solution_Activities[.]", recursive = TRUE, full.names = TRUE)
        if (length(found) > 0) activities_path <- found[1]
      }
      activities_df <- NULL
      if (file.exists(activities_path)) {
        activities_df <- tryCatch({
          raw <- read_tsv(activities_path, show_col_types = FALSE)
          raw %>% rename(Sample = 1) %>% tidyr::pivot_longer(-.data$Sample, names_to = "Signature", values_to = "N_mut") %>% filter(!is.na(.data$N_mut) & .data$N_mut > 0)
        }, error = function(e) NULL)
      }
      class_results[[mut_class]] <- list(activities_path = activities_path, activities_df = activities_df, run = file.exists(activities_path))
    }

    analysis_result(list(
      run_dir = run_dir,
      run_id = new_id,
      ref_label = ref_label,
      class_results = class_results,
      mutation_counts = mc
    ))
    showNotification("Analysis complete.", type = "message")
  })

  output$analysis_results_ui <- renderUI({
    res <- analysis_result()
    if (is.null(res)) return(p(tags$em("Run signature analysis to see results.")))
    cr <- res$class_results
    tabs <- Filter(function(x) !is.null(cr[[x]]) && isTRUE(cr[[x]]$run), c("SBS", "DBS", "ID"))
    if (length(tabs) == 0) return(p(tags$em("No assignment results (Python/SigProfilerAssignment may be unavailable).")))
    tab_panels <- lapply(tabs, function(tc) {
      tabPanel(tc,
        plotOutput(paste0("exposure_barplot_", tc), height = "400px"),
        downloadButton(paste0("download_activities_", tc), paste0("Download Assignment_Solution_Activities (", tc, ")"), class = "btn-secondary")
      )
    })
    tagList(
      h4("Assignment result (No. of mutations by sample and signature)"),
      do.call(tabsetPanel, c(tab_panels, list(id = "result_tabs")))
    )
  })

  # color palette
  high_contrast_palette <- function(n) {
    base <- c("#E41A1C", "#377EB8", "#4DAF4A", "#984EA3", "#FF7F00", "#FFFF33",
              "#A65628", "#F781BF", "#999999", "#66C2A5", "#FC8D62", "#8DA0CB",
              "#E78AC3", "#A6D854", "#FFD92F", "#E5C494", "#B3B3B3", "#1B9E77")
    rep(base, length.out = max(n, 1))
  }

  # Barplot per mutation class: x = Sample, y = N_mut, fill = Signature (from Activities table)
  output$exposure_barplot_SBS <- renderPlot({
    res <- analysis_result(); if (is.null(res) || !isTRUE(res$class_results$SBS$run)) return(NULL)
    adf <- res$class_results$SBS$activities_df
    if (is.null(adf) || nrow(adf) == 0) return(NULL)
    sigs <- unique(adf$Signature)
    pal <- setNames(high_contrast_palette(length(sigs)), sigs)
    ggplot(adf, aes(x = .data$Sample, y = .data$N_mut, fill = .data$Signature)) +
      geom_col(position = "stack") + scale_fill_manual(values = pal, name = "Signature") +
      theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "right") +
      labs(x = "Sample", y = "No. of mutations")
  }, height = 400)
  output$exposure_barplot_DBS <- renderPlot({
    res <- analysis_result(); if (is.null(res) || !isTRUE(res$class_results$DBS$run)) return(NULL)
    adf <- res$class_results$DBS$activities_df
    if (is.null(adf) || nrow(adf) == 0) return(NULL)
    sigs <- unique(adf$Signature)
    pal <- setNames(high_contrast_palette(length(sigs)), sigs)
    ggplot(adf, aes(x = .data$Sample, y = .data$N_mut, fill = .data$Signature)) +
      geom_col(position = "stack") + scale_fill_manual(values = pal, name = "Signature") +
      theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "right") +
      labs(x = "Sample", y = "No. of mutations")
  }, height = 400)
  output$exposure_barplot_ID <- renderPlot({
    res <- analysis_result(); if (is.null(res) || !isTRUE(res$class_results$ID$run)) return(NULL)
    adf <- res$class_results$ID$activities_df
    if (is.null(adf) || nrow(adf) == 0) return(NULL)
    sigs <- unique(adf$Signature)
    pal <- setNames(high_contrast_palette(length(sigs)), sigs)
    ggplot(adf, aes(x = .data$Sample, y = .data$N_mut, fill = .data$Signature)) +
      geom_col(position = "stack") + scale_fill_manual(values = pal, name = "Signature") +
      theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "right") +
      labs(x = "Sample", y = "No. of mutations")
  }, height = 400)

  output$download_activities_SBS <- downloadHandler(
    filename = function() paste0(run_id(), "_Assignment_Solution_Activities_SBS.txt"),
    content = function(file) { res <- analysis_result(); path <- res$class_results$SBS$activities_path %||% ""; if (nzchar(path) && file.exists(path)) file.copy(path, file) else writeLines("", file) },
    contentType = "text/tab-separated-values"
  )
  output$download_activities_DBS <- downloadHandler(
    filename = function() paste0(run_id(), "_Assignment_Solution_Activities_DBS.txt"),
    content = function(file) { res <- analysis_result(); path <- res$class_results$DBS$activities_path %||% ""; if (nzchar(path) && file.exists(path)) file.copy(path, file) else writeLines("", file) },
    contentType = "text/tab-separated-values"
  )
  output$download_activities_ID <- downloadHandler(
    filename = function() paste0(run_id(), "_Assignment_Solution_Activities_ID.txt"),
    content = function(file) { res <- analysis_result(); path <- res$class_results$ID$activities_path %||% ""; if (nzchar(path) && file.exists(path)) file.copy(path, file) else writeLines("", file) },
    contentType = "text/tab-separated-values"
  )

  # delete the previous temp files before close app (temporary storage)
  session$onSessionEnded(function() {
    cutoff <- Sys.time() - 3600
    for (base in c(getwd(), tempdir())) {
      runs_dir <- file.path(base, "tmp")
      if (!dir.exists(runs_dir)) next
      subdirs <- list.dirs(runs_dir, full.names = TRUE, recursive = FALSE)
      for (d in subdirs) {
        info <- tryCatch(file.info(d), error = function(e) NULL)
        if (!is.null(info) && !is.na(info$mtime) && info$mtime < cutoff) {
          tryCatch(unlink(d, recursive = TRUE), error = function(e) NULL)
        }
      }
    }
  })
}

# -----------------------------------------------------------------------------
# Run app
# -----------------------------------------------------------------------------
shinyApp(ui = ui, server = server)
