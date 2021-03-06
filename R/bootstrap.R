boot_resample <- function(x) {
  nr <- NROW(x)
  boot_idx <- sample(1:nr, replace = TRUE)
  x[boot_idx, ]
}

boot_wild_rad <- function(x) {
  nr <- NROW(x)
  rad <- sample(c(-1, 1), nr, replace = TRUE)
  x*rad
}

boot_wild_norm <- function(x) {
  nr <- NROW(x)
  gauss <- rnorm(nr)
  x*gauss
}

boot_mammen <- function(x) {
  nr <- NROW(x)
  mam <- sample(
    x = c(-(sqrt(5) - 1)/2, (sqrt(5) + 1)/2),
    prob = c((sqrt(5) + 1)/(2 * sqrt(5)), (sqrt(5) - 1)/(2 * sqrt(5))),
    size = nr,
    replace = TRUE)
  x*mam
}
