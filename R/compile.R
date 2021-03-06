# Copyright (C) 2013 - 2019  Metrum Research Group, LLC
#
# This file is part of mrgsolve.
#
# mrgsolve is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# mrgsolve is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with mrgsolve.  If not, see <http://www.gnu.org/licenses/>.

generate_rdefs <- function(pars,
                           cmt,
                           func,
                           init_fun="",
                           table_fun="",
                           config_fun="",
                           model="",omats,smats,
                           set=list(),...) {

    npar <- length(pars)
    ncmt <- length(cmt)

    dxdt <- paste0("dxdt_",cmt)
    init <- paste0(cmt, "_0")

    cmtindex <- seq_along(cmt)-1
    parsindex <- seq_along(pars)-1

    cmtdef <-  paste0("#define ", cmt,  " _A_[",    cmtindex,"]")
    initdef <- paste0("#define ", init, " _A_0_[",  cmtindex,"]")
    dxdef <-   paste0("#define ", dxdt, " _DADT_[", cmtindex,"]")
    pardef <-  paste0("#define ", pars, " _THETA_[",parsindex,"]")
    
    etal <- epsl <- NULL

    if(sum(nrow(omats)) > 0) {
        etai <- seq_len(sum(nrow(omats)))
        etal <- unlist(omats@labels,use.names=FALSE)
        stopifnot(length(etai)==length(etal))
        which <- etal != "."
        if(sum(which) > 0) {
            etal <- paste0("#define ", etal[which], " _xETA(",etai[which],")")
        } else {
            etal <- NULL
        }
    }

    if(sum(nrow(smats)) > 0) {
        epsi <- seq_len(sum(nrow(smats)))
        epsl <- unlist(smats@labels,use.names=FALSE)
        stopifnot(length(epsi)==length(epsl))
        which <- epsl != "."
        if(sum(which) > 0) {
            epsl <- paste0("#define ", epsl[which], " _xEPS(",epsi[which],")")
        } else {
            epsl <- NULL
        }
    }

    Fdef <- Adef <- Ddef <- Rdef <- cmtndef <- NULL

    cmtn <- unique(intersect(cvec_cs(set$CMTN),cmt))

    if(length(cmtn) > 0) {
        cmtnindex <- match(cmtn,cmt)-1
        cmtndef <- paste0("#define ", paste0("N_", cmtn), " ", cmtnindex+1)
        Fdef <- paste0("#define ", paste0("F_",cmtn), " _F_[",cmtnindex,"]")
        Adef <- paste0("#define ", paste0("ALAG_",cmtn), " _ALAG_[",cmtnindex,"]")
        Ddef <- paste0("#define ", paste0("D_",cmtn), " _D_[",cmtnindex,"]")
        Rdef <- paste0("#define ", paste0("R_",cmtn), " _R_[",cmtnindex,"]")
    }

    if(npar==0) pardef <- NULL
    if(ncmt==0) cmtdef <- initdef <- dxdef <- NULL

    return(
        c(paste0("#define __INITFUN___ ",init_fun),
          paste0("#define __ODEFUN___ ",func),
          paste0("#define __TABLECODE___ ", table_fun),
          paste0("#define __CONFIGFUN___ ", config_fun),
          paste0("#define __REGISTERFUN___ ", register_fun(model)),
          paste0("#define _nEQ ", ncmt),
          paste0("#define _nPAR ", npar),
          cmtndef,
          Fdef,
          Adef,
          Rdef,
          Ddef,
          cmtdef,
          initdef,
          dxdef,
          pardef,
          etal,
          epsl
          )
        )
}


relocate_funs <- function(x,PACKAGE) {
    x@package <- PACKAGE
    x
}

build_version <- function(x) {
  x@shlib[["version"]] 
}

compiled <- function(x,status=NULL) {
    if(is.null(status)) return(x@shlib$compiled)
    x@shlib$compiled <- status
    return(x)
}

win_def_name <- function(x) {
  paste0(compbase(model(x)),"-win.def")
}

write_win_def <- function(x) {
  if(.Platform$OS.type != "windows") return(NULL)
  cat(file=win_def_name(x), c("EXPORTS",paste0(" ", funs(x))),sep="\n")
}

rm_win_def <- function(x) {
  if(is.character(x)) {
    if(file_exists(x)) {
      file.remove(x)
    }
  }
  return(invisible(NULL))
}


SAFE_WAIT_TIME <- 1.5

update_wait_time <- function(n) {
  assignInMyNamespace("SAFE_WAIT_TIME",n)
}


check_and_copy <- function(from,to) {
  
  if(!file_exists(to)) {
    file.copy(from,to)
    same <- TRUE
  } else {
    same <- tools::md5sum(from) == tools::md5sum(to)
    if(!same) {
      file.copy(from,to,overwrite=TRUE)
    }
  }
  z <- file.remove(from)
  return(same)
}

# Wait a certain amount of time before re-compiling
# and loading a model
safe_wait <- function(x) {
  
  target <- file.path(soloc(x),compout(model(x)))
  if(!file_exists(target)) return(invisible(NULL))
  mt <- file.info(target)[["mtime"]]
  age <- as.numeric(as.POSIXct(Sys.time())) - as.numeric(as.POSIXct(mt))
  if(age > SAFE_WAIT_TIME) return(invisible(NULL))
  message("(waiting) ...")
  return(Sys.sleep(SAFE_WAIT_TIME-age))
}


# Clean up model shared objects
# 
# @param x model object
# @param where directory to clean up
# 
# @details
# \code{cleanso} removes (deletes) shared objects from the model compile directory and 
# attempts to unload shared objects which appear to be loaded.
# 
#
# 
cleanso <- function(x,where=soloc(x)) {
  so <- list.files(where, 
                   pattern =  paste0("*\\", .Platform$dynlib.ext), full.names=TRUE)
  so <- so[so != file.path(where,compout(model(x)))]
  lo <- sapply(getLoadedDLLs(), "[[", "path")
  y <- intersect(lo,so)
  for(w in y) foo <- try(silent=TRUE,dyn.unload(w))
  for(w in y) foo <- try(silent=TRUE,file.remove(w))
  return(invisible(NULL))
}

##' Get inits from compiled function
##' 
##' This function is usually for internal use.
##'
##' @param x mrgmod model object
##' @param keep_pointers should function pointers be returned?
##' 
##' @export
##' @keywords internal
touch_funs <- function(x,keep_pointers=TRUE) {
  
  funp <- pointers(x)
  
  param <- as.numeric(param(x))
  init <- as.numeric(x@init)
  neta <- sum(nrow(omat(x)))
  neps <- sum(nrow(smat(x)))
  
  out <- .Call(`_mrgsolve_TOUCH_FUNS`,param,init,neta,neps,x@capture,funp,
               x@envir)
  
  names(out$init) <- names(init)
  
  if(keep_pointers) {
    out[["pointers"]] <- funp
  }
  out
}

