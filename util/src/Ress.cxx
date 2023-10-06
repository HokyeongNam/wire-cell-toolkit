#include "WireCellUtil/Ress.h"

#include "WireCellUtil/LassoModel.h"

using namespace WireCell;

Ress::vector_t Ress::solve(Ress::matrix_t matrix, Ress::vector_t measured, const Ress::Params& params,
                           Ress::vector_t initial, Ress::vector_t weights)
{
    // Provide a uniform interface to RESS solving models.  RESS
    // *almost* already provides this.

    if (params.model == Ress::lasso) {
        WireCell::LassoModel model(params.lambda, params.max_iter, params.tolerance, params.non_negative);
        if (params.set_init) {
	  model.Setbeta(initial);
	}
        // FIXME: SetData overwrites SetLambdaWeight
        model.SetData(matrix, measured);
        if (weights.size()) {
            model.SetLambdaWeight(weights);
        }
        model.Fit();
        return model.Getbeta();
    }

    if (params.model == Ress::elnet) {
        WireCell::ElasticNetModel model(params.lambda, params.alpha, params.max_iter, params.tolerance,
                                        params.non_negative);
	if (params.set_init) {
	  model.Setbeta(initial);
        }
        model.SetData(matrix, measured);
	if (weights.size()) {
            model.SetLambdaWeight(weights);
        }
        model.Fit();
        return model.Getbeta();
    }

    return Ress::vector_t();
}

