make_poly <- function(file){
    dd <- raster(file)
    pol <- rasterToPolygons(dd, fun=NULL, dissolve=FALSE, na.rm=FALSE)
    proj4string(pol) <- CRS("+proj=longlat +datum=WGS84")
    pol$grids <- paste0("v", seq_len(nrow(pol)))
    xx <- as.data.frame(xyFromCell(dd, cell=seq_len(ncell(dd))))
    #Make dataframe of all xy coordinates
    xx$grids <- paste0("v", seq_len(nrow(xx)))
    m <- merge(pol, xx, by="grids")
    names(m)[2] <- "richness"
    names(m)[3] <- "lon"
    names(m)[4] <- "lat"
    m
}



#' Convert raw input distribution data to community
#'
#' The functions \code{points2comm}, \code{polys2comm}, \code{raster2comm}
#' provide convenient interfaces to convert raw distribution data often
#' available as point records, extent-of-occurrence polygons and raster layers,
#' respectively, to a community composition data frame at varying spatial grains
#' and extents for downstream analyses.
#'
#' @param files  list of raster layer objects with the same spatial
#' extent and resolution.
#' @param dat layers of merged maps corresponding to species ranges for
#' \code{polys2comm}; or point occurrence data frame for \code{points2comm},
#' with at least three columns:
#' \itemize{
#'   \item Column 1: \code{species} (listing the taxon names)
#'   \item Column 2: \code{decimallongitude} (corresponding to decimal longitude)
#'   \item Column 3: \code{decimallatitude} (corresponding to decimal latitude)
#' }
#' @param res the grain size of the grid cells in decimal degrees (default).
#' @param species a character string. The column with the species or taxon name.
#' Default = \dQuote{species}.
#' @param lon character with the column name of the longitude.
#' @param lat character with the column name of the latitude.
#' @param mask Only applicable to \code{points2comm}. If supplied, a polygon
#' shapefile covering the boundary of the survey region.
#' @param shp.grids if specified, the polygon shapefile of grid cells
#' with a column labeled \dQuote{grids}.
#' @param index Diversity index, one of \dQuote{richness} (default) or
#' \dQuote{abundance}.
#' @param \dots Further arguments passed to or from other methods.
#' @rdname raster2comm
#' @importFrom raster raster rasterToPolygons xyFromCell ncell
#' @importFrom raster values
#' @importFrom sp CRS proj4string<-
#' @importFrom data.table as.data.table
#' @return
#' \itemize{
#'   \item comm_dat: community data frame
#'   \item poly_shp: shapefile of grid cells with the values per cell.
#' }
#' @examples
#' \dontrun{
#' fdir <- system.file("NGAplants", package="phyloregion")
#' files <- file.path(fdir, dir(fdir))
#' raster2comm(files)
#' }
#'
#' @export
raster2comm <- function(files) {
    poly <- make_poly(files[1])
    tmp <- raster(files[1])
    fg <- as.data.frame(xyFromCell(tmp, cell=1:ncell(tmp)))
    ind1 <- paste(as.character(fg$x), as.character(fg$y), sep="_")
    ind2 <- paste(as.character(poly$lon), as.character(poly$lat), sep="_")
    index <- match(ind1, ind2)
    res <- NULL
    cells <- as.character(poly$grids)
    for(i in seq_along(files)) {
        obj <- raster(files[i])
        tmp <- values(obj)
        tmp <- cells[index[tmp > 0]]
        tmp <- tmp[!is.na(tmp)]
        if(length(tmp) > 0) res <- rbind(res, cbind(tmp, names(obj)))
    }
    if(length(tmp) > 0) colnames(res) <- c("grids", "species")
    y <- data.table::as.data.table(res)
    return(list(comm_dat = y, poly_shp = poly))
}


#' @rdname raster2comm
#' @importFrom data.table rbindlist
#' @importFrom sp coordinates over CRS proj4string merge
#' @importFrom methods as
#' @examples
#' \dontrun{
#' s <- readRDS(system.file("nigeria/nigeria.rds", package="phyloregion"))
#' sp <- random_species(100, species=5, shp=s)
#' polys2comm(dat = sp, species = "species")
#' }
#'
#' @export
polys2comm <- function(dat, res=1, shp.grids = NULL,
                       species = "species", ...) {
    dat <- dat[, species, drop = FALSE]
    names(dat) <- "species"
    if (length(shp.grids) == 0) {
        e <- extent(dat) + (2 * res)
        # coerce to a SpatialPolygons object
        mask <- as(e, "SpatialPolygons")
        lu <- as.data.frame(1L)
        mask <- sp::SpatialPolygonsDataFrame(mask, lu)
        m <- fishnet(mask, res = res)
    } else m <- shp.grids
    proj4string(dat) <- proj4string(m)
    x <- mapply(cbind, sp::over(dat, m, returnList = TRUE),
                dat@data$species, SIMPLIFY = FALSE)
    y <- rbindlist(x)
    names(y) <- c("grids", "species")
    y <- y[complete.cases(y), ]
    y <- unique(y[, c("grids", "species")])
    res <- data.frame(table(y$grids))
    names(res) <- c("grids", "richness")
    z <- sp::merge(m, res, by = "grids")
    z <- z[!is.na(z@data$richness), ]
    return(list(comm_dat = y, poly_shp = z))
}


#' @rdname raster2comm
#' @importFrom sp coordinates<- over CRS proj4string merge
#' @importFrom sp coordinates<- CRS proj4string<- SpatialPolygonsDataFrame
#' @importFrom stats complete.cases
#' @importFrom raster extent
#' @importFrom data.table as.data.table
#' @examples
#' s <- readRDS(system.file("nigeria/nigeria.rds", package = "phyloregion"))
#'
#' set.seed(1)
#' m <- data.frame(sp::spsample(s, 10000, type = "nonaligned"))
#' names(m) <- c("lon", "lat")
#' species <- paste0("sp", sample(1:1000))
#' m$taxon <- sample(species, size = nrow(m), replace = TRUE)
#'
#' points2comm(dat = m, mask = s, res = 0.5, lon = "lon", lat = "lat",
#'             species = "taxon")
#' @export
points2comm <- function(dat, mask = NULL, res = 1, lon = "decimallongitude",
                        lat = "decimallatitude", species = "species",
                        shp.grids = NULL, index = "taxon_richness", ...) {
    dat <- as.data.frame(dat)
    dat <- dat[, c(species, lon, lat)]
    names(dat) <- c("species", "lon", "lat")

    dat <- dat[complete.cases(dat), ]

    coordinates(dat) <- ~ lon + lat

    if (length(shp.grids) == 0) {
        if (length(mask) == 0) {
            e <- raster::extent(c(xmin = -180, xmax = 180, ymin = -90, ymax = 89))
            p <- as(e, "SpatialPolygons")
            m <- sp::SpatialPolygonsDataFrame(p, data.frame(sp = "x"))
            m <- fishnet(mask = m, res = res)
        } else (m <- fishnet(mask = mask, res = res))
    } else m <- shp.grids
    proj4string(dat) <- proj4string(m)
    x <- over(dat, m)
    #y <- cbind(as.data.frame(dat), x)
    y <- cbind(data.table::as.data.table(dat), x)
    y <- y[complete.cases(y), ]
    if (index == "abundance") {
        y <- y[, c("grids", "species")]
    }
    else if (index == "taxon_richness") {
        y <- unique(y <- y[, c("grids", "species")])
    }
    res <- data.frame(table(y$grids))
    names(res) <- c("grids", "richness")
    z <- sp::merge(m, res, by = "grids")
    z <- z[!is.na(z@data$richness), ]
    return(list(comm_dat = y, poly_shp = z))
}

