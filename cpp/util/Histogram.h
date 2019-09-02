#ifndef HISTOGRAM_H
#define HISTOGRAM_H

#include <vector>
#include <memory>
#include "ManagedArray.h"
#ifdef __SSE2__
#include <emmintrin.h>
#endif
#include <sstream>

namespace freud { namespace util {

// Class defining an axis of an array (used in histogram).
// T is the data type of the axis
class Axis
{
public:
    Axis() : m_nbins(0) {}

    // How many bins are there in this axis?
    size_t size() const
    {
        return m_nbins;
    }

    // What bin is the value in.
    virtual size_t getBin(const float &value) const = 0;

protected:
    size_t m_nbins; //!< Number of bins
};

// A regularly spaced axis
class RegularAxis : public Axis
{
public:
    RegularAxis(size_t nbins, float min, float max) : Axis(), m_min(min), m_max(max)
    {
        this->m_nbins = nbins;
        m_dr = (max-min)/nbins;
        float cur_location = min + m_dr/2;
        for (unsigned int i = 0; i < nbins; i++)
        {
            m_bins.push_back(cur_location);
            cur_location += m_dr;
        }
    }

    virtual size_t getBin(const float &value) const
    {
        float val = (value - m_min)/m_dr;
        // fast float to int conversion with truncation
#ifdef __SSE2__
        unsigned int bin = _mm_cvtt_ss2si(_mm_load_ss(&val));
#else
        unsigned int bin = (unsigned int)(val);
#endif
        // There may be a case where rsq < rmaxsq but
        // (r - m_rmin) * dr_inv rounds up to m_nbins.
        // This additional check prevents a seg fault.
        if (bin == m_nbins)
        {
            --bin;
        }
        return bin;
    }

protected:
    std::vector<float> m_bins;   //!< Bin locations.
    float m_min; //!< Lowest value allowed.
    float m_max; //!< Highest value allowed.
    float m_dr; //!< Gap between bins
};

class Histogram
{
public:
    typedef std::vector<std::shared_ptr<Axis> > Axes;
    typedef Axes::const_iterator AxisIterator;

    //! Default constructor
    Histogram() {}

    //! Constructor
    Histogram(std::vector<std::shared_ptr<Axis>> axes) : m_axes(axes)
    {
        std::vector<unsigned int> sizes;
        for (AxisIterator it = m_axes.begin(); it != m_axes.end(); it++)
            sizes.push_back((*it)->size());
        m_bin_counts = ManagedArray<unsigned int>(sizes);
    }

    //! Destructor
    ~Histogram() {};

    //! Implementation of variadic indexing function.
    template <typename ... Floats>
    void operator()(Floats ... values)
    {
        std::vector<float> value_vector = getValueVector(values ...);
        size_t bin = getBin(value_vector);
        m_bin_counts.get()[bin]++; // Will want to replace this with custom accumulation at some point.
    }

    size_t getBin(std::vector<float> values)
    {
        if (values.size() != m_axes.size())
        {
            std::ostringstream msg;
            msg << "This Histogram is " << m_axes.size() << "-dimensional, but only " << values.size() << " values were provided in getBin" << std::endl;
            throw std::invalid_argument(msg.str());
        }
        // First bin the values along each axis.
        std::vector<unsigned int> ax_bins;
        for (unsigned int ax_idx = 0; ax_idx < m_axes.size(); ax_idx++)
        {
            ax_bins.push_back(m_axes[ax_idx]->getBin(values[ax_idx]));
        }

        return m_bin_counts.getIndex(ax_bins);
    }

    //! Getter to expose the histogram to Python.
    /*! Like the ManagedArray's get function, this method is only part of the
     *  public API to support the Python API of freud. It should never be used
     *  in C++ code using the Histogram class.
     */
    const ManagedArray<unsigned int> &getBinCounts()
    {
        return m_bin_counts;
    }

    //! Reset the histogram.
    void reset()
    {
        m_bin_counts.reset();
    }

    ManagedArray<unsigned int> m_bin_counts; //!< Counts for each bin

protected:
    std::vector<std::shared_ptr<Axis > > m_axes; //!< The axes.

    std::vector<float> getValueVector(float value)
    {
        return {value};
    }

    template <typename ... Floats>
    std::vector<float> getValueVector(float value, Floats ... values)
    {
        std::vector<float> tmp = getValueVector(values...);
        tmp.insert(tmp.begin(), value);
        return tmp;
    }
};

}; }; // namespace freud::util

#endif
