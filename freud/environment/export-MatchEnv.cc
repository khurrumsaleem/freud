// Copyright (c) 2010-2024 The Regents of the University of Michigan
// This file is from the freud project, released under the BSD 3-Clause License.

#include <memory>
#include <nanobind/nanobind.h>
#include <nanobind/ndarray.h>
#include <nanobind/stl/shared_ptr.h> // NOLINT(misc-include-cleaner): used implicitly
#include <nanobind/stl/function.h> // NOLINT(misc-include-cleaner): used implicitly
#include <nanobind/stl/map.h> 
#include <nanobind/stl/vector.h>     // NOLINT(misc-include-cleaner): used implicitly

#include "MatchEnv.h"
#include "Registration.h"


namespace nb = nanobind;

namespace freud { namespace environment {

template<typename T, typename shape>
using nb_array = nanobind::ndarray<T, shape, nanobind::device::cpu, nanobind::c_contig>;

namespace wrap {
void compute_env_motif_match(const std::shared_ptr<EnvironmentMotifMatch>& env_motif_match, 
             std::shared_ptr<locality::NeighborQuery> nq,
             std::shared_ptr<locality::NeighborList> nlist,
             const locality::QueryArgs& qargs,
             const nb_array<float, nanobind::shape<-1, 3>>& motif,
             const unsigned int motif_size,
             const float threshold,
             const bool registration
)
{
    auto* motif_data = reinterpret_cast<vec3<float>*>(motif.data());
    env_motif_match->compute(nq, nlist, qargs, motif_data, motif_size, threshold, registration);
}

void compute_env_rmsd_min(const std::shared_ptr<EnvironmentRMSDMinimizer>& env_rmsd_min, 
             std::shared_ptr<locality::NeighborQuery> nq,
             std::shared_ptr<locality::NeighborList> nlist,
             const locality::QueryArgs& qargs,
             const nb_array<float, nanobind::shape<-1, 3>>& motif,
             const unsigned int motif_size,
             const float threshold,
             const bool registration
)
{
    auto* motif_data = reinterpret_cast<vec3<float>*>(motif.data());
    // TODO: where should threshold go?
    env_rmsd_min->compute(nq, nlist, qargs, motif_data, motif_size, registration);
}

std::map<unsigned int, unsigned int> compute_minimize_RMSD(
    const box::Box& box,
    const nb_array<float, nanobind::shape<-1, 3>>& refPoints1,
    nb_array<float, nanobind::shape<-1, 3>>& refPoints2,
    unsigned int numRef,
    float& min_rmsd,
    bool registration)
{
    auto* refPoints1_data = reinterpret_cast<vec3<float>*>(refPoints1.data());
    auto* refPoints2_data = reinterpret_cast<vec3<float>*>(refPoints2.data());
    return minimizeRMSD(box, refPoints1_data, refPoints2_data, numRef, min_rmsd, registration);
}

std::map<unsigned int, unsigned int> compute_is_similar(
    const box::Box& box,
    const nb_array<float, nanobind::shape<-1, 3>>& refPoints1,
    nb_array<float, nanobind::shape<-1, 3>>& refPoints2,
    unsigned int numRef,
    float threshold_sq,
    bool registration)
{
    auto* refPoints1_data = reinterpret_cast<vec3<float>*>(refPoints1.data());
    auto* refPoints2_data = reinterpret_cast<vec3<float>*>(refPoints2.data());
    return isSimilar(box, refPoints1_data, refPoints2_data, numRef, threshold_sq, registration);
}

};

namespace detail {

void export_MatchEnv(nb::module_& module)
{
    module.def("minimizeRMSD", &wrap::compute_minimize_RMSD);
    
    module.def("isSimilar", &wrap::compute_is_similar);

    nb::class_<MatchEnv>(module, "MatchEnv")
        .def(nb::init<>())
        .def("getPointEnvironments", &MatchEnv::getPointEnvironments);

    nb::class_<EnvironmentCluster>(module, "EnvironmentCluster")
        .def(nb::init<>())
        .def("compute", &EnvironmentCluster::compute)
        // .def("getClusters", &EnvironmentCluster::getClusterIdx) // TODO: should be there
        .def("getClusterEnvironments", &EnvironmentCluster::getClusterEnvironments)
        .def("getNumClusters", &EnvironmentCluster::getNumClusters);

    nb::class_<EnvironmentMotifMatch>(module, "EnvironmentMotifMatch")
        .def(nb::init<>())
        .def("compute", &wrap::compute_env_motif_match, nb::arg("nq"), nb::arg("nlist"), nb::arg("qargs"), nb::arg("motif"), nb::arg("motif_size"), nb::arg("threshold"), nb::arg("registration"))
        .def("getMatches", &EnvironmentMotifMatch::getMatches);

    nb::class_<EnvironmentRMSDMinimizer>(module, "EnvironmentRMSDMinimizer")
        .def(nb::init<>())
        .def("compute", &wrap::compute_env_rmsd_min, nb::arg("nq"), nb::arg("nlist"), nb::arg("qargs"), nb::arg("motif"), nb::arg("motif_size"), nb::arg("threshold"), nb::arg("registration"))
        .def("getRMSDs", &EnvironmentRMSDMinimizer::getRMSDs);

}

}; }; // namespace detail
}; // namespace freud::locality
