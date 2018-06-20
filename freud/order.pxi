# Copyright (c) 2010-2018 The Regents of the University of Michigan
# This file is part of the freud project, released under the BSD 3-Clause License.

import numpy as np
import time
from freud.util._VectorMath cimport vec3
from freud.util._VectorMath cimport quat
from freud.util._Boost cimport shared_array
from libcpp.memory cimport shared_ptr
from libcpp.complex cimport complex
from libcpp.vector cimport vector
from libcpp.map cimport map
from libcpp.pair cimport pair
cimport freud._box as _box
cimport freud._order as order
cimport numpy as np

# numpy must be initialized. When using numpy from C or Cython you must
# _always_ do that, or you will have segfaults
np.import_array()

cdef class CubaticOrderParameter:
    """Compute the cubatic order parameter [Cit1]_ for a system of particles
    using simulated annealing instead of Newton-Raphson root finding.

    .. moduleauthor:: Eric Harper <harperic@umich.edu>

    :param float t_initial: Starting temperature
    :param float t_final: Final temperature
    :param float scale: Scaling factor to reduce temperature
    :param n_replicates: Number of replicate simulated annealing runs
    :param seed: random seed to use in calculations. If None, system time used
    :type n_replicates: unsigned int
    :type seed: unsigned int

    """
    cdef order.CubaticOrderParameter * thisptr

    def __cinit__(self, t_initial, t_final, scale, n_replicates=1, seed=None):
        # run checks
        if (t_final >= t_initial):
            raise ValueError("t_final must be less than t_initial")
        if (scale >= 1.0):
            raise ValueError("scale must be less than 1")
        if seed is None:
            seed = int(time.time())
        elif not isinstance(seed, int):
            try:
                seed = int(seed)
            finally:
                print("supplied seed could not be used. using time as seed")
                seed = time.time()

        # for c++ code
        # create generalized rank four tensor, pass into c++
        cdef np.ndarray[float, ndim = 2] kd = np.eye(3, dtype=np.float32)
        cdef np.ndarray[float, ndim = 4] dijkl = np.einsum(
                "ij,kl->ijkl", kd, kd, dtype=np.float32)
        cdef np.ndarray[float, ndim = 4] dikjl = np.einsum(
                "ik,jl->ijkl", kd, kd, dtype=np.float32)
        cdef np.ndarray[float, ndim = 4] diljk = np.einsum(
                "il,jk->ijkl", kd, kd, dtype=np.float32)
        cdef np.ndarray[float, ndim = 4] r4 = dijkl+dikjl+diljk
        r4 *= (2.0/5.0)
        self.thisptr = new order.CubaticOrderParameter(
                t_initial, t_final, scale, < float*>r4.data,
                n_replicates, seed)

    def compute(self, orientations):
        """Calculates the per-particle and global order parameter.

        :param box: simulation box
        :param orientations: orientations to calculate the order parameter
        :type box: :py:class:`freud.box.Box`
        :type orientations: :class:`numpy.ndarray`,
                            shape= :math:`\\left(N_{particles}, 4 \\right)`,
                            dtype= :class:`numpy.float32`
        """
        orientations = freud.common.convert_array(
                orientations, 2, dtype=np.float32, contiguous=True,
                dim_message="orientations must be a 2 dimensional array")
        if orientations.shape[1] != 4:
            raise TypeError('orientations should be an Nx4 array')

        cdef np.ndarray[float, ndim = 2] l_orientations = orientations
        cdef unsigned int num_particles = <unsigned int > orientations.shape[0]

        with nogil:
            self.thisptr.compute(
                    < quat[float]*>l_orientations.data, num_particles, 1)
        return self

    def get_t_initial(self):
        """
        :return: value of initial temperature
        :rtype: float
        """
        return self.thisptr.getTInitial()

    def get_t_final(self):
        """
        :return: value of final temperature
        :rtype: float
        """
        return self.thisptr.getTFinal()

    def get_scale(self):
        """
        :return: value of scale
        :rtype: float
        """
        return self.thisptr.getScale()

    def get_cubatic_order_parameter(self):
        """
        :return: Cubatic order parameter
        :rtype: float
        """
        return self.thisptr.getCubaticOrderParameter()

    def get_orientation(self):
        """
        :return: orientation of global orientation
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(4 \\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef quat[float] q = self.thisptr.getCubaticOrientation()
        cdef np.ndarray[float, ndim = 1] result = np.array(
                [q.s, q.v.x, q.v.y, q.v.z], dtype=np.float32)
        return result

    def get_particle_op(self):
        """
        :return: Cubatic order parameter
        :rtype: float
        """
        cdef float * particle_op = \
            self.thisptr.getParticleCubaticOrderParameter().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.thisptr.getNumParticles()
        cdef np.ndarray[np.float32_t, ndim = 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_FLOAT32, < void*>particle_op)
        return result

    def get_particle_tensor(self):
        """
        :return: Rank 4 tensor corresponding to each individual particle
                    orientation
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}, 3, 3, 3, 3 \\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float * particle_tensor = self.thisptr.getParticleTensor().get()
        cdef np.npy_intp nbins[5]
        nbins[0] = <np.npy_intp > self.thisptr.getNumParticles()
        nbins[1] = <np.npy_intp > 3
        nbins[2] = <np.npy_intp > 3
        nbins[3] = <np.npy_intp > 3
        nbins[4] = <np.npy_intp > 3
        cdef np.ndarray[np.float32_t, ndim= 5
                        ] result = np.PyArray_SimpleNewFromData(
                                5, nbins, np.NPY_FLOAT32,
                                < void*>particle_tensor)
        return result

    def get_global_tensor(self):
        """
        :return: Rank 4 tensor corresponding to each individual particle
                    orientation
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(3, 3, 3, 3 \\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float * global_tensor = self.thisptr.getGlobalTensor().get()
        cdef np.npy_intp nbins[4]
        nbins[0] = <np.npy_intp > 3
        nbins[1] = <np.npy_intp > 3
        nbins[2] = <np.npy_intp > 3
        nbins[3] = <np.npy_intp > 3
        cdef np.ndarray[np.float32_t, ndim= 4
                        ] result = np.PyArray_SimpleNewFromData(
                                4, nbins, np.NPY_FLOAT32,
                                < void*>global_tensor)
        return result

    def get_cubatic_tensor(self):
        """
        :return: Rank 4 tensor corresponding to each individual particle
                    orientation
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(3, 3, 3, 3 \\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float * cubatic_tensor = self.thisptr.getCubaticTensor().get()
        cdef np.npy_intp nbins[4]
        nbins[0] = <np.npy_intp > 3
        nbins[1] = <np.npy_intp > 3
        nbins[2] = <np.npy_intp > 3
        nbins[3] = <np.npy_intp > 3
        cdef np.ndarray[np.float32_t, ndim= 4
                        ] result = np.PyArray_SimpleNewFromData(
                                4, nbins, np.NPY_FLOAT32,
                                < void*>cubatic_tensor)
        return result

    def get_gen_r4_tensor(self):
        """
        :return: Rank 4 tensor corresponding to each individual particle
                    orientation
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(3, 3, 3, 3 \\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float * gen_r4_tensor = self.thisptr.getGenR4Tensor().get()
        cdef np.npy_intp nbins[4]
        nbins[0] = <np.npy_intp > 3
        nbins[1] = <np.npy_intp > 3
        nbins[2] = <np.npy_intp > 3
        nbins[3] = <np.npy_intp > 3
        cdef np.ndarray[np.float32_t, ndim= 4
                        ] result = np.PyArray_SimpleNewFromData(
                                4, nbins, np.NPY_FLOAT32,
                                < void*>gen_r4_tensor)
        return result


cdef class NematicOrderParameter:
    """Compute the nematic order parameter for a system of particles.

    .. moduleauthor:: Jens Glaser <jsglaser@umich.edu>

    .. versionadded:: 0.7.0

    :param u: The nematic director of a single particle in the reference
              state (without any rotation applied)
    :type u: :class:`numpy.ndarray`,
             shape= :math:`\\left(3 \\right)`,
             dtype= :class:`numpy.float32`
    """
    cdef order.NematicOrderParameter *thisptr

    def __cinit__(self, u):
        # run checks
        if len(u) != 3:
            raise ValueError('u needs to be a three-dimensional vector')

        cdef np.ndarray[np.float32_t, ndim=1] l_u = \
                np.array(u,dtype=np.float32)
        self.thisptr = new order.NematicOrderParameter(
            (<vec3[float]*>l_u.data)[0])

    def compute(self, orientations):
        """Calculates the per-particle and global order parameter.

        :param orientations: orientations to calculate the order parameter
        :type orientations: :class:`numpy.ndarray`,
                            shape= :math:`\\left(N_{particles}, 4 \\right)`,
                            dtype= :class:`numpy.float32`
        """
        orientations = freud.common.convert_array(
            orientations, 2, dtype=np.float32, contiguous=True,
            dim_message="orientations must be a 2 dimensional array")
        if orientations.shape[1] != 4:
            raise TypeError('orientations should be an Nx4 array')

        cdef np.ndarray[float, ndim=2] l_orientations = orientations
        cdef unsigned int num_particles = <unsigned int> orientations.shape[0]

        with nogil:
            self.thisptr.compute(<quat[float]*>l_orientations.data,
                                 num_particles)

    def get_nematic_order_parameter(self):
        """The nematic order parameter.

        :return: Nematic order parameter
        :rtype: float
        """
        return self.thisptr.getNematicOrderParameter()

    def get_director(self):
        """The director (eigenvector corresponding to the order parameter).

        :return: The average nematic director
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(3 \\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef vec3[float] n = self.thisptr.getNematicDirector()
        cdef np.ndarray[np.float32_t, ndim=1] result = np.array(
                [n.x,n.y,n.z], dtype=np.float32)
        return result

    def get_particle_tensor(self):
        """The full per-particle tensor of orientation information.

        :return: 3x3 matrix corresponding to each individual particle
                 orientation
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}, 3, 3 \\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float *particle_tensor = self.thisptr.getParticleTensor().get()
        cdef np.npy_intp nbins[3]
        nbins[0] = <np.npy_intp>self.thisptr.getNumParticles()
        nbins[1] = <np.npy_intp>3
        nbins[2] = <np.npy_intp>3
        cdef np.ndarray[np.float32_t, ndim=3] result = \
                np.PyArray_SimpleNewFromData(
                    3, nbins, np.NPY_FLOAT32, <void*>particle_tensor)
        return result

    def get_nematic_tensor(self):
        """The nematic Q tensor.

        :return: 3x3 matrix corresponding to the average particle orientation
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(3, 3 \\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float *nematic_tensor = self.thisptr.getNematicTensor().get()
        cdef np.npy_intp nbins[2]
        nbins[0] = <np.npy_intp>3
        nbins[1] = <np.npy_intp>3
        cdef np.ndarray[np.float32_t, ndim=2] result = \
                np.PyArray_SimpleNewFromData(
                    2, nbins, np.NPY_FLOAT32, <void*>nematic_tensor)
        return result

cdef class HexOrderParameter:
    """Calculates the :math:`k`-atic order parameter for each particle in the
    system.

    The :math:`k`-atic order parameter for a particle :math:`i` and its
    :math:`n` neighbors :math:`j` is given by:

    :math:`\\psi_k \\left( i \\right) = \\frac{1}{n}
    \\sum_j^n e^{k i \\phi_{ij}}`

    The parameter :math:`k` governs the symmetry of the order parameter while
    the parameter :math:`n` governs the number of neighbors of particle
    :math:`i` to average over. :math:`\\phi_{ij}` is the angle between the
    vector :math:`r_{ij}` and :math:`\\left( 1,0 \\right)`

    .. note:: 2D: This calculation is defined for 2D systems only. However,
              particle positions are still required to be passed in as
              :code:`[x, y, 0]`.

    .. moduleauthor:: Eric Harper <harperic@umich.edu>

    :param float rmax: +/- r distance to search for neighbors
    :param k: symmetry of order parameter (:math:`k=6` is hexatic)
    :param n: number of neighbors (:math:`n=k` if :math:`n` not specified)
    :type k: unsigned int
    :type n: unsigned int
    """
    cdef order.HexOrderParameter * thisptr
    cdef num_neigh
    cdef rmax

    def __cinit__(self, rmax, k=int(6), n=int(0)):
        self.thisptr = new order.HexOrderParameter(rmax, k, n)
        self.rmax = rmax
        self.num_neigh = (n if n else int(k))

    def __dealloc__(self):
        del self.thisptr

    def compute(self, box, points, nlist=None):
        """Calculates the correlation function and adds to the current
        histogram.

        :param box: simulation box
        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type box: :py:class:`freud.box.Box`
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3 \\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        points = freud.common.convert_array(
                points, 2, dtype=np.float32, contiguous=True,
                dim_message="points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef np.ndarray[float, ndim = 2] l_points = points
        cdef unsigned int nP = <unsigned int > points.shape[0]

        defaulted_nlist = make_default_nlist_nn(
            box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        cdef locality.NeighborList * nlist_ptr = nlist_.get_ptr()

        cdef _box.Box l_box = _box.Box(
                box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(),
                box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        with nogil:
            self.thisptr.compute(
                    l_box, nlist_ptr, < vec3[float]*>l_points.data, nP)
        return self

    @property
    def psi(self):
        """Order parameter.
        """
        return self.getPsi()

    def getPsi(self):
        """Get the order parameter.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles} \\right)`,
                dtype= :class:`numpy.complex64`
        """
        cdef float complex * psi = self.thisptr.getPsi().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_COMPLEX64, < void*>psi)
        return result

    @property
    def box(self):
        """Get the box used in the calculation.
        """
        return self.getBox()

    def getBox(self):
        """Get the box used in the calculation.

        :return: freud Box
        :rtype: :py:class:`freud.box.Box`
        """
        return BoxFromCPP(< box.Box > self.thisptr.getBox())

    @property
    def num_particles(self):
        """Get the number of particles.
        """
        return self.getNP()

    def getNP(self):
        """Get the number of particles.

        :return: :math:`N_{particles}`
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

    @property
    def k(self):
        """Symmetry of the order parameter.
        """
        return self.getK()

    def getK(self):
        """Get the symmetry of the order parameter.

        :return: :math:`k`
        :rtype: unsigned int
        """
        cdef unsigned int k = self.thisptr.getK()
        return k

cdef class TransOrderParameter:
    """Compute the translational order parameter for each particle.

    .. moduleauthor:: Michael Engel <engelmm@umich.edu>

    :param float rmax: +/- r distance to search for neighbors
    :param float k: symmetry of order parameter (:math:`k=6` is hexatic)
    :param n: number of neighbors (:math:`n=k` if :math:`n` not specified)
    :type n: unsigned int

    """
    cdef order.TransOrderParameter * thisptr
    cdef num_neigh
    cdef rmax

    def __cinit__(self, rmax, k=6.0, n=0):
        self.thisptr = new order.TransOrderParameter(rmax, k, n)
        self.rmax = rmax
        self.num_neigh = (n if n else int(k))

    def __dealloc__(self):
        del self.thisptr

    def compute(self, box, points, nlist=None):
        """Calculates the local descriptors.

        :param box: simulation box
        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type box: :py:class:`freud.box.Box`
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3 \\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        points = freud.common.convert_array(
                points, 2, dtype=np.float32, contiguous=True,
                dim_message="points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef _box.Box l_box = _box.Box(
                box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(),
                box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        cdef np.ndarray[float, ndim = 2] l_points = points
        cdef unsigned int nP = <unsigned int > points.shape[0]

        defaulted_nlist = make_default_nlist_nn(
            box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        cdef locality.NeighborList * nlist_ptr = nlist_.get_ptr()

        with nogil:
            self.thisptr.compute(
                    l_box, nlist_ptr, < vec3[float]*>l_points.data, nP)
        return self

    @property
    def d_r(self):
        """Get a reference to the last computed spherical harmonic array.
        """
        return self.getDr()

    def getDr(self):
        """Get a reference to the last computed spherical harmonic array.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.complex64`
        """
        cdef float complex * dr = self.thisptr.getDr().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                            1, nbins, np.NPY_COMPLEX64, < void*>dr)
        return result

    @property
    def box(self):
        """Get the box used in the calculation.
        """
        return self.getBox()

    def getBox(self):
        """Get the box used in the calculation.

        :return: freud Box
        :rtype: :py:class:`freud.box.Box`
        """
        return BoxFromCPP(< box.Box > self.thisptr.getBox())

    @property
    def num_particles(self):
        """Get the number of particles.
        """
        return self.getNP()

    def getNP(self):
        """Get the number of particles.

        :return: :math:`N_{particles}`
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

cdef class LocalQl:
    """
    Compute the local Steinhardt rotationally invariant :math:`Q_l` [Cit4]_
    order parameter for a set of points.

    Implements the local rotationally invariant :math:`Q_l` order parameter
    described by Steinhardt. For a particle i, we calculate the average
    :math:`Q_l` by summing the spherical harmonics between particle :math:`i`
    and its neighbors :math:`j` in a local region:
    :math:`\\overline{Q}_{lm}(i) = \\frac{1}{N_b}
    \\displaystyle\\sum_{j=1}^{N_b} Y_{lm}(\\theta(\\vec{r}_{ij}),
    \\phi(\\vec{r}_{ij}))`

    This is then combined in a rotationally invariant fashion to remove local
    orientational order as follows: :math:`Q_l(i)=\\sqrt{\\frac{4\pi}{2l+1}
    \\displaystyle\\sum_{m=-l}^{l} |\\overline{Q}_{lm}|^2 }`

    For more details see PJ Steinhardt (1983) (DOI: 10.1103/PhysRevB.28.784)

    Added first/second shell combined average :math:`Q_l` order parameter for
    a set of points:

    * Variation of the Steinhardt :math:`Q_l` order parameter
    * For a particle i, we calculate the average :math:`Q_l` by summing the
      spherical harmonics between particle i and its neighbors j and the
      neighbors k of neighbor j in a local region

    .. moduleauthor:: Xiyu Du <xiyudu@umich.edu>
    .. moduleauthor:: Vyas Ramasubramani <vramasub@umich.edu>

    :param box: simulation box
    :param float rmax: Cutoff radius for the local order parameter. Values near
                       first minima of the RDF are recommended
    :param l: Spherical harmonic quantum number l.  Must be a positive number
    :param float rmin: can look at only the second shell or some arbitrary RDF
                       region
    :type box: :py:class:`freud.box.Box`
    :type l: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef order.LocalQl * qlptr
    cdef m_box
    cdef rmax

    def __cinit__(self, box, rmax, l, rmin=0):
        cdef _box.Box l_box
        if type(self) is LocalQl:
            l_box = _box.Box(
                box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(),
                box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
            self.m_box = box
            self.rmax = rmax
            self.qlptr = new order.LocalQl(l_box, rmax, l, rmin)

    def __dealloc__(self):
        if type(self) is LocalQl:
            del self.qlptr
            self.qlptr = NULL

    @property
    def box(self):
        """Get the box used in the calculation.
        """
        return self.getBox()

    @box.setter
    def box(self, value):
        """Reset the simulation box.
        """
        self.setBox(value)

    def getBox(self):
        """Get the box used in the calculation.

        :return: freud Box
        :rtype: :py:class:`freud.box.Box`
        """
        return BoxFromCPP(< box.Box > self.qlptr.getBox())

    def setBox(self, box):
        """Reset the simulation box.

        :param box: simulation box
        :type box: :py:class:`freud.box.Box`
        """
        cdef _box.Box l_box = _box.Box(
                box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(),
                box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.qlptr.setBox(l_box)

    @property
    def num_particles(self):
        """Get the number of particles.
        """
        return self.getNP()

    def getNP(self):
        """Get the number of particles.

        :return: :math:`N_{particles}`
        :rtype: unsigned int
        """
        cdef unsigned int np = self.qlptr.getNP()
        return np

    @property
    def Ql(self):
        """Get a reference to the last computed :math:`Q_l` for each particle.
        Returns NaN instead of :math:`Q_l` for particles with no neighbors.
        """
        return self.getQl()

    def getQl(self):
        """Get a reference to the last computed :math:`Q_l` for each particle.
        Returns NaN instead of :math:`Q_l` for particles with no neighbors.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float * Ql = self.qlptr.getQl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.qlptr.getNP()
        cdef np.ndarray[float, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_FLOAT32, < void*>Ql)
        return result

    @property
    def ave_Ql(self):
        """Get a reference to the last computed :math:`Q_l` for each particle.
        Returns NaN instead of :math:`Q_l` for particles with no neighbors.
        """
        return self.getAveQl()

    def getAveQl(self):
        """Get a reference to the last computed :math:`Q_l` for each particle.
        Returns NaN instead of :math:`Q_l` for particles with no neighbors.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float * Ql = self.qlptr.getAveQl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.qlptr.getNP()
        cdef np.ndarray[float, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_FLOAT32, < void*>Ql)
        return result

    @property
    def norm_Ql(self):
        """Get a reference to the last computed :math:`Q_l` for each particle.
        Returns NaN instead of :math:`Q_l` for particles with no neighbors.
        """
        return self.getQlNorm()

    def getQlNorm(self):
        """Get a reference to the last computed :math:`Q_l` for each particle.
        Returns NaN instead of :math:`Q_l` for particles with no neighbors.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float * Ql = self.qlptr.getQlNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.qlptr.getNP()
        cdef np.ndarray[float, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                            1, nbins, np.NPY_FLOAT32, < void*>Ql)
        return result

    @property
    def ave_norm_Ql(self):
        """Get a reference to the last computed :math:`Q_l` for each particle.
        Returns NaN instead of :math:`Q_l` for particles with no neighbors.
        """
        return self.getQlAveNorm()

    def getQlAveNorm(self):
        """Get a reference to the last computed :math:`Q_l` for each particle.
        Returns NaN instead of :math:`Q_l` for particles with no neighbors.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float * Ql = self.qlptr.getQlAveNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.qlptr.getNP()
        cdef np.ndarray[float, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_FLOAT32, < void*>Ql)
        return result

    def compute(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3 \\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        points = freud.common.convert_array(
                points, 2, dtype=np.float32, contiguous=True,
                dim_message="points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')
        cdef np.ndarray[float, ndim = 2] l_points = points
        cdef unsigned int nP = <unsigned int > points.shape[0]

        defaulted_nlist = make_default_nlist(
            self.m_box, points, points, self.rmax, nlist, True)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        cdef locality.NeighborList * nlist_ptr = nlist_.get_ptr()

        self.qlptr.compute(nlist_ptr, < vec3[float]*>l_points.data, nP)
        return self

    def computeAve(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3 \\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        points = freud.common.convert_array(
                points, 2, dtype=np.float32, contiguous=True,
                dim_message="points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef np.ndarray[float, ndim = 2] l_points = points
        cdef unsigned int nP = <unsigned int > points.shape[0]

        defaulted_nlist = make_default_nlist(
            self.m_box, points, points, self.rmax, nlist, True)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        cdef locality.NeighborList * nlist_ptr = nlist_.get_ptr()

        self.qlptr.compute(nlist_ptr, < vec3[float]*>l_points.data, nP)
        self.qlptr.computeAve(nlist_ptr, < vec3[float]*>l_points.data, nP)
        return self

    def computeNorm(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3 \\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        points = freud.common.convert_array(
                points, 2, dtype=np.float32, contiguous=True,
                dim_message="points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef np.ndarray[float, ndim = 2] l_points = points
        cdef unsigned int nP = <unsigned int > points.shape[0]

        defaulted_nlist = make_default_nlist(
            self.m_box, points, points, self.rmax, nlist, True)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        cdef locality.NeighborList * nlist_ptr = nlist_.get_ptr()

        self.qlptr.compute(nlist_ptr, < vec3[float]*>l_points.data, nP)
        self.qlptr.computeNorm( < vec3[float]*>l_points.data, nP)
        return self

    def computeAveNorm(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3 \\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        points = freud.common.convert_array(
                points, 2, dtype=np.float32, contiguous=True,
                dim_message="points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef np.ndarray[float, ndim = 2] l_points = points
        cdef unsigned int nP = <unsigned int > points.shape[0]

        defaulted_nlist = make_default_nlist(
            self.m_box, points, points, self.rmax, nlist, True)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        cdef locality.NeighborList * nlist_ptr = nlist_.get_ptr()

        self.qlptr.compute(nlist_ptr, < vec3[float]*>l_points.data, nP)
        self.qlptr.computeAve(nlist_ptr, < vec3[float]*>l_points.data, nP)
        self.qlptr.computeAveNorm( < vec3[float]*>l_points.data, nP)
        return self

cdef class LocalQlNear(LocalQl):
    """
    Compute the local Steinhardt rotationally invariant :math:`Q_l` order
    parameter [Cit4]_ for a set of points.

    Implements the local rotationally invariant :math:`Q_l` order parameter
    described by Steinhardt. For a particle i, we calculate the average
    :math:`Q_l` by summing the spherical harmonics between particle :math:`i`
    and its neighbors :math:`j` in a local region:
    :math:`\\overline{Q}_{lm}(i) = \\frac{1}{N_b}
    \\displaystyle\\sum_{j=1}^{N_b} Y_{lm}(\\theta(\\vec{r}_{ij}),
    \\phi(\\vec{r}_{ij}))`

    This is then combined in a rotationally invariant fashion to remove local
    orientational order as follows: :math:`Q_l(i)=\\sqrt{\\frac{4\pi}{2l+1}
    \\displaystyle\\sum_{m=-l}^{l} |\\overline{Q}_{lm}|^2 }`

    For more details see PJ Steinhardt (1983) (DOI: 10.1103/PhysRevB.28.784)

    Added first/second shell combined average :math:`Q_l` order parameter for
    a set of points:

    * Variation of the Steinhardt :math:`Q_l` order parameter
    * For a particle i, we calculate the average :math:`Q_l` by summing the
      spherical harmonics between particle i and its neighbors j and the
      neighbors k of neighbor j in a local region

    .. moduleauthor:: Xiyu Du <xiyudu@umich.edu>
    .. moduleauthor:: Vyas Ramasubramani <vramasub@umich.edu>

    :param box: simulation box
    :param float rmax: Cutoff radius for the local order parameter. Values near
                       first minima of the RDF are recommended
    :param l: Spherical harmonic quantum number l.  Must be a positive number
    :param kn: number of nearest neighbors. must be a positive integer
    :type box: :py:class:`freud.box.Box`
    :type l: unsigned int
    :type kn: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef num_neigh

    def __cinit__(self, box, rmax, l, kn=12):
        # Note that we cannot leverage super here because the
        # type conditional in the parent will prevent it.
        # Unfortunately, this is necessary for proper memory
        # management in this inheritance structure.
        cdef _box.Box l_box
        if type(self) == LocalQlNear:
            l_box = _box.Box(
                    box.getLx(), box.getLy(), box.getLz(),
                    box.getTiltFactorXY(), box.getTiltFactorXZ(),
                    box.getTiltFactorYZ(), box.is2D())
            self.qlptr = new order.LocalQl(l_box, rmax, l, 0)
            self.m_box = box
            self.rmax = rmax
            self.num_neigh = kn

    def __dealloc__(self):
        if type(self) == LocalQlNear:
            del self.qlptr
            self.qlptr = NULL

    def computeAve(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        defaulted_nlist = make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        return super(LocalQlNear, self).computeAve(points, nlist_)

    def computeNorm(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        defaulted_nlist = make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        return super(LocalQlNear, self).computeNorm(points, nlist_)

    def computeAveNorm(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                        shape= :math:`\\left(N_{particles}, 3\\right)`,
                        dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        defaulted_nlist = make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        return super(LocalQlNear, self).computeAveNorm(points, nlist_)

cdef class LocalWl(LocalQl):
    """
    Compute the local Steinhardt rotationally invariant :math:`W_l` order
    parameter [Cit4]_ for a set of points.

    Implements the local rotationally invariant :math:`W_l` order parameter
    described by Steinhardt that can aid in distinguishing  between FCC, HCP,
    and BCC.

    For more details see PJ Steinhardt (1983) (DOI: 10.1103/PhysRevB.28.784)

    Added first/second shell combined average :math:`W_l` order parameter for
    a set of points:

    * Variation of the Steinhardt :math:`W_l` order parameter
    * For a particle i, we calculate the average :math:`W_l` by summing the
      spherical harmonics between particle i and its neighbors j and the
      neighbors k of neighbor j in a local region

    .. moduleauthor:: Xiyu Du <xiyudu@umich.edu>
    .. moduleauthor:: Vyas Ramasubramani <vramasub@umich.edu>

    :param box: simulation box
    :param float rmax: Cutoff radius for the local order parameter. Values near
                       first minima of the RDF are recommended
    :param l: Spherical harmonic quantum number l.  Must be a positive number
    :param float rmin: Lower bound for computing the local order parameter.
                       Allows looking at, for instance, only the second shell,
                       or some other arbitrary rdf region.
    :type box: :py:class:`freud.box.Box`
    :type l: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef order.LocalWl * thisptr

    # List of Ql attributes to remove
    delattrs = ['Ql', 'getQl', 'ave_Ql', 'getAveQl',
                'norm_ql', 'getQlNorm', 'ave_norm_Ql', 'getQlAveNorm']

    def __cinit__(self, box, rmax, l, rmin=0, *args, **kwargs):
        cdef _box.Box l_box
        if type(self) is LocalWl:
            l_box = _box.Box(
                    box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(),
                    box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
            self.thisptr = self.qlptr = new order.LocalWl(l_box, rmax, l, rmin)
            self.m_box = box
            self.rmax = rmax

    def __dealloc__(self):
        if type(self) is LocalWl:
            del self.thisptr
            self.thisptr = NULL

    def __getattribute__(self, name):
        # Remove access to Ql methods from this class, their values may be
        # uninitialized and are not dependable.
        if name in LocalWl.delattrs:
            raise AttributeError(name)
        else:
            return super(LocalWl, self).__getattribute__(name)

    def __dir__(self):
        # Prevent unwanted Ql methods from appearing in dir output
        return sorted(set(dir(self.__class__)) -
                      set(self.__class__.delattrs))

    @property
    def Wl(self):
        """Get a reference to the last computed :math:`W_l` for each particle.
        Returns NaN instead of :math:`W_l` for particles with no neighbors.
        """
        return self.getWl()

    def getWl(self):
        """Get a reference to the last computed :math:`W_l` for each particle.
        Returns NaN instead of :math:`W_l` for particles with no neighbors.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                    shape= :math:`\\left(N_{particles}\\right)`,
                    dtype= :class:`numpy.complex64`
        """
        cdef float complex * Wl = self.thisptr.getWl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.qlptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_COMPLEX64, < void*>Wl)
        return result

    @property
    def ave_Wl(self):
        """Get a reference to the last computed :math:`W_l` for each particle.
        Returns NaN instead of :math:`W_l` for \ particles with no neighbors.
        """
        return self.getAveWl()

    def getAveWl(self):
        """Get a reference to the last computed :math:`W_l` for each particle.
        Returns NaN instead of :math:`W_l` for particles with no neighbors.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float complex * Wl = self.thisptr.getAveWl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.qlptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim= 1
                ] result = np.PyArray_SimpleNewFromData(
                        1, nbins, np.NPY_COMPLEX64, < void*>Wl)
        return result

    @property
    def norm_Wl(self):
        """Get a reference to the last computed :math:`W_l` for each particle.
        Returns NaN instead of :math:`W_l` for particles with no neighbors.
        """
        return self.getWlNorm()

    def getWlNorm(self):
        """Get a reference to the last computed :math:`W_l` for each particle.
        Returns NaN instead of :math:`W_l` for particles with no neighbors.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float complex * Wl = self.thisptr.getWlNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.qlptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_COMPLEX64, < void*>Wl)
        return result

    @property
    def ave_norm_Wl(self):
        """Get a reference to the last computed :math:`W_l` for each particle.
        Returns NaN instead of :math:`W_l` for particles with no neighbors.
        """
        return self.getWlAveNorm()

    def getWlAveNorm(self):
        """Get a reference to the last computed :math:`W_l` for each particle.
        Returns NaN instead of :math:`W_l` for particles with no neighbors.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.float32`
        """
        cdef float complex * Wl = self.thisptr.getAveNormWl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.qlptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                            1, nbins, np.NPY_COMPLEX64, < void*>Wl)
        return result

cdef class LocalWlNear(LocalWl):
    """
    Compute the local Steinhardt rotationally invariant :math:`W_l` order
    parameter [Cit4]_ for a set of points.

    Implements the local rotationally invariant :math:`W_l` order parameter
    described by Steinhardt that can aid in distinguishing between FCC, HCP,
    and BCC.

    For more details see PJ Steinhardt (1983) (DOI: 10.1103/PhysRevB.28.784)

    Added first/second shell combined average :math:`W_l` order parameter for a
    set of points:

    * Variation of the Steinhardt :math:`W_l` order parameter
    * For a particle i, we calculate the average :math:`W_l` by summing the
      spherical harmonics between particle i and its neighbors j and the
      neighbors k of neighbor j in a local region

    .. moduleauthor:: Xiyu Du <xiyudu@umich.edu>
    .. moduleauthor:: Vyas Ramasubramani <vramasub@umich.edu>

    :param box: simulation box
    :param float rmax: Cutoff radius for the local order parameter. Values near
                       first minima of the RDF are recommended
    :param l: Spherical harmonic quantum number l.  Must be a positive number
    :param kn: Number of nearest neighbors. Must be a positive number
    :type box: :py:class:`freud.box.Box`
    :type l: unsigned int
    :type kn: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef num_neigh

    def __cinit__(self, box, rmax, l, kn=12):
        cdef _box.Box l_box
        if type(self) is LocalWlNear:
            l_box = _box.Box(
                    box.getLx(), box.getLy(), box.getLz(),
                    box.getTiltFactorXY(), box.getTiltFactorXZ(),
                    box.getTiltFactorYZ(), box.is2D())
            self.thisptr = self.qlptr = new order.LocalWl(l_box, rmax, l, 0)
            self.m_box = box
            self.rmax = rmax
            self.num_neigh = kn

    def __dealloc__(self):
        del self.thisptr
        self.thisptr = NULL

    def computeAve(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        defaulted_nlist = make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        return super(LocalWlNear, self).computeAve(points, nlist_)

    def computeNorm(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        defaulted_nlist = make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        return super(LocalWlNear, self).computeNorm(points, nlist_)

    def computeAveNorm(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        defaulted_nlist = make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        return super(LocalWlNear, self).computeAveNorm(points, nlist_)

cdef class SolLiq:
    """
    Computes dot products of :math:`Q_{lm}` between particles and uses these
    for clustering.

    .. moduleauthor:: Richmond Newman <newmanrs@umich.edu>

    :param box: simulation box
    :param float rmax: Cutoff radius for the local order parameter. Values near
                       first minima of the RDF are recommended
    :param float Qthreshold: Value of dot product threshold when evaluating
                             :math:`Q_{lm}^*(i) Q_{lm}(j)` to determine if a
                             neighbor pair is a solid-like bond. (For
                             :math:`l=6`, 0.7 generally good for FCC or BCC
                             structures)
    :param Sthreshold: Minimum required number of adjacent solid-link bonds for
                       a particle to be considered solid-like for clustering.
                       (For :math:`l=6`, 6-8 generally good for FCC or BCC
                       structures)
    :param l: Choose spherical harmonic :math:`Q_l`.  Must be positive and
              even.
    :type box: :py:class:`freud.box.Box`
    :type Sthreshold: unsigned int
    :type l: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef order.SolLiq * thisptr
    cdef m_box
    cdef rmax

    def __init__(self, box, rmax, Qthreshold, Sthreshold, l):
        cdef _box.Box l_box = _box.Box(
                box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(),
                box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.SolLiq(l_box, rmax, Qthreshold, Sthreshold, l)
        self.m_box = box
        self.rmax = rmax

    def __dealloc__(self):
        del self.thisptr
        self.thisptr = NULL

    def compute(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        points = freud.common.convert_array(
                points, 2, dtype=np.float32, contiguous=True,
                dim_message="points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef np.ndarray[float, ndim = 2] l_points = points
        cdef unsigned int nP = <unsigned int > points.shape[0]

        defaulted_nlist = make_default_nlist(
            self.m_box, points, points, self.rmax, nlist, True)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        cdef locality.NeighborList * nlist_ptr = nlist_.get_ptr()

        self.thisptr.compute(nlist_ptr, < vec3[float]*>l_points.data, nP)
        return self

    def computeSolLiqVariant(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        points = freud.common.convert_array(
                points, 2, dtype=np.float32, contiguous=True,
                dim_message="points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef np.ndarray[float, ndim = 2] l_points = points
        cdef unsigned int nP = <unsigned int > points.shape[0]

        defaulted_nlist = make_default_nlist(
            self.m_box, points, points, self.rmax, nlist, True)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        cdef locality.NeighborList * nlist_ptr = nlist_.get_ptr()

        self.thisptr.computeSolLiqVariant(
                nlist_ptr, < vec3[float]*>l_points.data, nP)
        return self

    def computeSolLiqNoNorm(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        points = freud.common.convert_array(
                points, 2, dtype=np.float32, contiguous=True,
                dim_message="points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef np.ndarray[float, ndim = 2] l_points = points
        cdef unsigned int nP = <unsigned int > points.shape[0]

        defaulted_nlist = make_default_nlist(
            self.m_box, points, points, self.rmax, nlist, True)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        cdef locality.NeighborList * nlist_ptr = nlist_.get_ptr()

        self.thisptr.computeSolLiqNoNorm(
                nlist_ptr, < vec3[float]*>l_points.data, nP)
        return self

    @property
    def box(self):
        """Get the box used in the calculation.
        """
        return self.getBox()

    @box.setter
    def box(self, value):
        """Reset the simulation box.

        :param box: simulation box
        :type box: :py:class:`freud.box.Box`
        """
        self.setBox(value)

    def getBox(self):
        """Get the box used in the calculation.

        :return: freud Box
        :rtype: :py:class:`freud.box.Box`
        """
        return BoxFromCPP(< box.Box > self.thisptr.getBox())

    def setClusteringRadius(self, rcutCluster):
        """Reset the clustering radius.

        :param float rcutCluster: radius for the cluster finding
        """
        self.thisptr.setClusteringRadius(rcutCluster)

    def setBox(self, box):
        """Reset the simulation box.

        :param box: simulation box
        :type box: :py:class:`freud.box.Box`
        """
        cdef _box.Box l_box = _box.Box(
                box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(),
                box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr.setBox(l_box)

    @property
    def largest_cluster_size(self):
        """Returns the largest cluster size. Must call a compute method first.
        """
        return self.getLargestClusterSize()

    def getLargestClusterSize(self):
        """Returns the largest cluster size. Must call a compute method first.

        :return: largest cluster size
        :rtype: unsigned int
        """
        cdef unsigned int clusterSize = self.thisptr.getLargestClusterSize()
        return clusterSize

    @property
    def cluster_sizes(self):
        """Return the sizes of all clusters.
        """
        return self.getClusterSizes()

    def getClusterSizes(self):
        """Return the sizes of all clusters.

        :return: largest cluster size
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{clusters}\\right)`,
                dtype= :class:`numpy.uint32`

        .. todo:: unsure of the best way to pass back...as this doesn't do
                  what I want
        """
        cdef vector[unsigned int] clusterSizes = self.thisptr.getClusterSizes()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.thisptr.getNumClusters()
        cdef np.ndarray[np.uint32_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                            1, nbins, np.NPY_UINT32, < void*> & clusterSizes)
        return result

    @property
    def Ql_mi(self):
        """Get a reference to the last computed :math:`Q_{lmi}` for each
        particle.
        """
        return self.getQlmi()

    def getQlmi(self):
        """Get a reference to the last computed :math:`Q_{lmi}` for each
        particle.

        :return: order parameter
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.complex64`
        """
        cdef float complex * Qlmi = self.thisptr.getQlmi().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_COMPLEX64, < void*>Qlmi)
        return result

    @property
    def clusters(self):
        """Get a reference to the last computed set of solid-like cluster
        indices for each particle.
        """
        return self.getClusters()

    def getClusters(self):
        """Get a reference to the last computed set of solid-like cluster
        indices for each particle.

        :return: clusters
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.uint32`
        """
        cdef unsigned int * clusters = self.thisptr.getClusters().get()
        cdef np.npy_intp nbins[1]
        # this is the correct number
        nbins[0] = <np.npy_intp > self.thisptr.getNP()
        cdef np.ndarray[np.uint32_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_UINT32, < void*>clusters)
        return result

    @property
    def num_connections(self):
        """Get a reference to the number of connections per particle.
        """
        return self.getNumberOfConnections()

    def getNumberOfConnections(self):
        """Get a reference to the number of connections per particle.

        :return: clusters
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{particles}\\right)`,
                dtype= :class:`numpy.uint32`
        """
        cdef unsigned int * connections = \
            self.thisptr.getNumberOfConnections().get()
        cdef np.npy_intp nbins[1]
        # this is the correct number
        nbins[0] = <np.npy_intp > self.thisptr.getNP()
        cdef np.ndarray[np.uint32_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                            1, nbins, np.NPY_UINT32, < void*>connections)
        return result

    @property
    def Ql_dot_ij(self):
        """Get a reference to the number of connections per particle.
        """
        return self.getNumberOfConnections()

    def getQldot_ij(self):
        """Get a reference to the qldot_ij values.

        :return: largest cluster size
        :rtype: :class:`numpy.ndarray`,
                shape= :math:`\\left(N_{clusters}\\right)`,
                dtype= :class:`numpy.complex64`

        .. todo:: figure out the size of this cause apparently its size is just
            its size
        """
        cdef vector[float complex] Qldot = self.thisptr.getQldot_ij()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp > self.thisptr.getNumClusters()
        cdef np.ndarray[np.complex64_t, ndim= 1
                        ] result = np.PyArray_SimpleNewFromData(
                                1, nbins, np.NPY_COMPLEX64, < void*> & Qldot)
        return result

    @property
    def num_particles(self):
        """Get the number of particles.
        """
        return self.getNP()

    def getNP(self):
        """Get the number of particles.

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

cdef class SolLiqNear(SolLiq):
    """
    Computes dot products of :math:`Q_{lm}` between particles and uses these
    for clustering.

    .. moduleauthor:: Richmond Newman <newmanrs@umich.edu>

    :param box: simulation box
    :param float rmax: Cutoff radius for the local order parameter. Values near
                       first minima of the RDF are recommended
    :param float Qthreshold: Value of dot product threshold when evaluating
                             :math:`Q_{lm}^*(i) Q_{lm}(j)` to determine if a
                             neighbor pair is a solid-like bond. (For
                             :math:`l=6`, 0.7 generally good for FCC or BCC
                             structures)
    :param Sthreshold: Minimum required number of adjacent solid-link bonds for
                       a particle to be considered solid-like for clustering.
                       (For :math:`l=6`, 6-8 generally good for FCC or BCC
                       structures)
    :param l: Choose spherical harmonic :math:`Q_l`.  Must be positive and
              even.
    :param kn: Number of nearest neighbors. Must be a positive number
    :type box: :py:class:`freud.box.Box`
    :type Sthreshold: unsigned int
    :type l: unsigned int
    :type kn: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef num_neigh

    def __init__(self, box, rmax, Qthreshold, Sthreshold, l, kn=12):
        cdef _box.Box l_box = _box.Box(
                box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(),
                box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.SolLiq(l_box, rmax, Qthreshold, Sthreshold, l)
        self.m_box = box
        self.rmax = rmax
        self.num_neigh = kn

    def __dealloc__(self):
        del self.thisptr
        self.thisptr = NULL

    def compute(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        defaulted_nlist = make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        return SolLiq.compute(self, points, nlist_)

    def computeSolLiqVariant(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        defaulted_nlist = make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        return SolLiq.computeSolLiqVariant(self, points, nlist_)

    def computeSolLiqNoNorm(self, points, nlist=None):
        """Compute the local rotationally invariant :math:`Q_l` order
        parameter.

        :param points: points to calculate the order parameter
        :param nlist: :py:class:`freud.locality.NeighborList` object to use to
                      find bonds
        :type points: :class:`numpy.ndarray`,
                      shape= :math:`\\left(N_{particles}, 3\\right)`,
                      dtype= :class:`numpy.float32`
        :type nlist: :py:class:`freud.locality.NeighborList`
        """
        defaulted_nlist = make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef NeighborList nlist_ = defaulted_nlist[0]
        return SolLiq.computeSolLiqNoNorm(self, points, nlist_)
