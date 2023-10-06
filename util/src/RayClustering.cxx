#include "WireCellUtil/RayClustering.h"

using namespace WireCell;
using namespace WireCell::RayGrid;

WireCell::RayGrid::blobproj_t WireCell::RayGrid::projection(const blobvec_t& blobs, layer_index_t layer)
{
    blobproj_t ret;
    for (blobref_t blob : blobs) {
        const auto bounds = blob->strips()[layer].bounds;
        for (auto gi = bounds.first; gi != bounds.second; ++gi) {
            if ((int) ret.size() <= gi) {
                ret.resize(gi + 1);
            }
            ret[gi].push_back(blob);
        }
    }
    return ret;
}

WireCell::RayGrid::blobvec_t WireCell::RayGrid::select(const blobproj_t& proj, grid_range_t gr)
{
    if (proj.empty()) {
        return WireCell::RayGrid::blobvec_t();
    }

    blobset_t uniq;
    int nproj = std::min((int) proj.size(), gr.second);
    for (grid_index_t gind = gr.first; gind < nproj; ++gind) {
        const auto& some = proj[gind];
        uniq.insert(some.begin(), some.end());
    }
    return blobvec_t(uniq.begin(), uniq.end());
}

WireCell::RayGrid::blobvec_t WireCell::RayGrid::overlap(const blobref_t& blob, const blobproj_t& proj,
                                                        layer_index_t layer, grid_index_t tolerance, const bool verbose)
{
    const auto& strip = blob->strips()[layer];
    auto lbound = std::max(0,strip.bounds.first-tolerance);
    auto hbound = std::min(proj.size(), (size_t)strip.bounds.second+tolerance);
    if (verbose) {
        std::cout << "bound: {" << lbound << ", " << hbound << "}" << std::endl;
        std::cout << blob->as_string() << std::endl;
    }
    auto blobs = select(proj, {lbound, hbound});
    if (blobs.empty()) {
        return blobs;
    }
    if (layer == 2) {
        return blobs;
    }

    --layer;
    auto newproj = projection(blobs, layer);
    return overlap(blob, newproj, layer, tolerance, verbose);
}

WireCell::RayGrid::blobvec_t WireCell::RayGrid::references(const blobs_t& blobs)
{
    const size_t siz = blobs.size();
    blobvec_t ret(siz);
    for (size_t ind = 0; ind < siz; ++ind) {
        ret[ind] = blobs.begin() + ind;
    }
    return ret;
}

bool WireCell::RayGrid::surrounding(const blobref_t& a, const blobref_t& b)
{
    const auto& astrips = a->strips();
    const auto& bstrips = b->strips();
    const int nlayers = astrips.size();

    int ainb = 0, bina = 0;
    for (int ilayer = 0; ilayer < nlayers; ++ilayer) {
        const auto& astrip = astrips[ilayer];
        const auto& bstrip = bstrips[ilayer];
        const auto& abounds = astrip.bounds;
        const auto& bbounds = bstrip.bounds;
        if (abounds.first <= bbounds.first and bbounds.second <= abounds.second) {
            ++bina;
        }
        if (bbounds.first <= abounds.first and abounds.second <= bbounds.second) {
            ++ainb;
        }
    }
    if (ainb == nlayers or bina == nlayers) {
        return true;
    }
    return false;
}

void WireCell::RayGrid::associate(const blobs_t& one, const blobs_t& two, associator_t func, overlap_t ol)
{
    if (one.empty() or two.empty()) {
        return;
    }
    const size_t nlayers = two[0].strips().size();
    const size_t ilayer = nlayers - 1;
    const auto proj = projection(references(two), ilayer);
    for (blobref_t blob = one.begin(); blob != one.end(); ++blob) {
        auto assoc = ol(blob, proj, ilayer);  // recursive call
        for (blobref_t other : assoc) {
            func(blob, other);
        }
    }
}

/*
for blob in slice[i]:

  other_blobs = slice[i+1];
  for strip in blob.strips:
    other_blobs = overlapping_blobs(other_blobs, strip)

  if other_blobs.empty():
    continue

  mark(blob)
  for other in other_blobs:
    mark(other)
*/
