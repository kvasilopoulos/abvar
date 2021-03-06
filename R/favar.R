# factordata = econdata::bbe2005[,-1]

#'  Extracts first k principal components from t x n matrix data, loadings
#'  are normalized so that lam'lam/n=I, fac is t x k, lam is n x k
#'
#' @export
#' @param .data data from which the factors should be extracted
#' @param nfactors number of factors that are going to be extracted
#' @return matrix with the extracted factors
#'
#'
#'
factor_extract <- function(factordata, no_factors = 2) {
  # dtm <- as.matrix(.data)
  # # nc <- ncol(dtm)
  # nr <- nrow(dtm)
  # xx <- crossprod(dtm)
  # eig <- eigen(xx)
  # eigenval <- eig$values
  # idx <- sort(diag(eigenval))
  # eigenvec <- eig$vectors
  # evc <- matrix(NA, nr, nr)
  # for (i in 1:nr) {
  #   evc[,i] <- eigenvec[, idx[i]]
  # }
  # lambda <- sqrt(nr) * eigenvec[, 1:nfactors, drop = FALSE]
  # fac <-  dtm %*% lambda / nr

  factordata <- as.matrix(factordata)
  nv <- ncol(factordata) # number of variables in factordata
  nObs <- nrow(factordata)
  x.x <- t(factordata) %*% factordata
  evectors <- eigen(x.x)$vectors
  ret.evectors <- sqrt(nObs)*evectors[,1:no_factors]

  fac <- factordata %*% ret.evectors/nObs
}

#' @export
#' @title draw posterior for measurement equation using a normal-gamma prior
#' @param li_prvar prior on variance for coefficients
#' @param fy 'independent' variables
#' @param xy 'dependent' variables
#' @param K number of variables in ts model
#' @param N total number of variables in factor data
#' @param P Number variables in ts model plus number of factors
#' @param Sigma previous draw of variance-covariance matrix
#' @param L previous draw of coefficients
#' @param alpha,beta prior on variances
#' @importFrom stats rnorm
#' @importFrom stats rgamma
draw_posterior_normal <- function(li_prvar, fy, xy, K, P, N, Sigma, L, alpha, beta) {
  for (ii in 1:(N + K)) {
    if (ii > K) {
      Li_postvar <- solve(solve(li_prvar) + Sigma[ii, ii]^(-1) * t(fy) %*% fy)
      Li_postmean <- Li_postvar %*% (Sigma[ii, ii]^(-1) * t(fy) %*% xy[, ii])
      L[ii, 1:P] <- t(Li_postmean) + stats::rnorm(P) %*% t(chol(Li_postvar))
    }
    resi <- xy[, ii] - fy %*% L[ii, ]
    sh <- alpha / 2 + T / 2
    sc <- beta / 2 + t(resi) %*% resi
    Sigma[ii, ii] <- stats::rgamma(1, shape = sh, scale = sc)
  }

  list(L = L, Sigma = Sigma)
}

#' @export
#' @title Draw posterior for measurement equation using an SSVS-prior
#' @param fy 'independent' variables
#' @param xy 'dependent' variables
#' @param K number of variables in ts model
#' @param N total number of variables in factor data
#' @param P Number variables in ts model plus number of factors
#' @param L previous draw of coefficients
#' @param Sigma previous draw of variances
#' @param tau2 variance of coefficients
#' @param c2 factor for tau2
#' @param gammam previous draw of gammas
#' @param alpha,beta priors for variances
#' @importFrom stats pnorm
draw_posterior_ssvs <- function(fy, xy, K, P, N, Sigma, tau2, c2, gammam, alpha, beta, L) {
  for (ii in 1:(N + K)) {
    if (ii > K) {

      # Sample betas
      VBeta <- diag(gammam[, ii] * c2 * tau2 + (1 - gammam[, ii]) * tau2)
      DBeta <- solve(t(fy) %*% fy * Sigma[ii, ii]^(-1))
      dbeta <- t(fy) %*% xy[, ii] * Sigma[ii, ii]^(-1)
      HBeta <- t(chol(DBeta))

      L[ii, 1:P] <- t(DBeta %*% dbeta) + (rnorm(P) %*% HBeta)

      # Sample the gammas
      for (jj in 1:P) {
        numerator <- stats::pnorm(L[ii, jj], mean = 0, sd = sqrt(c2 * tau2))
        denominator <- numerator + stats::pnorm(L[ii, jj], mean = 0, sd = sqrt(tau2))
        prob <- numerator / denominator
        gammam[jj, ii] <- 0.5 * sign(runif(1) - prob) + 0.5
      }

      # Sample the variance
      resid <- xy[, ii] - fy %*% L[ii, ]
      sh <- alpha / 2 + T / 2
      sc <- beta / 2 + t(resid) %*% resid
      Sigma[ii, ii] <- rgamma(1, shape = sh, scale = sc)
    }
  }

  list(Sigma = Sigma, L = L, gammam = gammam)
}

#' @title linear regression using single value decomposition
#' @param y dependent variable
#' @param ly independent variable

olssvd <- function(y, ly) {
  duv <- svd(t(ly) %*% ly)
  x_inv <- duv$v %*% diag(1 / duv$d) %*% t(duv$u)
  x_pseudo_inv <- x_inv %*% t(ly)
  x_pseudo_inv %*% y
}

#' @export
#' @title Factor-Augmented Vector Autoregression
#' @param data data that is not going to be reduced to factors
#' @param factordata data that is going to be reduced to its factors
#' @param nreps total number of draws
#' @param burnin number of burn-in draws.
#' @param nthin thinning parameter
#' @param priorObj An S3 object containing information about the prior.
#' @param priorm Selects the prior on the measurement equation, 1=Normal-Gamma Prior and 2=SSVS prior.
#' @param alpha,beta prior on the variance of the measurement equation
#' @param tau2 variance of the coefficients in the measurement equation (only used if priorm=2)
#' @param c2 factor for the variance of the coefficients (only used if priorm=2)
#' @param li_prvar prior on variance of coefficients (only used if priorm = 1)
#' @param stabletest boolean, check if a draw is stationary or not
#'
favar <- function(data, priorObj, factordata, nreps, burnin, alpha, beta, tau2,
                  c2, li_prvar, priorm, stabletest = TRUE, nthin = 1) {

  # normalize data
  scaled_data <- scale(data)
  scaled_factordata <- scale(factordata)

  # Variables
  no_lags <- priorObj$nolags
  no_factors <- priorObj$nofactors
  intercept <- priorObj$intercept

  nObs <- nrow(scaled_data)
  N <- ncol(factordata)
  K <- ncol(data)
  P <- K + no_factors

  # Declare Variables for storage
  if (intercept) {
    constant <- 1
  } else {
    constant <- 0
  }

  storevar <- floor((nreps - burnin) / nthin)
  addInfo <- array(list(), dim = c(storevar))

  Alphadraws <- array(NA, dim = c(P * priorObj$nolags + constant, P, storevar))
  Sigmadraws <- array(NA, dim = c(P, P, storevar))
  Ldraws <- array(NA, dim = c(N + K, P, storevar))
  Sigma_measure <- array(NA, dim = c(N + K, N + K, storevar))
  gammam_draws <- array(NA, dim = c(P, N + K, storevar))

  # extract factors and join series

  fac <- factor_extract(factordata, no_factors)
  xy <- cbind(data, factordata)
  fy <- cbind(data, fac)

  L <- olssvd(xy, fy)

  resids <- xy - fy %*% L
  Sigma <- t(resids) %*% resids

  L <- t(L)
  print(dim(L))

  # Prior on the measurement equation
  gammam <- array(0.5, dim = c(P, N + K))
  Liprvar <- li_prvar * diag(1, P)

  # Initialize the MCMC algorithm
  fy_lagged <- lagdata(fy, nolags = no_lags, intercept = intercept)
  draw <- initialize_mcmc(priorObj, fy_lagged$y, fy_lagged$x)

  # Start the MCMC sampler

  for (ireps in 1:nreps) {
    print(ireps)

    # Draw posterior on measurement equation
    if (priorm == 1) {
      draw_measurement <- draw_posterior_normal(Liprvar, fy, xy, K, P, N, Sigma, L, alpha, beta)
      L <- draw_measurement$L
      Sigma <- draw_measurement$Sigma
    }
    else if (priorm == 2) {
      draw_measurement <- draw_posterior_ssvs(fy, xy, K, P, N, Sigma, tau2, c2, gammam, alpha, beta, L)
      L <- draw_measurement$L
      Sigma <- draw_measurement$Sigma
      gammam <- draw_measurement$gammam
    }

    # Draw posterior for state equation
    draw <- draw_posterior(priorObj, fy_lagged$y, fy_lagged$x, previous = draw, stabletest = stabletest)

    # Store results
    if (ireps > burnin && (ireps - burnin) %% nthin == 0) {
      Alphadraws[, , (ireps - burnin) / nthin] <- draw$Alpha
      Sigmadraws[, , (ireps - burnin) / nthin] <- draw$Sigma
      addInfo[[(ireps - burnin) / nthin]] <- draw$addInfo
      Ldraws[, , (ireps - burnin) / nthin] <- L
      Sigma_measure[, , (ireps - burnin) / nthin] <- Sigma

      if (priorm == 2) {
        gammam_draws[, , (ireps - burnin) / nthin ] <- gammam
      }
    }
  } # End loop over MCMC sampler

  # Store results

  # general information
  general_information <- list(
    intercept = priorObj$intercept,
    nolags = priorObj$nolags,
    nofactors = no_factors,
    nreps = nreps,
    burnin = burnin,
    nthin = nthin
  )

  # Information about the data

  if (sum(class(data) == "xts") > 0) {
    tstype <- "xts"
    var_names <- colnames(data)
  }
  else if (sum(class(data) == "ts") > 0) {
    tstype <- "ts"
    var_names <- colnames(data)
  }
  else if (is.matrix(data)) {
    tstype <- "matrix"
    var_names <- colnames(data)
  }

  data_info <- list(
    type = tstype,
    var_names = var_names,
    data = data,
    no_variables = K
  )

  # Information about the data used to extract the factors

  if (sum(class(factordata) == "xts") > 0) {
    tstype <- "xts"
    var_names <- colnames(factordata)
  }
  else if (sum(class(factordata) == "ts") > 0) {
    tstype <- "ts"
    var_names <- colnames(factordata)
  }
  else if (is.matrix(factordata)) {
    tstype <- "matrix"
    var_names <- colnames(factordata)
  }

  factordata_info <- list(
    type = tstype,
    var_names = var_names,
    data = factordata,
    no_variables = K
  )


  # The results of the mcmc draws

  draw_info <- list(
    Alpha = Alphadraws,
    Sigma = Sigmadraws,
    Sigma_measure = Sigma_measure,
    L = Ldraws,
    additional_info = addInfo
  )

  # Return information
  structure(list(
    general_info = general_information,
    data_info = data_info,
    factordata_info = factordata_info,
    mcmc_draws = draw_info
  ),
  class = "favar"
  )
}

#' @export
#' @title Function to calculate irfs
#' @param obj an S3 object of class favar
#' @param id_obj an S3 object with information about identifiaction of the model
#' @param nhor horizon of the impulse-response function
#' @param irfquantiles quantiles for the impulse-response functions
#' @param ncores number of cores used
#' @param ... currently not used
#'
#' @return returns an S3-object of the class fvirf
irf.favar <- function(x, id_obj, nhor = 12, ncores = 1, irfquantiles = c(0.05, 0.95), ...) {

  # Preliminaries
  obj <- x
  intercept <- obj$general_info$intercept
  Betadraws <- obj$mcmc_draws$Alpha
  Sigmadraws <- obj$mcmc_draws$Sigma
  Ldraws <- obj$mcmc_draws$L
  nolags <- obj$general_info$nolags

  nreps <- dim(Betadraws)[3]
  k <- dim(Sigmadraws)[1]
  dimXY <- dim(Ldraws)[1]

  irf_small_draws <- array(0, dim = c(k, k, nhor, nreps))
  irf_large_draws <- array(0, dim = c(k, dimXY, nhor, nreps))

  if (ncores > 1 && !requireNamespace("foreach", quietly = TRUE)) {
    stop("The foreach package cannot be loaded.")
  }

  if (ncores == 1) {
    for (ii in 1:nreps) {
      Alpha <- Betadraws[, , ii]
      Sigma <- Sigmadraws[, , ii]
      L <- Ldraws[, , ii]

      irf <- compirf(Alpha = Alpha, Sigma = Sigma, id_obj = id_obj, nolags = nolags, intercept = intercept, nhor = nhor)
      irf_small_draws[, , , ii] <- irf

      for (jj in 1:k) {
        irf_large_draws[jj, , , ii] <- L[, ] %*% irf[jj, , ]
      }
    }
  }
  else {

    # Get impulse-response for VAR-system
    # Register workers
    cl <- parallel::makeCluster(ncores)
    doParallel::registerDoParallel(cl)

    `%dopar%` <- foreach::`%dopar%`

    xtmp <- foreach::foreach(ii = 1:nreps) %dopar% {
      Alpha <- Betadraws[, , ii]
      Sigma <- Sigmadraws[, , ii]

      irf <- compirf(Alpha = Alpha, Sigma = Sigma, id_obj = id_obj, nolags = nolags, intercept = intercept, nhor = nhor)
    } # End getting IRFs

    # Transform it to larger system
    for (ii in 1:nreps) {
      L <- Ldraws[, , ii]
      irf_small_draws <- xtmp[[ii]]

      for (jj in 1:k) {
        irf_large_draws[jj, , , ii] <- L[, ] %*% irf_small_draws
      }
    } # end transformation
  } # End loop over parallel version

  # Store values
  IrfSmallFinal <- array(0, dim = c(k, k, nhor, 3))
  IrfLargeFinal <- array(0, dim = c(k, dimXY, nhor, 3))
  irflower <- min(irfquantiles)
  irfupper <- max(irfquantiles)

  for (jj in 1:k) {
    for (kk in 1:k) {
      for (ll in 1:nhor) {
        IrfSmallFinal[jj, kk, ll, 1] <- quantile(irf_small_draws[jj, kk, ll, ], probs = 0.5)
        IrfSmallFinal[jj, kk, ll, 2] <- quantile(irf_small_draws[jj, kk, ll, ], probs = irflower)
        IrfSmallFinal[jj, kk, ll, 3] <- quantile(irf_small_draws[jj, kk, ll, ], probs = irfupper)
      }
    }
  }
  for (jj in 1:k) {
    for (kk in 1:dimXY) {
      for (ll in 1:nhor) {
        IrfLargeFinal[jj, kk, ll, 1] <- quantile(irf_large_draws[jj, kk, ll, ], probs = 0.5)
        IrfLargeFinal[jj, kk, ll, 2] <- quantile(irf_large_draws[jj, kk, ll, ], probs = irflower)
        IrfLargeFinal[jj, kk, ll, 3] <- quantile(irf_large_draws[jj, kk, ll, ], probs = irfupper)
      }
    }
  }

  # Returning values
  relist <- structure(list(
    irf = IrfLargeFinal, irfhorizon = nhor, varnames = obj$data_info$varnames,
    factor_varnames = obj$factordata_info$varnames
  ), class = "fvirf")
  return(relist)
}
