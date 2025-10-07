// This provides some util functions.

local g = import 'pgraph.jsonnet';
local wc = import 'wirecell.jsonnet';

{
    //  Return a list of channel by anode index: 0,1,2,3
    // "AnodePlane:anode110" -> 0
    // "AnodePlane:anode120" -> 1
    // "AnodePlane:anode111" -> 2
    // "AnodePlane:anode121" -> 3

    // local chrng = [ [ std.range(0,475), std.range(952,1427), std.range(1904,2195) ],
    //                 [ std.range(0,475), std.range(952,1427), std.range(2196,2487) ],
    //                 [ std.range(476,951), std.range(1428,1903), std.range(2488,2779) ],
    //                 [ std.range(476,951), std.range(1428,1903), std.range(2780,3071) ]
    //               ],
    // anode_channels :: function(n) {
    //   local nmod = n % 4,
    //   local channels = chrng[nmod][0] + chrng[nmod][1] + chrng[nmod][2],
    //   local nmulti = ( n - nmod ) / 4,
    //   ret: [ x + 3072 * nmulti for x in channels],
    // }.ret,

    anode_channels :: function(n) {
      local crp = (n - n%2)/2,
      local cru0 = std.range(0,475) + std.range(952,1427) + std.range(1904, 2487),
      local cru1 = std.range(476, 951) + std.range(1428, 1903) + std.range(2488, 3071),
      local channels = if n%2 == 0 then cru0 else cru1,
      ret: [x + 3072 * crp for x in channels],
    }.ret,

    // Return the number of split (1 or 2) for an anode
    anode_split(ident):: (ident%100 - ident%10)/10,

    //  Build a depofanout-[signal]-[framesummer]-[pipelines]-fanin graph.
    //  FrameSummer add up the two "split" anodes into one frame.
    //  Each branch of the pipelines operates on the summed signal frame.
    fansummer :: function(fout, sigpipes, summers, actpipes, fin, name="fansummer", outtags=[], tag_rules=[]) {

        local fanoutmult = std.length(sigpipes),
        local faninmult = std.length(actpipes),

        local fanout = g.pnode({
            type: fout,
            name: name,
            data: {
                multiplicity: fanoutmult,
                tag_rules: tag_rules,
            },
        }, nin=1, nout=fanoutmult),


        local fanin = g.pnode({
            type: fin,
            name: name,
            data: {
                multiplicity: faninmult,
                tags: outtags,
            },
        }, nin=faninmult, nout=1),

        local reducer = g.intern(innodes=sigpipes,
                                 outnodes=actpipes,
                                 centernodes=summers,
                                 edges= 
                                 // connecting signal and summer
                                 [g.edge(sigpipes[0], summers[0],0,0)]
                                 + [g.edge(sigpipes[1], summers[0],0,1)]
                                 + [g.edge(sigpipes[2], summers[1],0,0)]
                                 + [g.edge(sigpipes[3], summers[1],0,1)]

                                 + [g.edge(sigpipes[4], summers[2],0,0)]
                                 + [g.edge(sigpipes[5], summers[2],0,1)]
                                 + [g.edge(sigpipes[6], summers[3],0,0)]
                                 + [g.edge(sigpipes[7], summers[3],0,1)]

                                 + [g.edge(sigpipes[8], summers[4],0,0)]
                                 + [g.edge(sigpipes[9], summers[4],0,1)]
                                 + [g.edge(sigpipes[10], summers[5],0,0)]
                                 + [g.edge(sigpipes[11], summers[5],0,1)]

                                 + [g.edge(sigpipes[12], summers[6],0,0)]
                                 + [g.edge(sigpipes[13], summers[6],0,1)]
                                 + [g.edge(sigpipes[14], summers[7],0,0)]
                                 + [g.edge(sigpipes[15], summers[7],0,1)]

                                 // connecting summer and the operator pipelines
                                 + [g.edge(summers[n], actpipes[n]) for n in std.range(0,faninmult-1)],
                                 name=name),

        ret: g.intern(innodes=[fanout],
                      outnodes=[fanin],
                      centernodes=[reducer],
                      edges=
                      [g.edge(fanout, sigpipes[n], n, 0) for n in std.range(0, fanoutmult-1)] +
                      [g.edge(reducer, fanin, n, n) for n in std.range(0, faninmult-1)],
                      name=name),
    }.ret,

  // Build a fanout-[pipelines]-fanin graph.  pipelines is a list of
  // pnode objects, one for each spine of the fan.
  fanpipe:: function(fout, pipelines, fin, name='fanpipe', outtags=[], fout_tag_rules=[], fin_tag_rules=[]) {

    local fanmult = std.length(pipelines),
    local fannums = std.range(0, fanmult - 1),

    local fanout = g.pnode({
      type: fout,
      name: name,
      data: {
        multiplicity: fanmult,
        tag_rules: fout_tag_rules,
      },
    }, nin=1, nout=fanmult),


    local fanin = g.pnode({
      type: fin,
      name: name,
      data: {
        multiplicity: fanmult,
        tag_rules: fin_tag_rules,
        tags: outtags,
      },
    }, nin=fanmult, nout=1),

    ret: g.intern(innodes=[fanout],
                  outnodes=[fanin],
                  centernodes=pipelines,
                  edges=
                  [g.edge(fanout, pipelines[n], n, 0) for n in std.range(0, fanmult - 1)] +
                  [g.edge(pipelines[n], fanin, 0, n) for n in std.range(0, fanmult - 1)],
                  name=name),
  }.ret,

  // The approximated sim+sigproc
  splat:: function(params, tools, anode, name=null) {
    local apaid = anode.data.ident,
    local sufix = if std.type(name) == "null" then apaid else name,
    local bg = g.pnode({
        type:'DepoBagger',
        name: sufix,
        data: {
            gate: [params.sim.ductor.start_time,
                   params.sim.ductor.start_time+params.sim.ductor.readout_time],
        },
    }, nin=1, nout=1),
    local sp = g.pnode({
        type: 'DepoFluxSplat',
        name: sufix,
        data: {
            anode: wc.tn(anode),
            field_response: wc.tn(tools.field), // for speed and origin
            sparse: true,
            // sparse: false,
            tick: params.daq.tick,
            window_start: params.sim.ductor.start_time,
            window_duration: params.sim.ductor.readout_time,
            // reference_time: 1.0 * wc.us, // default
            reference_time: 0.0, // default
            // reference_time: 62.5 * wc.us, // default
            // time_offsets: [-62.5*wc.us, -62.5*wc.us, -62.5*wc.us],
            // reference_time: params.det.response_plane / params.lar.drift_speed, // close to 125
            // Run wirecell-gen morse-* to find these numbers that match the extra
            // spread the sigproc induces.
            "smear_long": [
                2.691862363980221,
                2.6750200122535057,
                2.7137567141154055
            ],
            "smear_tran": [
                0.7377218875719689,
                0.7157764520393882,
                0.13980698710556544
            ]
        },
    }, nin=1, nout=1, uses=[anode, tools.field]),
    local rt = g.pnode({
        type: 'Retagger',
        name: sufix,
        data: {
            // Note: retagger keeps tag_rules an array to be like frame fanin/fanout.
            tag_rules: [{
                // Retagger also handles "frame" and "trace" like fanin/fanout
                // merge separately all traces like gaussN to gauss.
                frame: {
                ".*": "deposplat%d" % apaid
                },
                merge: {
                ".*": "deposplat%d" % apaid
                },
            }],
        },
    }, nin=1, nout=1),
    ret: g.pipeline([bg, sp, rt],"%s-%s" % [bg.name, sp.name]),
  }.ret,



  // Drift Velocity as a function of Electric Field and LAr Temperature
  // adapted from lardataalg/DetectorInfo/DetectorPropertiesStandard.cxx
  // original formula: W. Walkowiak, NIM A 449 (2000) 288-294
  // Efield should have units of kV/cm
  // Temperature should have units of Kelvin
  // return vaule has unit of mm/us
  drift_velocity :: function(efield, temperature) {
  
      local tshift = -87.203 + temperature,
      local xFit = 0.0938163 - 0.0052563 * tshift - 0.0001470 * tshift * tshift,
      local uFit = 5.18406 + 0.01448 * tshift - 0.003497 * tshift * tshift -
                            0.000516 * tshift * tshift * tshift,
  
      // Icarus Parameter Set, use as default
      local P1 = -0.04640, // K^-1
      local P2 = 0.01712,  // K^-1
      local P3= 1.88125,  // (kV/cm)^-1
      local P4 = 0.99408,  // kV/cm
      local P5 = 0.01172,  // (kV/cm)^-P6
      local P6 = 4.20214,
      local T0 = 105.749, // K
  
      // Walkowiak Parameter Set
      local P1W = -0.01481, // K^-1
      local P2W = -0.0075,  // K^-1
      local P3W = 0.141,    // (kV/cm)^-1
      local P4W = 12.4,     // kV/cm
      local P5W = 1.627,    // (kV/cm)^-P6
      local P6W = 0.317,
      local T0W = 90.371, // K
  
      // From Craig Thorne . . . currently not documented
      // smooth transition from linear at small fields to
      //     icarus fit at most fields to Walkowiak at very high fields
      ret: if efield < xFit then
        efield * uFit
      else if efield < 0.619 then
        (P1 * (temperature - T0) + 1) *
                (P3 * efield * std.log(1 + P4 / efield) + P5 * std.pow(efield, P6)) +
              P2 * (temperature - T0)
      else if efield < 0.699 then
        12.5 * (efield - 0.619) *
               ((P1W * (temperature - T0W) + 1) *
                  (P3W * efield * std.log(1 + P4W / efield) + P5W * std.pow(efield, P6W)) +
                P2W * (temperature - T0W)) +
             12.5 * (0.699 - efield) *
               ((P1 * (temperature - T0) + 1) *
                  (P3 * efield * std.log(1 + P4 / efield) + P5 * std.pow(efield, P6)) +
                P2 * (temperature - T0))
      else 
        (P1W * (temperature - T0W) + 1) *
                (P3W * efield * std.log(1 + P4W / efield) + P5W * std.pow(efield, P6W)) +
              P2W * (temperature - T0W),
  
  }.ret,

}
