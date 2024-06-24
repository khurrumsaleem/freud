// Copyright (c) 2010-2024 The Regents of the University of Michigan
// This file is from the freud project, released under the BSD 3-Clause License.

#ifndef EXPORT_NEIGHBOR_QUERY_H
#define EXPORT_NEIGHBOR_QUERY_H

#include "AABBQuery.h"
#include "LinkCell.h"
#include "NeighborQuery.h"
#include "RawPoints.h"

#include <nanobind/nanobind.h>
#include <nanobind/ndarray.h>
namespace nb = nanobind;

namespace freud { namespace locality {

template<typename T, typename shape>
using nb_array = nanobind::ndarray<T, shape, nanobind::device::cpu, nanobind::c_contig>;

namespace wrap {

std::shared_ptr<NeighborQueryIterator> query(std::shared_ptr<NeighborQuery> nq, nb_array<float, nb::shape<-1, 3>> query_points,
                                             const QueryArgs& qargs)
{
    unsigned int n_query_points = query_points.shape(0);
    const vec3<float>* query_points_data = (vec3<float>*) query_points.data();
    return nq->query(query_points_data, n_query_points, qargs);
}

void AABBQueryConstructor(AABBQuery* nq, const box::Box& box, nb_array<float, nb::shape<-1, 3>> points)
{
    unsigned int n_points = points.shape(0);
    vec3<float>* points_data = (vec3<float>*) points.data();
    new (nq) AABBQuery(box, points_data, n_points);
}

void LinkCellConstructor(LinkCell* nq, const box::Box& box, nb_array<float, nb::shape<-1, 3>> points, float cell_width)
{
    unsigned int n_points = points.shape(0);
    vec3<float>* points_data = (vec3<float>*) points.data();
    new (nq) LinkCell(box, points_data, n_points, cell_width);
}

void RawPointsConstructor(RawPoints* nq, const box::Box& box, nb_array<float, nb::shape<-1, 3>> points)
{
    unsigned int n_points = points.shape(0);
    vec3<float>* points_data = (vec3<float>*) points.data();
    new (nq) RawPoints(box, points_data, n_points);
}

}; // namespace wrap

namespace detail {
void export_NeighborQuery(nb::module_& m)
{
    nb::class_<NeighborQuery>(m, "NeighborQuery")
        .def("query", &wrap::query)
        .def("getBox", &NeighborQuery::getBox);
}

void export_AABBQuery(nb::module_& m)
{
    nb::class_<AABBQuery, NeighborQuery>(m, "AABBQuery").def("__init__", &wrap::AABBQueryConstructor);
}

void export_LinkCell(nb::module_& m)
{
    nb::class_<LinkCell, NeighborQuery>(m, "LinkCell")
        .def("__init__", &wrap::LinkCellConstructor)
        .def("GetCellWidth", &LinkCell::getCellWidth);
}

void export_RawPoints(nb::module_& m)
{
    nb::class_<RawPoints, NeighborQuery>(m, "RawPoints").def("__init__", &wrap::RawPointsConstructor);
}

void export_QueryArgs(nb::module_& m)
{
    nb::enum_<QueryType>(m, "QueryType")
        .value("none", QueryType::none)
        .value("ball", QueryType::ball)
        .value("nearest", QueryType::nearest);
    nb::class_<QueryArgs>(m, "QueryArgs")
        .def(nb::init<>())
        .def_rw("mode", &QueryArgs::mode)
        .def_rw("num_neighbors", &QueryArgs::num_neighbors)
        .def_rw("r_max", &QueryArgs::r_max)
        .def_rw("r_min", &QueryArgs::r_min)
        .def_rw("r_guess", &QueryArgs::r_guess)
        .def_rw("scale", &QueryArgs::scale)
        .def_rw("exclude_ii", &QueryArgs::exclude_ii);
}

void export_NeighborQueryIterator(nb::module_& m)
{
    nb::class_<NeighborQueryIterator>(m, "NeighborQueryIterator")
        .def("next", &NeighborQueryIterator::next)
        .def("toNeighborList", &NeighborQueryIterator::toNeighborList);
}
}; // namespace detail

}; }; // namespace freud::locality

#endif
