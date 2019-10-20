# Copyright (c) 2010-2019 The Regents of the University of Michigan
# This file is from the freud project, released under the BSD 3-Clause License.

R"""
The :class:`freud.density` module contains various classes relating to the
density of the system. These functions allow evaluation of particle
distributions with respect to other particles.
"""

import freud.locality
import warnings
import numpy as np

from cython.operator cimport dereference
from freud.util cimport _Compute
from freud.locality cimport _PairCompute, _SpatialHistogram1D
from freud.util cimport vec3

from collections.abc import Sequence

cimport freud._density
cimport freud.box, freud.locality
cimport numpy as np
cimport freud.util

# numpy must be initialized. When using numpy from C or Cython you must
# _always_ do that, or you will have segfaults
np.import_array()

ctypedef unsigned int uint

cdef class CorrelationFunction(_SpatialHistogram1D):
    R"""Computes the complex pairwise correlation function.

    The correlation function is given by
    :math:`C(r) = \left\langle s_1(0) \cdot s_2(r) \right\rangle` between
    two sets of points :math:`p_1` (:code:`points`) and :math:`p_2`
    (:code:`query_points`) with associated values :math:`s_1` (:code:`values`)
    and :math:`s_2` (:code:`query_values`). Computing the correlation function
    results in an array of the expected (average) product of all values at a
    given radial distance :math:`r`.

    The values of :math:`r` where the correlation function is computed are
    controlled by the :code:`r_max` and :code:`dr` parameters to the
    constructor. :code:`r_max` determines the maximum distance at which to
    compute the correlation function and :code:`dr` is the step size for each
    bin.

    .. note::
        **Self-correlation:** It is often the case that we wish to compute the
        correlation function of a set of points with itself. If
        :code:`query_points` is the same as :code:`points`, not provided, or
        :code:`None`, we omit accumulating the self-correlation value in the
        first bin.

    Args:
        bins (unsigned int):
            The number of bins in the RDF.
        r_max (float):
            Maximum pointwise distance to include in the calculation.
    """  # noqa E501
    cdef freud._density.CorrelationFunction[np.complex128_t] * thisptr
    cdef is_complex

    def __cinit__(self, unsigned int bins, float r_max):
        self.thisptr = self.histptr = new \
            freud._density.CorrelationFunction[np.complex128_t](bins, r_max)
        self.r_max = r_max
        self.is_complex = False

    def __dealloc__(self):
        del self.thisptr

    def compute(self, system, values, query_points=None,
                query_values=None, neighbors=None, reset=True):
        R"""Calculates the correlation function and adds to the current
        histogram.

        Args:
            system:
                Any object that is a valid argument to
                :class:`freud.locality.NeighborQuery.from_system`.
            values ((:math:`N_{points}`) :class:`numpy.ndarray`):
                Values associated with the system points used to calculate the
                correlation function.
            query_points ((:math:`N_{query\_points}`, 3) :class:`numpy.ndarray`, optional):
                Query points used to calculate the correlation function.  Uses
                the system's points if :code:`None` (Default value =
                :code:`None`).
            query_values ((:math:`N_{query\_points}`) :class:`numpy.ndarray`, optional):
                Query values used to calculate the correlation function.  Uses
                :code:`values` if :code:`None`.  (Default value
                = :code:`None`).
            neighbors (:class:`freud.locality.NeighborList` or dict, optional):
                Either a :class:`NeighborList <freud.locality.NeighborList>` of
                neighbor pairs to use in the calculation, or a dictionary of
                `query arguments
                <https://freud.readthedocs.io/en/next/querying.html>`_
                (Default value: None).
            reset (bool):
                Whether to erase the previously computed values before adding
                the new computation; if False, will accumulate data (Default
                value: True).
        """  # noqa E501
        if reset:
            self.is_complex = False
            self._reset()

        cdef:
            freud.locality.NeighborQuery nq
            freud.locality.NeighborList nlist
            freud.locality._QueryArgs qargs
            const float[:, ::1] l_query_points
            unsigned int num_query_points

        nq, nlist, qargs, l_query_points, num_query_points = \
            self._preprocess_arguments(system, query_points, neighbors)

        # Save if any inputs have been complex so far.
        self.is_complex = self.is_complex or np.any(np.iscomplex(values)) or \
            np.any(np.iscomplex(query_values))

        values = freud.util._convert_array(
            values, shape=(nq.points.shape[0], ), dtype=np.complex128)
        if query_values is None:
            query_values = values
        else:
            query_values = freud.util._convert_array(
                query_values, shape=(l_query_points.shape[0], ),
                dtype=np.complex128)

        cdef np.complex128_t[::1] l_values = values
        cdef np.complex128_t[::1] l_query_values = query_values

        self.thisptr.accumulate(
            nq.get_ptr(),
            <np.complex128_t*> &l_values[0],
            <vec3[float]*> &l_query_points[0, 0],
            <np.complex128_t*> &l_query_values[0],
            num_query_points, nlist.get_ptr(),
            dereference(qargs.thisptr))
        return self

    @_Compute._computed_property
    def correlation(self):
        """(:math:`N_{bins}`) :class:`numpy.ndarray`: Expected (average)
        product of all values at a given radial distance."""
        output = freud.util.make_managed_numpy_array(
            &self.thisptr.getCorrelation(),
            freud.util.arr_type_t.COMPLEX_DOUBLE)
        return output if self.is_complex else np.real(output)

    def __repr__(self):
        return ("freud.density.{cls}(bins={bins}, r_max={r_max})").format(
            cls=type(self).__name__, bins=self.nbins, r_max=self.r_max)

    def plot(self, ax=None):
        """Plot complex correlation function.

        Args:
            ax (:class:`matplotlib.axes.Axes`, optional): Axis to plot on. If
                :code:`None`, make a new figure and axis.
                (Default value = :code:`None`)

        Returns:
            (:class:`matplotlib.axes.Axes`): Axis with the plot.
        """
        import freud.plot
        return freud.plot.line_plot(self.R, np.real(self.RDF),
                                    title="Correlation Function",
                                    xlabel=r"$r$",
                                    ylabel=r"$\operatorname{Re}(C(r))$",
                                    ax=ax)

    def _repr_png_(self):
        try:
            import freud.plot
            return freud.plot._ax_to_bytes(self.plot())
        except (AttributeError, ImportError):
            return None


cdef class GaussianDensity(_Compute):
    R"""Computes the density of a system on a grid.

    Replaces particle positions with a Gaussian blur and calculates the
    contribution from each to the proscribed grid based upon the distance of
    the grid cell from the center of the Gaussian. The resulting data is a
    regular grid of particle densities that can be used in standard algorithms
    requiring evenly spaced point, such as Fast Fourier Transforms. The
    dimensions of the image (grid) are set in the constructor, and can either
    be set equally for all dimensions or for each dimension independently.

    Args:
        width (int or list or tuple):
            The number of bins to make the image in each direction (identical
            in all dimensions if a single integer value is provided).
        r_max (float):
            Distance over which to blur.
        sigma (float):
            Sigma parameter for Gaussian.
    """  # noqa: E501
    cdef freud._density.GaussianDensity * thisptr

    def __cinit__(self, width, r_max, sigma):
        cdef vec3[uint] width_vector
        if isinstance(width, int):
            width_vector = vec3[uint](width, width, width)
        elif isinstance(width, Sequence) and len(width) == 2:
            width_vector = vec3[uint](width[0], width[1], 1)
        elif isinstance(width, Sequence) and len(width) == 3:
            width_vector = vec3[uint](width[0], width[1], width[2])
        else:
            raise ValueError("The width must be either a number of bins or a "
                             "sequence indicating the widths in each spatial "
                             "dimension (length 2 in 2D, length 3 in 3D).")

        self.thisptr = new freud._density.GaussianDensity(
            width_vector, r_max, sigma)

    def __dealloc__(self):
        del self.thisptr

    @_Compute._computed_property
    def box(self):
        """:class:`freud.box.Box`: Box used in the calculation."""
        return freud.box.BoxFromCPP(self.thisptr.getBox())

    def compute(self, system):
        R"""Calculates the Gaussian blur for the specified points.

        Args:
            system:
                Any object that is a valid argument to
                :class:`freud.locality.NeighborQuery.from_system`.
        """
        cdef freud.locality.NeighborQuery nq = \
            freud.locality.NeighborQuery.from_system(system)
        self.thisptr.compute(nq.get_ptr())
        return self

    @_Compute._computed_property
    def density(self):
        """(:math:`w_x`, :math:`w_y`, :math:`w_z`) :class:`numpy.ndarray`: The
        image grid with the Gaussian density."""
        if self.box.is2D:
            return np.squeeze(freud.util.make_managed_numpy_array(
                &self.thisptr.getDensity(), freud.util.arr_type_t.FLOAT))
        else:
            return freud.util.make_managed_numpy_array(
                &self.thisptr.getDensity(), freud.util.arr_type_t.FLOAT)

    @property
    def r_max(self):
        """float: Distance over which to blur."""
        return self.thisptr.getRMax()

    @property
    def sigma(self):
        """float: Sigma parameter for Gaussian."""
        return self.thisptr.getSigma()

    @property
    def width(self):
        """int or list or tuple: The number of bins to make the image in each
        direction (identical in all dimensions if a single integer value is
        provided)."""
        cdef vec3[uint] width = self.thisptr.getWidth()
        return (width.x, width.y, width.z)

    def __repr__(self):
        return ("freud.density.{cls}({width}, "
                "{r_max}, {sigma})").format(cls=type(self).__name__,
                                            width=self.width,
                                            r_max=self.r_max,
                                            sigma=self.sigma)

    def plot(self, ax=None):
        """Plot Gaussian Density.

        Args:
            ax (:class:`matplotlib.axes.Axes`, optional): Axis to plot on. If
                :code:`None`, make a new figure and axis.
                (Default value = :code:`None`)

        Returns:
            (:class:`matplotlib.axes.Axes`): Axis with the plot.
        """
        import freud.plot
        if not self.box.is2D:
            return None
        return freud.plot.density_plot(self.density, self.box, ax=ax)

    def _repr_png_(self):
        try:
            import freud.plot
            return freud.plot._ax_to_bytes(self.plot())
        except (AttributeError, ImportError):
            return None


cdef class LocalDensity(_PairCompute):
    R"""Computes the local density around a particle.

    The density of the local environment is computed and averaged for a given
    set of query points in a sea of data points. Providing the same points
    calculates them against themselves. Computing the local density results in
    an array listing the value of the local density around each query
    point. Also available is the number of neighbors for each query point,
    giving the user the ability to count the number of particles in that
    region. Note that the computed density is essentially a number density
    (that allows for fractional values as described below). If your particles
    have a specific volume, you can compute a volume density by simply
    multiplying the output by the volume of the particles.

    In order to provide sufficiently smooth data, data points can be
    fractionally counted towards the density.  Rather than perform
    compute-intensive area (volume) overlap calculations to
    determine the exact amount of overlap area (volume), the LocalDensity class
    performs a simple linear interpolation relative to the centers of the data
    points.  Specifically, a point is counted as one neighbor of a given
    query point if it is entirely contained within the :code:`r_max`, half
    of a neighbor if the distance to its center is exactly :code:`r_max`, and
    zero if its center is a distance greater than or equal to :code:`r_max +
    diameter` from the query point's center. Graphically, this looks like:

    .. image:: images/density.png

    Args:
        r_max (float):
            Maximum distance over which to calculate the density.
        diameter (float):
            Diameter of particle circumsphere.
    """
    cdef freud._density.LocalDensity * thisptr

    def __cinit__(self, float r_max, float diameter):
        self.thisptr = new freud._density.LocalDensity(r_max, diameter)

    def __dealloc__(self):
        del self.thisptr

    @property
    def r_max(self):
        """float: Maximum distance over which to calculate the density."""
        return self.thisptr.getRMax()

    @property
    def diameter(self):
        """float: Diameter of particle circumsphere."""
        return self.thisptr.getDiameter()

    @_Compute._computed_property
    def box(self):
        """:class:`freud.box.Box`: Box used in the calculation."""
        return freud.box.BoxFromCPP(self.thisptr.getBox())

    def compute(self, system, query_points=None, neighbors=None):
        R"""Calculates the local density for the specified points. Does not
        accumulate (will overwrite current data).

        Args:
            system:
                Any object that is a valid argument to
                :class:`freud.locality.NeighborQuery.from_system`.
            query_points ((:math:`N_{query\_points}`, 3) :class:`numpy.ndarray`, optional):
                Query points used to calculate the correlation function. Uses
                the system's points if :code:`None` (Default
                value = :code:`None`).
            neighbors (:class:`freud.locality.NeighborList` or dict, optional):
                Either a :class:`NeighborList <freud.locality.NeighborList>` of
                neighbor pairs to use in the calculation, or a dictionary of
                `query arguments
                <https://freud.readthedocs.io/en/next/querying.html>`_
                (Default value: None).
        """  # noqa E501
        cdef:
            freud.locality.NeighborQuery nq
            freud.locality.NeighborList nlist
            freud.locality._QueryArgs qargs
            const float[:, ::1] l_query_points
            unsigned int num_query_points

        nq, nlist, qargs, l_query_points, num_query_points = \
            self._preprocess_arguments(system, query_points, neighbors)
        self.thisptr.compute(
            nq.get_ptr(),
            <vec3[float]*> &l_query_points[0, 0],
            num_query_points, nlist.get_ptr(),
            dereference(qargs.thisptr))
        return self

    @property
    def default_query_args(self):
        """The default query arguments are
        :code:`{'mode': 'ball', 'r_max': self.r_max + 0.5*self.diameter}`."""
        return dict(mode="ball",
                    r_max=self.r_max + 0.5*self.diameter)

    @_Compute._computed_property
    def density(self):
        """(:math:`N_{points}`) :class:`numpy.ndarray`: Density of points per
        query point."""
        return freud.util.make_managed_numpy_array(
            &self.thisptr.getDensity(),
            freud.util.arr_type_t.FLOAT)

    @_Compute._computed_property
    def num_neighbors(self):
        """(:math:`N_{points}`) :class:`numpy.ndarray`: Number of neighbor
        points for each query point."""
        return freud.util.make_managed_numpy_array(
            &self.thisptr.getNumNeighbors(),
            freud.util.arr_type_t.FLOAT)

    def __repr__(self):
        return ("freud.density.{cls}(r_max={r_max}, "
                "diameter={diameter})").format(cls=type(self).__name__,
                                               r_max=self.r_max,
                                               diameter=self.diameter)


cdef class RDF(_SpatialHistogram1D):
    R"""Computes RDF for supplied data.

    The RDF (:math:`g \left( r \right)`) is computed and averaged for a given
    set of query points in a sea of data points. Providing the same points
    calculates them against themselves. Computing the RDF results in an RDF
    array listing the value of the RDF at each given :math:`r`, listed in the
    :code:`R` array.

    The values of :math:`r` to compute the RDF are set by the values of
    :code:`r_min`, :code:`r_max`, :code:`bins` in the constructor.
    :code:`r_max` sets the maximum distance at which to calculate the :math:`g
    \left( r \right)`, :code:`r_min` sets the minimum distance at which to
    calculate the :math:`g \left( r \right)`, and :code:`bins` determines the
    number of bins.

    .. note::
        **2D:** :class:`freud.density.RDF` properly handles 2D boxes.
        The points must be passed in as :code:`[x, y, 0]`.

    Args:
        bins (unsigned int):
            The number of bins in the RDF.
        r_max (float):
            Maximum interparticle distance to include in the calculation.
        r_min (float, optional):
            Minimum interparticle distance to include in the calculation
            (Default value = :code:`0`).
    """
    cdef freud._density.RDF * thisptr

    def __cinit__(self, unsigned int bins, float r_max, float r_min=0):
        if type(self) == RDF:
            self.thisptr = self.histptr = new freud._density.RDF(
                bins, r_max, r_min)

            # r_max is left as an attribute rather than a property for now
            # since that change needs to happen at the _SpatialHistogram level
            # for multiple classes.
            self.r_max = r_max

    def __dealloc__(self):
        if type(self) == RDF:
            del self.thisptr

    def compute(self, system, query_points=None, neighbors=None,
                reset=True):
        R"""Calculates the RDF and adds to the current RDF histogram.

        Args:
            system:
                Any object that is a valid argument to
                :class:`freud.locality.NeighborQuery.from_system`.
            query_points ((:math:`N_{query\_points}`, 3) :class:`numpy.ndarray`, optional):
                Query points used to calculate the RDF. Uses the system's
                points if :code:`None` (Default value =
                :code:`None`).
            neighbors (:class:`freud.locality.NeighborList` or dict, optional):
                Either a :class:`NeighborList <freud.locality.NeighborList>` of
                neighbor pairs to use in the calculation, or a dictionary of
                `query arguments
                <https://freud.readthedocs.io/en/next/querying.html>`_
                (Default value: None).
            reset (bool):
                Whether to erase the previously computed values before adding
                the new computation; if False, will accumulate data (Default
                value: True).
        """  # noqa E501
        if reset:
            self._reset()

        cdef:
            freud.locality.NeighborQuery nq
            freud.locality.NeighborList nlist
            freud.locality._QueryArgs qargs
            const float[:, ::1] l_query_points
            unsigned int num_query_points
        nq, nlist, qargs, l_query_points, num_query_points = \
            self._preprocess_arguments(system, query_points, neighbors)

        self.thisptr.accumulate(
            nq.get_ptr(),
            <vec3[float]*> &l_query_points[0, 0],
            num_query_points, nlist.get_ptr(),
            dereference(qargs.thisptr))
        return self

    @_Compute._computed_property
    def rdf(self):
        """(:math:`N_{bins}`,) :class:`numpy.ndarray`: Histogram of RDF
        values."""
        return freud.util.make_managed_numpy_array(
            &self.thisptr.getRDF(),
            freud.util.arr_type_t.FLOAT)

    @_Compute._computed_property
    def n_r(self):
        """(:math:`N_{bins}`,) :class:`numpy.ndarray`: Histogram of cumulative
        bin_counts values. More precisely, :code:`n_r[i]` is the average number
        of points contained within a ball of radius :code:`R[i]+dr/2` centered
        at a given :code:`query_point` averaged over all :code:`query_points`
        in the last call to :meth:`~.compute` (or :meth:`~.accumulate`)."""
        return freud.util.make_managed_numpy_array(
            &self.thisptr.getNr(),
            freud.util.arr_type_t.FLOAT)

    def __repr__(self):
        return ("freud.density.{cls}(bins={bins}, r_max={r_max}, "
                "r_min={r_min})").format(cls=type(self).__name__,
                                         bins=len(self.bin_centers),
                                         r_max=self.bounds[1],
                                         r_min=self.bounds[0])

    def plot(self, ax=None):
        """Plot radial distribution function.

        Args:
            ax (:class:`matplotlib.axes.Axes`, optional): Axis to plot on. If
                :code:`None`, make a new figure and axis.
                (Default value = :code:`None`)

        Returns:
            (:class:`matplotlib.axes.Axes`): Axis with the plot.
        """
        import freud.plot
        return freud.plot.line_plot(self.R, self.RDF,
                                    title="RDF",
                                    xlabel=r"$r$",
                                    ylabel=r"$g(r)$",
                                    ax=ax)

    def _repr_png_(self):
        try:
            import freud.plot
            return freud.plot._ax_to_bytes(self.plot())
        except (AttributeError, ImportError):
            return None
