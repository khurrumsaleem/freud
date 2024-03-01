// Copyright (c) 2010-2023 The Regents of the University of Michigan
// This file is from the freud project, released under the BSD 3-Clause License.

#pragma once

#include <vector>

#include "ManagedArray.h"
#include "Voronoi.h"

/*! \file ContinuousCoordination.h
    \brief Routines for computing local continuous coordination numbers based on Voronoi tesselation.
*/

namespace freud { namespace order {

//! Compute the continuous coordination number(s) at each point.
class ContinuousCoordination
{
public:
    //! Constructor
    ContinuousCoordination(std::vector<float> powers, bool compute_log, bool compute_exp);

    //! Destructor
    ~ContinuousCoordination() = default;

    //! Compute the local continuous coordination number
    void compute(const freud::locality::Voronoi* voronoi);

    //! Get the powers of the continuous coordination number to compute
    const std::vector<float>& getPowers() const
    {
        return m_powers;
    }
    //! Get whether to compute the log continuous coordinatio number
    bool getComputeLog() const
    {
        return m_compute_log;
    }
    //! Get whether to compute the exp continuous coordinatio number
    bool getComputeExp() const
    {
        return m_compute_exp;
    }

    //! Get a reference to the last computed number of neighbors
    const util::ManagedArray<float>& getCoordination() const
    {
        return m_coordination;
    }

    //! Get the number of coordination numbers to compute.
    unsigned int getNumberOfCoordinations() const;

private:
    std::vector<float> m_powers;              //!< The powers to use for CNv
    bool m_compute_log;                       //!< Whether to compute CNlog
    bool m_compute_exp;                       //!< Whether to compute CNexp
    util::ManagedArray<float> m_coordination; //!< number of neighbors array computed
};

}; }; // namespace freud::order
