#' @export
vcov.varm <- function(object, ...) {
  object$vcov
}

#' @export
irf_boot <- function(x, ...) {
  UseMethod("irf_boot")
}



#' Impulse response functions
#'
#'   @export
#' @examples
#' \dontrun{
#'
#'
#'
#' irf(obj_dt, nboot = 100, horizon = 20, id = id_chol(), shock = scale_shock("se")) %>% str()
#' irf(obj_dt, nboot = 100, horizon = 20, id = id_chol(), shock = scale_shock("unit")) %>% str()
#'
#' autoplot(irf(obj_dt, nboot = 100, horizon = 20, id = id_none(), shock = scale_shock("unit")))
#'
#' autoplot(irf(obj_dt, nboot = 100, horizon = 20, id = id_chol(), shock = scale_shock("unit")))
#'
#'
#'}
irf.varm <- function(object, horizon = 12, nboot = 100, boot =  boot_spec(fn = boot_inst, nboot = 500),
                     id = id_none(), shock = shock_scale(), ...) {

  A <- comp(coefficients(object))
  B <- object$vcov

  Bid <- id(B)
  Bscale <- shock(Bid)

  irfs <- irf_(A, Bscale, h = horizon)
  boot_irfs <- irf_boot(obj = object, h = horizon, nb = nboot, id = id, shock = shock)
  structure(
    list(
      irfs = irfs,
      boot_irfs = boot_irfs
    ),
    class = append("irf_varm", class(irfs))
  )
}

#' Boostrap irfs
#'
#'
#' @export
#' @examples
#'
irf_boot.varm <- function(obj, h, nb, id, shock, ...) {

  K <- obj$K
  p <- obj$p

  bty <- array(0, c(K, K, h + 1, nb))
  for (i in 1:nb) {

    boot_Y <- boot_var(obj)
    boot_obj <- varm(varm::spec(as.data.frame(boot_Y), .endo_lags = p))

    A <- comp(coefficients(boot_obj))
    B <- boot_obj$vcov

    Bid <- id(B)
    Bscale <- shock(Bid)

    bty[,,,i] <- irf_(A, Bscale, h = h)
  }
  nms <- names(obj$lhs)
  dimnames(bty) <- list(nms, nms, paste0("h", 1:(h+1)), paste0("n", 1:nb))
  bty
}

#' Impulse Response Function Algorithm 1
#'
#' @importFrom expm expm %^%
#' @examples
#'
#'
#'
irf_ <- function(A, B, h) {
  K <- get_attr(A, "K")
  p <- get_attr(A, "p")
  nms <- rownames(B)
  J <- cbind(eye(K), zeros(K, K*(p - 1)))
  irf_comp <-  array(0, c(K * p, h + 1, K * p)) # matrix(NA, K^2, h + 1)
  irf_comp[1:K, 1, 1:K] <- B
  for (i in 1:h) {
    irf_comp[, i + 1, ] <- c(J %*% (A %^% i) %*% t(J) %*% B)
  }
  irf_comp <- irf_comp[1:K, , 1:K]
  out <- aperm(irf_comp, c(3, 1, 2))
  dimnames(out) <- list(nms, nms, paste0("h", 1:(h+1)))
  out
}

# fevd --------------------------------------------------------------------

#' @export
fevd.varm <- function(object, horizon = 12, id = id_none(), shock = shock_scale(), ...) {

  A <- comp(coefficients(object))
  B <- object$vcov

  Bid <- id(B)
  Bscale <- shock(Bid)

  fevds <- fevd_(A, Bscale, h = horizon)

  structure(
    list(
      fevds =
    ),
    class = append("fevd_varm", class(fevds))
  )

}

fevd_ <- function(A, B, h) {

  K <- get_attr(A, "K")
  p <- get_attr(A, "p")
  nms <- rownames(B)
  # J <- cbind(eye(K), zeros(K, K*(p - 1)))
  J <- eye(K)

  fevd <- matrix(0, K^2, h + 1)
  for (i in 0:h) {
    temp <- matrix(A^i %*% B, nrow = K^2, 1)
    fevd[, i + 1] <- fevd[, i + 1] + temp^2
  }
  sumfevd <- sum(fevd)

  VC <- zeros(K)
  for (j in 1:K) {
    VC[j, ] <- fevd[, ] / sumfevd
  }
  VC
}


# Scale -------------------------------------------------------------------


shock_scale <- function(type = c("se", "unit"), size = 1) {
  type <- match.arg(type)
  if (type == "se") {
    out <- function(x) x * size
  }else{
    out <- function(x) x/base::diag(x) * size
  }
  out
}


