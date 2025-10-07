// This produces a function to configure DNN-ROI for one APA given
// anode and torch service (ts) objects.
// 
// The prefix is prepended to all internal node names if uniqueness
// beyond anode ID is needed.  The output_scale allows for an ad-hoc
// scaling of dnnroi output.  The U and W planes will go through
// dnnroi while hte W plane will be shunted.  What comes out will be a
// unified frame with frame tag "dnnspN" where "N" is the anode ID.

local wc = import "wirecell.jsonnet";
local pg = import "pgraph.jsonnet";


function (anode, ts, prefix="dnnroi", output_scale=1.0, nticks_tde=6400, nticks_bde=6400, tick_per_slice=10, nchunks=1) 
    local crpid = anode.data.ident;
    local is_tde = crpid >= 4 && crpid <= 7;
    local prename = prefix + std.toString(crpid);
    local intags = ['loose_lf%d'%crpid, 'mp2_roi%d'%crpid,
                     'mp3_roi%d'%crpid];

    local dnnroi_u = if is_tde then pg.pnode({
        type: "DNNROIFinding",
        name: prename+"u",
        data: {
            anode: wc.tn(anode),
            plane: 0,
            intags: intags,
            decon_charge_tag: "decon_charge%d" %crpid,
            outtag: "dnnsp%du"%crpid,
            output_scale: output_scale,
            forward: wc.tn(ts),
            nticks: nticks_tde,
            tick_per_slice: tick_per_slice,
            nchunks: nchunks
        }
    }, nin=1, nout=1, uses=[ts, anode])
    else pg.pnode({
        type: "DNNROIFinding",
        name: prename+"u",
        data: {
            anode: wc.tn(anode),
            plane: 0,
            intags: intags,
            decon_charge_tag: "decon_charge%d" %crpid,
            outtag: "dnnsp%du"%crpid,
            output_scale: output_scale,
            forward: wc.tn(ts),
            nticks: nticks_bde,
            tick_per_slice: tick_per_slice,
            nchunks: nchunks
        }
    }, nin=1, nout=1, uses=[ts, anode]);

    local dnnroi_v = if is_tde then pg.pnode({
        type: "DNNROIFinding",
        name: prename+"v",
        data: {
            anode: wc.tn(anode),
            plane: 1,
            intags: intags,
            decon_charge_tag: "decon_charge%d" %crpid,
            outtag: "dnnsp%dv"%crpid,
            output_scale: output_scale,
            forward: wc.tn(ts),
            nticks: nticks_tde,
            tick_per_slice: tick_per_slice,
            nchunks: nchunks
        }
    }, nin=1, nout=1, uses=[ts, anode])
    else pg.pnode({
        type: "DNNROIFinding",
        name: prename+"v",
        data: {
            anode: wc.tn(anode),
            plane: 1,
            intags: intags,
            decon_charge_tag: "decon_charge%d" %crpid,
            outtag: "dnnsp%dv"%crpid,
            output_scale: output_scale,
            forward: wc.tn(ts),
            nticks: nticks_bde,
            tick_per_slice: tick_per_slice,
            nchunks: nchunks
        }
    }, nin=1, nout=1, uses=[ts, anode]);

    local dnnroi_w = pg.pnode({
        type: "PlaneSelector",
        name: prename+"w",
        data: {
            anode: wc.tn(anode),
            plane: 2,
            tags: ["gauss%d"%crpid],
            tag_rules: [{
                frame: {".*":"DNNROIFinding"},
                trace: {["gauss%d"%crpid]:"dnnsp%dw"%crpid},
            }],
        }
    }, nin=1, nout=1, uses=[anode]);

    local dnnpipes = [dnnroi_u, dnnroi_v, dnnroi_w];
    local dnnfanout = pg.pnode({
        type: "FrameFanout",
        name: prename,
        data: {
            multiplicity: 3
        }
    }, nin=1, nout=3);

    local dnnfanin = pg.pnode({
        type: "FrameFanin",
        name: prename,
        data: {
            multiplicity: 3,
            tag_rules: [{
                frame: {".*": "dnnsp%d" % crpid},
                trace: {".*": "dnnsp%d" % crpid},
            } for plane in ["u", "v", "w"]]
        },
    }, nin=3, nout=1);
    
    local retagger = pg.pnode({
      type: "Retagger",
      name: 'dnnroi%d' % crpid,
      data: {
        // Note: retagger keeps tag_rules an array to be like frame fanin/fanout.
        tag_rules: [{
          // Retagger also handles "frame" and "trace" like fanin/fanout
          // merge separately all traces like gaussN to gauss.
          frame: {
            ".*": "dnnsp%d" % crpid
          },
          merge: {
            ".*": "dnnsp%d" % crpid
          },
        //   merge: {'dnnsp\\d[uvw]' : 'dnnsp%d' %crpid,},
        }],
      },
    }, nin=1, nout=1);

    pg.intern(innodes=[dnnfanout],
              outnodes=[retagger],
              centernodes=dnnpipes+[dnnfanin],
              edges=[pg.edge(dnnfanout, dnnpipes[ind], ind, 0) for ind in [0,1,2]] +
              [pg.edge(dnnpipes[ind], dnnfanin, 0, ind) for ind in [0,1,2]] +
              [pg.edge(dnnfanin, retagger, 0, 0)])

