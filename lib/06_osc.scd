(
var sourceDefaults;

"[AKM] creating OSC I/O...".postln;

sourceDefaults = [0.0, 0.0, 1.7, 3.0, 1.0, 1.0, 0.2];

~sourceIds.do({ |sourceId|
	~controlBussesInputs[sourceId.asSymbol].setn(sourceDefaults);
});
// Group EQ/filter/system buses are seeded in 02_buses.scd (optionally from
// `state` in server.json). Don't overwrite them here.

// ---------------------------------------------------------------------------
// v3 OSC API surface (SC -> agent -> UI)
//
// Outbound channels (all prefixed `/akm/server/`):
//   * /state/sources      - 20 Hz, only emitted when at least one source's
//                           bus differs from the last broadcast. Payload is
//                           a flat float array repeating
//                           [sourceIdx, x, y, z, r, A, dl, rm] per changed
//                           source. Empty payload = empty tick = NOT sent.
//   * /state/system       - 20 Hz, only emitted when the system snapshot
//                           differs from the last broadcast. Fixed-length
//                           vector; see `~akmBuildSystemVector` below.
//   * /event/ready        - boot complete, carries first system snapshot.
//   * /event/quit         - emitted from the quit OSCdef before s.quit.
//   * /event/error        - emitted from any handler's catch-all.
//   * /event/state_saved  - reserved for future use (agent currently emits
//                           a WS-level state_saved instead).
//   * /heartbeat, /perf, /meters - unchanged (1 / 3 / 20 Hz).
//
// Inbound `/akm/...` setters no longer send /ack/* responses. The 20 Hz
// /state/* channels reflect bus changes so the UI hydrates from there.
// ---------------------------------------------------------------------------

// Coerce every OSC arg via `.asFloat` and validate finiteness before touching
// the control bus. Without this, an OSC client that sends ints, strings, or
// doubles (some TouchDesigner / Max patches do) can pass non-`f`-tagged args
// through to `/c_setn`, and scsynth will crash on the malformed packet. We
// also clip a few critical params so a divide-by-zero or negative radius
// can't poison the panner SynthDef.
~akmSafeFloat = { |val, fallback=0.0|
	var f;
	f = if(val.isNil) {
		fallback
	} {
		if(val.isKindOf(Number)) {
			val.asFloat
		} {
			val.asString.asFloat
		}
	};
	if(f.isNaN or: { f.abs == inf }) { fallback } { f }
};

// Emit a v3 event to the agent. Catch-all event helper.
~akmEmitEvent = { |kind, args|
	var path = ("/akm/server/event/" ++ kind).asSymbol;
	if(args.isNil) {
		~oscSendNetAddr.sendMsg(path);
	} {
		~oscSendNetAddr.sendMsg(path, *args);
	};
};

~akmEmitError = { |where, msg|
	"[AKM] handler error in %: %".format(where, msg).warn;
	~akmEmitEvent.value(\error, [where.asString, msg.asString]);
};

~sourceIds.do({ |sourceId|
	var path = ("/akm/source/" ++ sourceId ++ "/params").asSymbol;
	var bus = ~controlBussesInputs[sourceId.asSymbol];
	OSCdef(("akm-src-" ++ sourceId).asSymbol, { |msg|
		try {
			var raw, vals;
			raw = msg.copyRange(1, 7);
			if(raw.size != 7) {
				"[AKM] /akm/source/%/params expected 7 args, got %".format(sourceId, raw.size).warn;
			} {
				vals = [
					~akmSafeFloat.value(raw[0], 0.0),
					~akmSafeFloat.value(raw[1], 0.0),
					~akmSafeFloat.value(raw[2], 1.7),
					~akmSafeFloat.value(raw[3], 3.0).max(0.0001),
					~akmSafeFloat.value(raw[4], 1.0).max(0.01),
					~akmSafeFloat.value(raw[5], 1.0),
					~akmSafeFloat.value(raw[6], 0.0).clip(0.0, 1.0)
				];
				bus.setn(vals);
			};
		} { |error|
			~akmEmitError.value("/akm/source/" ++ sourceId ++ "/params", error.errorString);
		};
	}, path, nil, ~oscReceivePort);
});

// Per speaker gain
~allSpeakers.do({ |sp, idx|
	var speakerId = sp[\id];
	var path = ("/akm/speaker/" ++ speakerId ++ "/gain").asSymbol;
	OSCdef(("akm-spk-" ++ speakerId).asSymbol, { |msg|
		var db = ~akmSafeFloat.value(msg[1], 0.0);
		~controlBusSpeakerGains.setAt(idx, ~akmDbToFactor.value(db));
	}, path, nil, ~oscReceivePort);
});

// Per speaker mute. Bus stores 1.0 for muted, 0.0 for unmuted; outputRouter
// multiplies signal by (1 - mute).
~allSpeakers.do({ |sp, idx|
	var speakerId = sp[\id];
	var path = ("/akm/speaker/" ++ speakerId ++ "/mute").asSymbol;
	OSCdef(("akm-spk-mute-" ++ speakerId).asSymbol, { |msg|
		var muted = ~akmSafeFloat.value(msg[1], 0.0).clip(0.0, 1.0);
		~controlBusSpeakerMutes.setAt(idx, muted);
	}, path, nil, ~oscReceivePort);
});

// Group EQ
[\satellite, \sub_mid, \sub_lf].do({ |role|
	var roleName = role.asString;
	var path = ("/akm/group/" ++ roleName ++ "/eq").asSymbol;
	var bus = ~controlBusGroupEq[role];
	OSCdef(("akm-group-eq-" ++ roleName).asSymbol, { |msg|
		var raw = msg.copyRange(1, ~numEQParameters);
		if(raw.size == ~numEQParameters) {
			var vals = raw.collect({ |v| ~akmSafeFloat.value(v, 0.0) });
			bus.setn(vals);
		};
	}, path, nil, ~oscReceivePort);
});

// Group filters
[\satellite, \sub_mid, \sub_lf].do({ |role|
	var roleName = role.asString;
	var path = ("/akm/group/" ++ roleName ++ "/filter").asSymbol;
	var bus = ~controlBusGroupFilter[role];
	OSCdef(("akm-group-filter-" ++ roleName).asSymbol, { |msg|
		var raw = msg.copyRange(1, 2);
		if(raw.size == 2) {
			// rq is the reciprocal of Q. 0.05 means Q=20, the upper sane
			// bound for a self-stable resonant filter. 10 means Q=0.1, very
			// gentle. .max(0.0001) would allow Q=10000 which self-oscillates
			// and pumps energy into the satellite reverb loop.
			var vals = [
				~akmSafeFloat.value(raw[0], 1000.0).clip(20.0, 20000.0),
				~akmSafeFloat.value(raw[1], 1.0).clip(0.05, 10.0)
			];
			bus.setn(vals);
		};
	}, path, nil, ~oscReceivePort);
});

// Group gain (per role). Stacks on top of per-speaker and system gain.
[\satellite, \sub_mid, \sub_lf].do({ |role, idx|
	var roleName = role.asString;
	var path = ("/akm/group/" ++ roleName ++ "/gain").asSymbol;
	OSCdef(("akm-group-gain-" ++ roleName).asSymbol, { |msg|
		if(msg.size >= 2) {
			var db = ~akmSafeFloat.value(msg[1], 0.0);
			~controlBusGroupGains.setAt(idx, ~akmDbToFactor.value(db));
		};
	}, path, nil, ~oscReceivePort);
});

// Sub-mid reverb control
OSCdef("akm-submid-reverb".asSymbol, { |msg|
	if(msg.size >= 3) {
		var enabled = ~akmSafeFloat.value(msg[1], 0.0).clip(0.0, 1.0);
		var mix = ~akmSafeFloat.value(msg[2], 0.0).clip(0.0, 1.0);
		~controlBusSubMidReverb.setn([enabled, mix]);
	};
}, "/akm/group/sub_mid/reverb", nil, ~oscReceivePort);

// System reverb
OSCdef("akm-system-reverb".asSymbol, { |msg|
	if(msg.size >= 3) {
		var decay = ~akmSafeFloat.value(msg[1], 0.5).clip(0.0, 5.0);
		var feedback = ~akmSafeFloat.value(msg[2], 0.5).clip(0.0, 0.99);
		~controlBusSystemReverb.setn([decay, feedback]);
	};
}, "/akm/system/reverb", nil, ~oscReceivePort);

// System gain
OSCdef("akm-system-gain".asSymbol, { |msg|
	if(msg.size >= 2) {
		var db = ~akmSafeFloat.value(msg[1], 0.0);
		~controlBusSystemGain.set(~akmDbToFactor.value(db));
	};
}, "/akm/system/gain", nil, ~oscReceivePort);

// Quit
OSCdef("akm-server-quit".asSymbol, { |msg|
	~akmEmitEvent.value(\quit, [1]);
	[~heartbeatRoutine, ~stateBroadcastRoutine, ~perfRoutine].do({ |r| r !? { r.stop } });
	// Free all OSCdefs we registered so a future reload in the same sclang
	// process (rare for the agent-managed flow, common in the SC IDE) doesn't
	// end up with duplicated handlers on the same address.
	OSCdef.all.do({ |d| d.free });
	s.quit;
}, "/akm/server/quit", nil, ~oscReceivePort);

// Meters forwarding from SendPeakRMS
OSCdef("akm-meters-forwarder".asSymbol, { |msg|
	var payload = msg.copyRange(3, msg.size - 1);
	~oscSendNetAddr.sendMsg("/akm/server/meters", *payload);
}, "/akm/server/meters/raw", s.addr);

// Heartbeat (liveness ping). Carries an `uptimeSec` payload so the agent can
// keep its uptime counter in sync without a separate routine.
~heartbeatUptimeSec = 0;
~heartbeatRoutine = Routine({
	loop {
		if(s.serverRunning) {
			~heartbeatUptimeSec = ~heartbeatUptimeSec + 1;
			~oscSendNetAddr.sendMsg("/akm/server/heartbeat", ~heartbeatUptimeSec);
		};
		1.0.wait;
	}
}).play(AppClock);

// Performance telemetry. SC's built-in alive thread already polls scsynth
// for `/status.reply` and stashes results into `s.avgCPU`, `s.peakCPU`,
// `s.numSynths`, etc. — we just read those fields and forward a fixed-shape
// `/akm/server/perf` message at ~telemetryPerfHz (default 3 Hz).
~perfBlockSize = s.options.blockSize.asFloat;
"[AKM] perf telemetry @ % Hz, blockSize=%".format(~telemetryPerfHz, ~perfBlockSize).postln;
~perfRoutine = Routine({
	var interval = (1.0 / ~telemetryPerfHz).max(0.1);
	var tickCount = 0;
	loop {
		if(s.serverRunning) {
			var sr = (s.sampleRate ? s.options.sampleRate ? 0).asFloat;
			var avg = (s.avgCPU ? 0.0).asFloat;
			var peak = (s.peakCPU ? 0.0).asFloat;
			var nSynths = (s.numSynths ? 0).asFloat;
			var nGroups = (s.numGroups ? 0).asFloat;
			var nUGens = (s.numUGens ? 0).asFloat;
			var nDefs = (s.numSynthDefs ? 0).asFloat;
			~oscSendNetAddr.sendMsg(
				"/akm/server/perf",
				avg, peak, sr, ~perfBlockSize, nSynths, nGroups, nUGens, nDefs
			);
			if(tickCount == 0) {
				"[AKM] perf first frame: cpu=%/% sr=% nSynths=%".format(
					avg, peak, sr, nSynths
				).postln;
			};
			tickCount = tickCount + 1;
		};
		interval.wait;
	}
}).play(AppClock);

// ---------------------------------------------------------------------------
// 20 Hz delta-driven state broadcaster (replaces the v2 per-source-per-tick
// firehose). Two caches gate transmission so the bus only carries traffic
// that the UI doesn't already have.
// ---------------------------------------------------------------------------

~lastBroadcastSources = IdentityDictionary.new;
~lastBroadcastSystem = nil;

// Convert a linear amp factor back to dB for the snapshot. Clamps to -200 dB
// at the floor so OSC can serialize the value (Inf/NaN would crash some
// receivers).
~akmFactorToDb = { |factor|
	if(factor.isNil or: { factor.isNaN } or: { factor <= 0.0 }) {
		-200.0
	} {
		factor.ampdb.max(-200.0)
	};
};

// Build the fixed-length system snapshot vector. Layout (v3):
//   [0]            schema version (currently 1)
//   [1]            system gain dB
//   [2..4]         group gain dB [satellite, sub_mid, sub_lf]
//   [5..10]        group filter [sat.freq, sat.rq, mid.freq, mid.rq, lf.freq, lf.rq]
//   [11..11+39]    group EQ [sat (13), mid (13), lf (13)]
//   [next..N]      speaker gains dB (numOutputs values)
//   [next..M]      speaker mutes 0/1 (numOutputs values)
//   [M+1..M+2]     system reverb [decay, feedback]
//   [M+3..M+4]     sub-mid reverb [enabled, mix]
~akmBuildSystemVector = {
	var sysGainDb = ~akmFactorToDb.value(~controlBusSystemGain.getSynchronous);
	var groupGainFactors = ~controlBusGroupGains.getnSynchronous(3);
	var groupGainDbs = groupGainFactors.collect({ |f| ~akmFactorToDb.value(f) });
	var groupFilterParts = [\satellite, \sub_mid, \sub_lf].collect({ |role|
		~controlBusGroupFilter[role].getnSynchronous(2)
	}).flatten;
	var groupEqParts = [\satellite, \sub_mid, \sub_lf].collect({ |role|
		~controlBusGroupEq[role].getnSynchronous(~numEQParameters)
	}).flatten;
	var speakerGainFactors = ~controlBusSpeakerGains.getnSynchronous(~numOutputs);
	var speakerGainDbs = speakerGainFactors.collect({ |f| ~akmFactorToDb.value(f) });
	var speakerMutes = ~controlBusSpeakerMutes.getnSynchronous(~numOutputs);
	var systemReverb = ~controlBusSystemReverb.getnSynchronous(2);
	var subMidReverb = ~controlBusSubMidReverb.getnSynchronous(2);

	[1.0, sysGainDb]
		++ groupGainDbs
		++ groupFilterParts
		++ groupEqParts
		++ speakerGainDbs
		++ speakerMutes
		++ systemReverb
		++ subMidReverb;
};

// Compare two flat float arrays with a tiny epsilon. Bus reads round-trip
// through float32 so direct `==` produces nuisance diffs.
~akmArraysClose = { |a, b, eps=1e-5|
	var equal = a.notNil and: { b.notNil and: { a.size == b.size } };
	if(equal) {
		block { |break|
			a.do({ |val, i|
				if((val - b[i]).abs > eps) {
					equal = false;
					break.value;
				};
			});
		};
	};
	equal;
};

~stateBroadcastRoutine = Routine({
	var interval = (1.0 / ~telemetryStateHz).max(0.016);
	loop {
		try {
			var changedSources = [];
			var systemVector;

			~sourceIds.do({ |sourceId, idx|
				var key = sourceId.asSymbol;
				var vals = ~controlBussesInputs[key].getnSynchronous(7);
				var last = ~lastBroadcastSources[key];
				if(~akmArraysClose.value(vals, last).not) {
					changedSources = changedSources ++ [idx.asFloat] ++ vals;
					~lastBroadcastSources[key] = vals.copy;
				};
			});

			if(changedSources.size > 0) {
				~oscSendNetAddr.sendMsg("/akm/server/state/sources", *changedSources);
			};

			systemVector = ~akmBuildSystemVector.value;
			if(~akmArraysClose.value(systemVector, ~lastBroadcastSystem).not) {
				~oscSendNetAddr.sendMsg("/akm/server/state/system", *systemVector);
				~lastBroadcastSystem = systemVector.copy;
			};
		} { |error|
			~akmEmitError.value("state-broadcast", error.errorString);
		};
		interval.wait;
	}
}).play(AppClock);

// Emit a "ready" event carrying the first system snapshot inline. The agent
// uses this address as the authoritative boot-complete signal.
{
	var snapshot = ~akmBuildSystemVector.value;
	~lastBroadcastSystem = snapshot.copy;
	~oscSendNetAddr.sendMsg("/akm/server/event/ready", *snapshot);
}.value;

"[AKM] OSC ready.".postln;
)
