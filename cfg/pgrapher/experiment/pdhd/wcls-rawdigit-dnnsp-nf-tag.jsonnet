// This is a main entry point to configure a WC/LS job that applies
// noise filtering and signal processing to existing RawDigits.  The
// FHiCL is expected to provide the following parameters as attributes
// in the "params" structure.
//
// epoch: the hardware noise fix expoch: "before", "after", "dynamic" or "perfect"
// reality: whether we are running on "data" or "sim"ulation.
// raw_input_label: the art::Event inputTag for the input RawDigit
//
// see the .fcl of the same name for an example
//
// Manual testing, eg:
//
// jsonnet -V reality=data -V epoch=dynamic -V raw_input_label=daq \\
//         -V signal_output_form=sparse \\
//         -J cfg cfg/pgrapher/experiment/uboone/wcls-nf-sp.jsonnet
//
// jsonnet -V reality=sim -V epoch=perfect -V raw_input_label=daq \\
//         -V signal_output_form=sparse \\
//         -J cfg cfg/pgrapher/experiment/uboone/wcls-nf-sp.jsonnet


// local epoch = std.extVar('epoch');  // eg "dynamic", "after", "before", "perfect"
local reality = std.extVar('reality');
local sigoutform = std.extVar('signal_output_form');  // eg "sparse" or "dense"
local save_tradsp = true;

local wc = import 'wirecell.jsonnet';
local g = import 'pgrapher/common/pgraph.jsonnet'; // FIXME: use system-wide pgraph.jsonnet

local raw_input_label = std.extVar('raw_input_label');  // eg "daq"


local data_params = import 'pgrapher/experiment/pdhd/params.jsonnet';
local simu_params = import 'pgrapher/experiment/pdhd/simparams.jsonnet';
local base = if reality == 'data' then data_params else simu_params;
local params = base {
    daq: super.daq {
      tick: 1.0/std.extVar('clock_speed') * wc.us,
    },
};

local tools_maker = import 'pgrapher/common/tools.jsonnet';
local tools = tools_maker(params);

local wcls_maker = import 'pgrapher/ui/wcls/nodes.jsonnet';
local wcls = wcls_maker(params, tools);

//local nf_maker = import "pgrapher/experiment/pdsp/nf.jsonnet";
//local chndb_maker = import "pgrapher/experiment/pdsp/chndb.jsonnet";

local sp_maker = import 'pgrapher/experiment/pdhd/sp.jsonnet';

//local chndbm = chndb_maker(params, tools);
//local chndb = if epoch == "dynamic" then chndbm.wcls_multi(name="") else chndbm.wct(epoch);


// Collect the WC/LS input converters for use below.  Make sure the
// "name" argument matches what is used in the FHiCL that loads this
// file.  In particular if there is no ":" in the inputer then name
// must be the emtpy string.
local wcls_input = {
  adc_digits: g.pnode({
    type: 'wclsRawFrameSource',
    name: '',
    data: {
      art_tag: raw_input_label,
      frame_tags: ['orig'],  // this is a WCT designator
      //nticks: params.daq.nticks,
      // nticks: nsample,
      tick: params.daq.tick,
    },
  }, nin=0, nout=1),

};

// Collect all the wc/ls output converters for use below.  Note the
// "name" MUST match what is used in theh "outputers" parameter in the
// FHiCL that loads this file.
local mega_anode = {
  type: 'MegaAnodePlane',
  name: 'meganodes',
  data: {
    anodes_tn: [wc.tn(anode) for anode in tools.anodes],
  },
};
local wcls_output = {
  // The noise filtered "ADC" values.  These are truncated for
  // art::Event but left as floats for the WCT SP.  Note, the tag
  // "raw" is somewhat historical as the output is not equivalent to
  // "raw data".
  nf_digits: g.pnode({
    type: 'wclsFrameSaver',
    name: 'nfsaver',
    data: {
      anode: wc.tn(tools.anode),
      digitize: true,  // true means save as RawDigit, else recob::Wire
      frame_tags: ['raw'],
      //nticks: params.daq.nticks,
      // nticks: nsample,
      chanmaskmaps: ['bad'],
    },
  }, nin=1, nout=1, uses=[tools.anode]),


  // The output of signal processing.  Note, there are two signal
  // sets each created with its own filter.  The "gauss" one is best
  // for charge reconstruction, the "wiener" is best for S/N
  // separation.  Both are used in downstream WC code.
  sp_signals: g.pnode({
    type: 'wclsFrameSaver',
    name: 'spsaver',
    data: {
      // anode: wc.tn(tools.anode),
      anode: wc.tn(mega_anode),
      digitize: false,  // true means save as RawDigit, else recob::Wire
      frame_tags: ['gauss', 'wiener'],
      frame_scale: [0.001, 0.001],
      //nticks: params.daq.nticks,
      // nticks: nsample,
      chanmaskmaps: [],
      summary_tags: ['wiener'],  // retagger makes this tag
      summary_suffix: "",
      //  just one threshold value
      summary_operator: { threshold: 'set' },
      nticks: -1,

    },
  }, nin=1, nout=1, uses=[mega_anode]),

  dnn_signals: g.pnode({
    type: 'wclsFrameSaver',
    name: 'dnnsaver',
    data: {
      anode: wc.tn(mega_anode),
      digitize: false,  // true means save as RawDigit, else recob::Wire
      frame_tags: ['dnnsp'],
      frame_scale: [0.001],
      nticks: -1,

    },
  }, nin=1, nout=1, uses=[mega_anode]),
};

// local perfect = import 'chndb-perfect.jsonnet';
local base = import 'pgrapher/experiment/pdhd/chndb-base.jsonnet';
local chndb = [{
  type: 'OmniChannelNoiseDB',
  name: 'ocndbperfect%d' % n,
  // data: perfect(params, tools.anodes[n], tools.field, n),
  data: base(params, tools.anodes[n], tools.field, n){dft:wc.tn(tools.dft)},
  uses: [tools.anodes[n], tools.field, tools.dft],
} for n in std.range(0, std.length(tools.anodes) - 1)];

local nf_maker = import 'pgrapher/experiment/pdhd/nf.jsonnet';
local nf_pipes = [nf_maker(params, tools.anodes[n], chndb[n], n, name='nf%d' % n) for n in std.range(0, std.length(tools.anodes) - 1)];

//// an empty omnibus noise filter
//// for suppressing bad channels stored in the noise db
//local obnf = [
//  g.pnode(
//    {
//      type: 'OmnibusNoiseFilter',
//      name: 'nf%d' % n,
//      data: {
//
//        // This is the number of bins in various filters
//        // nsamples: params.nf.nsamples,
//
//        channel_filters: [],
//        grouped_filters: [],
//        channel_status_filters: [],
//        noisedb: wc.tn(chndb[n]),
//        // intraces: 'orig%d' % n,  // frame tag get all traces
//        intraces: 'orig',  // frame tag get all traces
//        outtraces: 'raw%d' % n,
//      },
//    }, uses=[chndb[n], tools.anodes[n]], nin=1, nout=1
//  )
//  for n in std.range(0, std.length(tools.anodes) - 1)
//];
//local nf_pipes = [g.pipeline([obnf[n]], name='nf%d' % n) for n in std.range(0, std.length(tools.anodes) - 1)];

local sp_override = { // assume all tages sets in base sp.jsonnet
    sparse: sigoutform == 'sparse',
    // sparse: sigoutform == 'dense',
    // wiener_tag: "",
    // gauss_tag: "",
    use_roi_refinement: true,
    use_roi_debug_mode: true,
    save_negtive_charge: false, // no negative charge in gauss
    tight_lf_tag: "",
    // loose_lf_tag: "",
    cleanup_roi_tag: "",
    break_roi_loop1_tag: "",
    break_roi_loop2_tag: "",
    shrink_roi_tag: "",
    extend_roi_tag: "",
    // decon_charge_tag: "",
    use_multi_plane_protection: true,
    do_not_mp_protect_traditional: true, // do_not_mp_protect_traditional to 
                                         // make a clear ref, defualt is false
    mp_tick_resolution: 10,
};


//local sp = sp_maker(params, tools, { sparse: sigoutform == 'sparse' });
local sp = sp_maker(params, tools, sp_override);
local sp_pipes = [sp.make_sigproc(a) for a in tools.anodes];

local chsel_pipes = [
  g.pnode({
    type: 'ChannelSelector',
    name: 'chsel%d' % n,
    data: {
      channels: std.range(2560 * n, 2560 * (n + 1) - 1),
      //tags: ['orig%d' % n], // traces tag
    },
  }, nin=1, nout=1)
  for n in std.range(0, std.length(tools.anodes) - 1)
];

local hio_orig = [g.pnode({
      type: 'HDF5FrameTap',
      name: 'hio_orig%d' % n,
      data: {
        anode: wc.tn(tools.anodes[n]),
        trace_tags: ['orig%d'%n],
        filename: "g4-rec-%d.h5" % n,
        chunk: [0, 0], // ncol, nrow
        gzip: 2,
        high_throughput: true,
      },
    }, nin=1, nout=1),
    for n in std.range(0, std.length(tools.anodes) - 1)
    ];

local hio_sp = [g.pnode({
      type: 'HDF5FrameTap',
      name: 'hio_sp%d' % n,
      data: {
        anode: wc.tn(tools.anodes[n]),
        trace_tags: ['loose_lf%d' % n
        , 'tight_lf%d' % n
        , 'cleanup_roi%d' % n
        , 'break_roi_1st%d' % n
        , 'break_roi_2nd%d' % n
        , 'shrink_roi%d' % n
        , 'extend_roi%d' % n
        , 'mp3_roi%d' % n
        , 'mp2_roi%d' % n
        , 'decon_charge%d' % n
        , 'gauss%d' % n],
        filename: "g4-rec-%d.h5" % n,
        chunk: [0, 0], // ncol, nrow
        gzip: 2,
        high_throughput: true,
      },
    }, nin=1, nout=1),
    for n in std.range(0, std.length(tools.anodes) - 1)
    ];


local hio_dnn = [g.pnode({
      type: 'HDF5FrameTap',
      name: 'hio_dnn%d' % n,
      data: {
        anode: wc.tn(tools.anodes[n]),
        // trace_tags: ['dnn_sp%d' % n],
        trace_tags: ['dnnsp%d' % n],
        filename: "g4-rec-%d.h5" % n,
        chunk: [0, 0], // ncol, nrow
        gzip: 2,
        high_throughput: true,
      },
    }, nin=1, nout=1),
    for n in std.range(0, std.length(tools.anodes) - 1)
    ];


local dnnroi = import 'pgrapher/experiment/pdhd/dnnroi.jsonnet';
local ts = {
    type: "TorchService",
    name: "dnnroi",
    data: {
        // model: "ts-model/unet-cosmic390-newwc-depofluxsplat-pdhd.ts",
        model: "ts-model/CP49_mobilenetv3_rebin10_lr0p1_thr100_U.ts",
        
        device: "cpu", // "gpucpu",
        concurrency: 1,
    },
};

local magoutput = 'protodunehd-data-check.root';
local magnify = import 'pgrapher/experiment/pdhd/magnify-sinks.jsonnet';
local magio = magnify(tools, magoutput);

local nfsp_pipes = [
  g.pipeline([
               chsel_pipes[n],
               magio.orig_pipe[n],
               nf_pipes[n],
               magio.raw_pipe[n],
               sp_pipes[n],
               magio.decon_pipe[n],
               // magio.threshold_pipe[n],
               magio.debug_pipe[n], // use_roi_debug_mode=true in sp.jsonnet
               // hio_sp[n],

               dnnroi(tools.anodes[n], ts, output_scale=1.0, nticks=params.daq.nticks, nchunks=1),
               magio.dnnsp_pipe[n],
               // hio_dnn[n],

               

             ],
             'nfsp_pipe_%d' % n)
  for n in std.range(0, std.length(tools.anodes) - 1)
];

//local f = import 'pgrapher/common/funcs.jsonnet';
local f = import 'pgrapher/experiment/pdhd/funcs.jsonnet';
//local outtags = ['gauss%d' % n for n in std.range(0, std.length(tools.anodes) - 1)];
//local fanpipe = f.fanpipe('FrameFanout', nfsp_pipes, 'FrameFanin', 'sn_mag_nf', outtags);
local fanpipe = f.fanpipe('FrameFanout', nfsp_pipes, 'FrameFanin', 'sn_mag_nf');

local retagger = g.pnode({
  type: 'Retagger',
  name: 'dnnout',
  data: {
    tag_rules: [{
      frame: {'.*': 'dnnretagger',},
      merge: {'dnnsp\\d': 'dnnsp',},
    }],
  },
}, nin=1, nout=1);

// ---- tap right after retagger (pass-through, no graph break) ----
local mag_after_retagger = g.pnode({
  type: 'MagnifySink',
  name: 'mag_after_retagger',
  data: {
    output_filename: magoutput,      // 이미 위에서 'protodunehd-data-check.root'
    root_file_mode: 'UPDATE',
    // retagger가 붙이는 tag를 frames로 지정
    // 네 retagger 설정에서 frame:{'.*':'dnnretagger'} 였으니 보통 이게 맞습니다.
    frames: ['dnnretagger'],
    trace_has_tag: true,             // dnnsp/gauss 등 trace tag 쓰는 체인이면 보통 true
    // mega_anode를 쓰는 saver를 이미 쓰고 있으니 mega_anode로 맞추는 게 안전
    anode: wc.tn(mega_anode),
  },
}, nin=1, nout=1, uses=[mega_anode]);


// local sink = g.pnode({ type: 'DumpFrames' }, nin=1, nout=0);
// local graph = g.pipeline([wcls_input.adc_digits, fanpipe, retagger, wcls_output.dnn_signals, sink]);
local sink = g.pnode({ type: 'DumpFrames', name: 'final_dump' }, nin=1, nout=0);
local graph = g.pipeline([
  wcls_input.adc_digits,
  fanpipe,
  retagger,
  mag_after_retagger,        // <-- 여기!
  wcls_output.dnn_signals,
  sink
]);



// -------- tradsp: preselect (before Fanin) --------
local tradsp_preselect = [
  g.pnode({
    type: 'TagSelector',
    name: 'tradsp_preselect%d' % n,
    data: { tags: ['gauss%d' % n, 'wiener%d' % n] },
  }, nin=1, nout=1)
  for n in std.range(0, std.length(tools.anodes) - 1)
];


// Build an incomplete subgraph ending to be spliced for saving out frames 
local ofanin = g.pnode({ 
      type: 'FrameFanin',
      name:"outfanin",
      data:{
          multiplicity: std.length(tools.anodes),
          tag_rules: [
            {
              frame: {'.*': 'outfanin',},
              trace: {
                ['gauss%d' % n]: ['gauss%d' % n],
                ['wiener%d' % n]: ['wiener%d' % n],
                // ['threshold%d' % n]: ['threshold%d' % n],
              },
            }
            for n in std.range(0, std.length(tools.anodes) - 1)
          ],
      } 
      }, nin=std.length(tools.anodes), nout=1);
local osink = g.pnode({ type: 'DumpFrames', name:"outsink", data:{} }, nin=1, nout=0);
// local outsgr = g.intern(innodes=[ofanin,], centernodes = [osink],
//                       edges=[ g.edge(ofanin, osink) ], name="outsgr");
local outretagger = g.pnode({
  type: 'Retagger',
  name: 'spout',
  data: {
    tag_rules: [{
      frame: {'.*': 'spretagger',},
      merge: {
        'gauss\\d': 'gauss',
        'wiener\\d': 'wiener',
        // 'threshold\\d': 'threshold',
      },
    }],
  },
}, nin=1, nout=1);
// local outgr = g.pipeline([ofanin, outretagger, wcls_output.sp_signals, osink]);
// local outgr = g.pipeline([ofanin, outretagger, osink]);
local outgr = g.pipeline([ofanin, outretagger, wcls_output.sp_signals, osink]);

// Connect per-anode frames into tradsp_preselect, then into ofanin inputs.
// NOTE: this uses nfsp_pipes[n] as the source of each anode stream.
local tradsp_edges =
  // nfsp_pipes[n] output -> tradsp_preselect[n]
  [ g.edge(nfsp_pipes[n], tradsp_preselect[n], 0, 0)
    for n in std.range(0, std.length(tools.anodes) - 1)
  ]
  +
  // tradsp_preselect[n] -> ofanin input port n
  [ g.edge(tradsp_preselect[n], ofanin, 0, n)
    for n in std.range(0, std.length(tools.anodes) - 1)
  ];

// Final edges = main + tradsp saver subgraph + explicit connections

local all_edges = g.edges(graph) + g.edges(outgr) + tradsp_edges;

local app = {
  type: 'Pgrapher',
  data: { edges: all_edges },
};

// Finally, the configuration sequence
g.uses(graph)
+ g.uses(outgr)
+ [ u
    for n in std.range(0, std.length(tools.anodes) - 1)
    for u in g.uses(tradsp_preselect[n])
  ]
+ [app]
