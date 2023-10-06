/** Hook in boost::units::measurement

    This is an example outside of Boost, proper.  We hook it in
    through this file just to give some firewall.

    Besides arithemtic methods, there are these accessors:

        constexpr value_type value() const
        constexpr value_type uncertainty() const
        constexpr value_type lower_bound() const
        constexpr value_type upper_bound() const

*/
#ifndef WIRECELLUTIL_MEASUREMENT
#define WIRECELLUTIL_MEASUREMENT

#include "WireCellUtil/boost_units_measurement.h"

namespace WireCell::Measurement {

    using float32 = boost::units::measurement<float>;
    using float64 = boost::units::measurement<double>;

}

#endif
