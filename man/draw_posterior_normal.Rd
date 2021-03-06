% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/favar.R
\name{draw_posterior_normal}
\alias{draw_posterior_normal}
\title{draw posterior for measurement equation using a normal-gamma prior}
\usage{
draw_posterior_normal(li_prvar, fy, xy, K, P, N, Sigma, L, alpha, beta)
}
\arguments{
\item{li_prvar}{prior on variance for coefficients}

\item{fy}{'independent' variables}

\item{xy}{'dependent' variables}

\item{K}{number of variables in ts model}

\item{P}{Number variables in ts model plus number of factors}

\item{N}{total number of variables in factor data}

\item{Sigma}{previous draw of variance-covariance matrix}

\item{L}{previous draw of coefficients}

\item{alpha, beta}{prior on variances}
}
\description{
draw posterior for measurement equation using a normal-gamma prior
}
