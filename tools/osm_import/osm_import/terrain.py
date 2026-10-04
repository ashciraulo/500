"""Terrain heightfield: DEM resampled onto a regular grid in plan coordinates."""
from __future__ import annotations

import numpy as np
from scipy import ndimage

from . import fetch
from .common import Projector


class HeightField:
    """Regular grid of heights. H[j, i] is the height at (e0 + i*step, n0 + j*step)."""

    def __init__(self, e0: float, n0: float, step: float, H: np.ndarray):
        self.e0, self.n0, self.step = e0, n0, step
        self.H = H.astype(np.float64)

    @property
    def shape(self):
        return self.H.shape

    def node_coords(self):
        nj, ni = self.H.shape
        return (self.e0 + np.arange(ni) * self.step, self.n0 + np.arange(nj) * self.step)

    def sample(self, e, n):
        """Height at plan coordinates (vectorised).

        Each grid cell is two planar triangles split along its (i, j)-(i+1, j+1)
        diagonal, exactly like the ground mesh, so anything draped with this
        function lies flush on the ground.
        """
        e = np.asarray(e, dtype=np.float64)
        n = np.asarray(n, dtype=np.float64)
        fx = (e - self.e0) / self.step
        fy = (n - self.n0) / self.step
        nj, ni = self.H.shape
        ix = np.clip(np.floor(fx).astype(np.int64), 0, ni - 2)
        iy = np.clip(np.floor(fy).astype(np.int64), 0, nj - 2)
        tx = np.clip(fx - ix, 0.0, 1.0)
        ty = np.clip(fy - iy, 0.0, 1.0)
        H = self.H
        h00 = H[iy, ix]
        h10 = H[iy, ix + 1]
        h01 = H[iy + 1, ix]
        h11 = H[iy + 1, ix + 1]
        lower = tx >= ty
        return np.where(lower,
                        h00 + tx * (h10 - h00) + ty * (h11 - h10),
                        h00 + ty * (h01 - h00) + tx * (h11 - h01))

    def normal(self, e, n):
        """Smooth surface normal in (e, n, up) components."""
        d = self.step * 0.5
        dhde = (self.sample(e + d, n) - self.sample(e - d, n)) / (2 * d)
        dhdn = (self.sample(e, n + d) - self.sample(e, n - d)) / (2 * d)
        nrm = np.column_stack([-dhde, -dhdn, np.ones_like(dhde)])
        return nrm / np.linalg.norm(nrm, axis=1, keepdims=True)


def _clean_dem(dem: np.ndarray) -> np.ndarray:
    """Remove nodata spikes and most buildings/trees from a surface model."""
    bad = (dem < -50) | (dem > 600)
    if bad.any():
        idx = ndimage.distance_transform_edt(bad, return_distances=False, return_indices=True)
        dem = dem[tuple(idx)]
    # Buildings and trees are positive bumps: a low percentile filter approximates bare earth.
    # Pits (voids, water glints) are filled from the local median first so the
    # percentile filter doesn't spread them.
    med = ndimage.median_filter(dem, size=9)
    dem = np.maximum(dem, med - 1.0)
    big = ndimage.median_filter(dem, size=31)
    dem = np.maximum(dem, big - 2.5)
    dem = ndimage.percentile_filter(dem, 25, size=7)
    return ndimage.gaussian_filter(dem, 1.6)


def build_heightfield(cfg: dict, proj: Projector, e0, n0, e1, n1, step: float) -> HeightField:
    ni = int(np.ceil((e1 - e0) / step)) + 1
    nj = int(np.ceil((n1 - n0) / step)) + 1
    es = e0 + np.arange(ni) * step
    ns = n0 + np.arange(nj) * step
    E, N = np.meshgrid(es, ns)
    lon, lat = proj.inv(E.ravel(), N.ravel())
    pad = 0.01
    dem, georef = fetch.dem_mosaic(cfg, lon.min() - pad, lat.min() - pad, lon.max() + pad, lat.max() + pad)
    dem = _clean_dem(dem)
    px, py = georef(lon, lat)
    H = ndimage.map_coordinates(dem, [py, px], order=1, mode="nearest").reshape(nj, ni)
    return HeightField(e0, n0, step, H)
