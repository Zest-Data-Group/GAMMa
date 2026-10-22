# Prototype for ticket T-03 (dev/tickets/T-03-antimeridian-hull.md), 2026-10-22.
# Run from the repo root: Rscript dev/prototype_antimeridian_hull.R

suppressMessages(library(terra))
land <- vect("appData/land_simple.gpkg")
hull_rot <- function(lon, lat, land) {
  s <- sort(unique(lon)); gaps <- diff(c(s, s[1] + 360)); i <- which.max(gaps)
  seam <- s[i] + gaps[i] / 2                     # centre of largest empty gap
  if (seam > 180) seam <- seam - 360
  lon2 <- ifelse(lon > seam, lon - 360, lon)     # unwrap into (seam-360, seam]
  v <- vect(cbind(lon2, lat), crs = "EPSG:4326")
  h <- convHull(v)
  crosses <- min(lon2) < -180
  land2 <- if (crosses) rotate(land, longitude = seam, split = TRUE, left = TRUE) else land
  clipped <- intersect(h, land2)
  if (length(clipped) == 0) stop("no land")
  out <- aggregate(clipped)
  if (crosses) out <- rotate(out, longitude = -180, split = TRUE, left = FALSE)
  list(seam = seam, crosses = crosses, area_km2 = expanse(out, unit = "km"), ext = as.vector(ext(out)), n = nrow(out))
}
t0 <- Sys.time()
cat("Fiji:\n"); print(hull_rot(c(179.9,-179.9,178.5,177.5), c(-16.8,-17.5,-16.5,-18.1), land))
cat("Fiji translated to Brazil (control, same shape):\n"); print(hull_rot(c(179.9,-179.9,178.5,177.5) - 225, c(-16.8,-17.5,-16.5,-18.1), land))
cat("Two hemispheres (E N America + Japan):\n"); print(hull_rot(c(-84,-80,-75,138,140,142), c(35,40,38,35,37,40), land))
cat("Same points shifted +100 lon (Atlantic gap now largest?):\n"); print(hull_rot(c(-84,-80,-75,138,140,142)+100, c(35,40,38,35,37,40), land))
cat("Brazil control:\n"); print(hull_rot(c(-45,-46,-44,-45.5), c(-10,-11,-10.5,-9), land))
cat("Circumboreal (Europe, Siberia, Alaska, Canada):\n"); print(hull_rot(c(10,60,120,170,-150,-100,-60), c(60,62,63,64,65,60,58), land))
print(Sys.time() - t0)
