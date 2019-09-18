// Copyright (c) 2010-2019 The Regents of the University of Michigan
// This file is from the freud project, released under the BSD 3-Clause License.

#ifndef PMFT_H
#define PMFT_H

#include <memory>
#include <ostream>
#include <tbb/tbb.h>

#include "Box.h"
#include "Histogram.h"
#include "HistogramCompute.h"
#include "ManagedArray.h"
#include "VectorMath.h"

/*! \internal
    \file PMFT.h
    \brief Declares base class for all PMFT classes
*/

namespace freud { namespace pmft {

//! Computes the PMFT for a given set of points
/*! The PMFT class is an abstract class providing the basis for all classes calculating PMFTs for specific
 *  dimensional cases. The PMFT class defines some of the key interfaces required for all PMFT classes, such
 *  as the ability to access the underlying PCF and box. Many of the specific methods must be implemented by
 *  subclasses that account for the proper set of dimensions.The required functions are implemented as pure
 *  virtual functions here to enforce this.
 */
class PMFT : public util::HistogramCompute
{
public:
    //! Constructor
    PMFT() : HistogramCompute(), m_r_max(0) {}

    //! Destructor
    virtual ~PMFT() {};

    //! \internal
    //! helper function to reduce the thread specific arrays into one array
    //! Must be implemented by subclasses
    virtual void reducePCF() = 0;

    //! Implementing pure virtual function from parent class.
    virtual void reduce()
    {
        reducePCF();
    }

    float getRMax()
    {
        return m_r_max;
    }

    //! Helper function to precompute axis bin center,
    util::ManagedArray<float> precomputeAxisBinCenter(unsigned int size, float d, float max)
    {
        return precomputeArrayGeneral(size, d, [=](float T, float nextT) { return -max + ((T + nextT) / 2.0); });
    }

    //! Helper function to precompute array with the following logic.
    //! :code:`Func cf` should be some sort of (float)(float, float).
    template<typename Func>
    util::ManagedArray<float> precomputeArrayGeneral(unsigned int size, float d, Func cf)
    {
        util::ManagedArray<float> arr({size});
        for (unsigned int i = 0; i < size; i++)
        {
            float T = float(i) * d ;
            float nextT = float(i + 1) * d;
            arr[i] = cf(T, nextT);
        }
        return arr;
    }

    //! Helper function to reduce three dimensionally with appropriate Jaocobian.
    template<typename JacobFactor>
    void reduce(JacobFactor jf)
    {
        m_pcf_array.prepare(m_histogram.shape());
        m_histogram.reset();

        float inv_num_dens = m_box.getVolume() / (float) m_n_query_points;
        float norm_factor = (float) 1.0 / ((float) m_frame_counter * (float) m_n_points);
        float prefactor = inv_num_dens*norm_factor;

        m_histogram.reduceOverThreadsPerBin(m_local_histograms,
                [this, &prefactor, &jf] (size_t i) {
                m_pcf_array[i] = m_histogram[i] * prefactor * jf(i);
                });
    }

    //! Get a reference to the PCF array
    const util::ManagedArray<float> &getPCF()
    {
        return reduceAndReturn(m_pcf_array);
    }

    //! Get a reference to the bin counts array
    const util::ManagedArray<unsigned int> &getBinCounts()
    {
        return reduceAndReturn(m_histogram.getBinCounts());
    }

protected:
    float m_r_max; //!< r_max used in cell list construction

    util::ManagedArray<float> m_pcf_array;         //!< Array of computed pair correlation function.
};

}; }; // end namespace freud::pmft

#endif // PMFT_H
