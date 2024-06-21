// Copyright (c) 2010-2024 The Regents of the University of Michigan
// This file is from the freud project, released under the BSD 3-Clause License.

#ifndef EXPORT_PERIODIC_BUFFER_H
#define EXPORT_PERIODIC_BUFFER_H

#include "PeriodicBuffer.h"

#include <nanobind/ndarray.h>
namespace nb = nanobind;

namespace freud { namespace locality {

template<typename T, typename shape = nb::shape<-1, 3>>
using nb_array = nb::ndarray<T, shape, nb::device::cpu, nb::c_contig>;

nb::ndarray<nb::numpy, float, nb::shape<-1, 3>> getBufferPointsPython(PeriodicBuffer pbuf)
{
    const auto& bufferPoints = pbuf.getBufferPoints();
    return nb::ndarray<nb::numpy, float, nb::shape<-1, 3>>((void*) bufferPoints.data(),
                                                           {bufferPoints.size(), 3}, nb::handle());
}

nb::ndarray<nb::numpy, unsigned int, nb::ndim<1>> getBufferIdsPython(PeriodicBuffer pbuf)
{
    const auto& bufferIds = pbuf.getBufferIds();
    return nb::ndarray<nb::numpy, unsigned int, nb::ndim<1>>((void*) bufferIds.data(), {bufferIds.size()},
                                                             nb::handle());
}

namespace detail {
void export_PeriodicBuffer(nb::module_& m)
{
    nb::class_<PeriodicBuffer>(m, "PeriodicBuffer")
        .def(nb::init<>())
        .def("compute", &PeriodicBuffer::compute)
        .def("getBufferPoints", &getBufferPointsPython)
        //                nb::rv_policy::reference_internal)
        .def("getBufferIds", &getBufferIdsPython);
    //                nb::rv_policy::reference_internal)
};
}; // namespace detail

}; }; // namespace freud::locality

#endif
