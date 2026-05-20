(
var sourceDefaults;

"[AKM] creating OSC I/O...".postln;

sourceDefaults = [0.0, 0.0, 1.7, 3.0, 1.0, 1.0, 0.2];

~sourceIds.do({ |sourceId|
	~controlBussesInputs[sourceId.asSymbol].setn(sourceDefaults);
});
// Group EQ/filter/system buses are seeded in 02_buses.scd (optionally from
// `state` in server.json). Don't overwrite them here.

~ackPathFor = { |suffix| ("/akm/server/ack" ++ suffix).asSymbol };

// Source params. We coerce every arg via `.asFloat` and validate finiteness
// before touching the control bus. Without this, an OSC client that sends
// ints, strings, or doubles (some TouchDesigner / Max patches do) can pass
// non-`f`-tagged args through to `/c_setn`, and scsynth will crash on the
// malformed packet. We also clip a few critical params so a divide-by-zero
// or negative radius can't poison the panner SynthDef.
~akmSafeFloat = { |val, fallback=0.0|
	var f;
	// Resilient to anything an OSC client might tag — ints, floats, doubles,
	// strings, symbols, even nil. Symbols don't have `.asFloat`, so we route
	// them through `.asString.asFloat` (which returns 0.0 for non-numeric
	// strings instead of erroring out and killing the OSCdef handler).
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

~sourceIds.do({ |sourceId|
	var path = ("/akm/source/" ++ sourceId ++ "/params").asSymbol;
	var ackPath = ~ackPathFor.value("/source/" ++ sourceId ++ "/params");
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
				"[AKM] src % params <- %".format(sourceId, vals).postln;
				bus.setn(vals);
				~oscSendNetAddr.sendMsg(ackPath, *vals);
			};
		} { |error|
			"[AKM] /akm/source/%/params handler error: %".format(
				sourceId, error.errorString
			).warn;
		};
	}, path, nil, ~oscReceivePort);
});

// Per speaker gain
~allSpeakers.do({ |sp, idx|
	var speakerId = sp[\id];
	var path = ("/akm/speaker/" ++ speakerId ++ "/gain").asSymbol;
	var ackPath = ~ackPathFor.value("/speaker/" ++ speakerId ++ "/gain");
	OSCdef(("akm-spk-" ++ speakerId).asSymbol, { |msg|
		var db = ~akmSafeFloat.value(msg[1], 0.0);
		~controlBusSpeakerGains.setAt(idx, ~akmDbToFactor.value(db));
		~oscSendNetAddr.sendMsg(ackPath, db);
	}, path, nil, ~oscReceivePort);
});

// Per speaker mute. Bus stores 1.0 for muted, 0.0 for unmuted; outputRouter
// multiplies signal by (1 - mute).
~allSpeakers.do({ |sp, idx|
	var speakerId = sp[\id];
	var path = ("/akm/speaker/" ++ speakerId ++ "/mute").asSymbol;
	var ackPath = ~ackPathFor.value("/speaker/" ++ speakerId ++ "/mute");
	OSCdef(("akm-spk-mute-" ++ speakerId).asSymbol, { |msg|
		var muted = ~akmSafeFloat.value(msg[1], 0.0).clip(0.0, 1.0);
		~controlBusSpeakerMutes.setAt(idx, muted);
		~oscSendNetAddr.sendMsg(ackPath, muted);
	}, path, nil, ~oscReceivePort);
});

// Group EQ
[\satellite, \sub_mid, \sub_lf].do({ |role|
	var roleName = role.asString;
	var path = ("/akm/group/" ++ roleName ++ "/eq").asSymbol;
	var ackPath = ~ackPathFor.value("/group/" ++ roleName ++ "/eq");
	var bus = ~controlBusGroupEq[role];
	OSCdef(("akm-group-eq-" ++ roleName).asSymbol, { |msg|
		var raw = msg.copyRange(1, ~numEQParameters);
		if(raw.size == ~numEQParameters) {
			var vals = raw.collect({ |v| ~akmSafeFloat.value(v, 0.0) });
			bus.setn(vals);
			~oscSendNetAddr.sendMsg(ackPath, *vals);
		};
	}, path, nil, ~oscReceivePort);
});

// Group filters
[\satellite, \sub_mid, \sub_lf].do({ |role|
	var roleName = role.asString;
	var path = ("/akm/group/" ++ roleName ++ "/filter").asSymbol;
	var ackPath = ~ackPathFor.value("/group/" ++ roleName ++ "/filter");
	var bus = ~controlBusGroupFilter[role];
	OSCdef(("akm-group-filter-" ++ roleName).asSymbol, { |msg|
		var raw = msg.copyRange(1, 2);
		if(raw.size == 2) {
			var vals = [
				~akmSafeFloat.value(raw[0], 1000.0).max(1.0),
				~akmSafeFloat.value(raw[1], 1.0).max(0.0001)
			];
			bus.setn(vals);
			~oscSendNetAddr.sendMsg(ackPath, *vals);
		};
	}, path, nil, ~oscReceivePort);
});

// Group gain (per role). Stacks on top of per-speaker and system gain.
[\satellite, \sub_mid, \sub_lf].do({ |role, idx|
	var roleName = role.asString;
	var path = ("/akm/group/" ++ roleName ++ "/gain").asSymbol;
	var ackPath = ~ackPathFor.value("/group/" ++ roleName ++ "/gain");
	OSCdef(("akm-group-gain-" ++ roleName).asSymbol, { |msg|
		if(msg.size >= 2) {
			var db = ~akmSafeFloat.value(msg[1], 0.0);
			~controlBusGroupGains.setAt(idx, ~akmDbToFactor.value(db));
			~oscSendNetAddr.sendMsg(ackPath, db);
		};
	}, path, nil, ~oscReceivePort);
});

// Sub-mid reverb control
OSCdef("akm-submid-reverb".asSymbol, { |msg|
	if(msg.size >= 3) {
		var enabled = ~akmSafeFloat.value(msg[1], 0.0).clip(0.0, 1.0);
		var mix = ~akmSafeFloat.value(msg[2], 0.0).clip(0.0, 1.0);
		~controlBusSubMidReverb.setn([enabled, mix]);
		~oscSendNetAddr.sendMsg("/akm/server/ack/group/sub_mid/reverb", enabled, mix);
	};
}, "/akm/group/sub_mid/reverb", nil, ~oscReceivePort);

// System reverb
OSCdef("akm-system-reverb".asSymbol, { |msg|
	if(msg.size >= 3) {
		var decay = ~akmSafeFloat.value(msg[1], 0.5).clip(0.0, 5.0);
		var feedback = ~akmSafeFloat.value(msg[2], 0.5).clip(0.0, 0.99);
		~controlBusSystemReverb.setn([decay, feedback]);
		~oscSendNetAddr.sendMsg("/akm/server/ack/system/reverb", decay, feedback);
	};
}, "/akm/system/reverb", nil, ~oscReceivePort);

// System gain
OSCdef("akm-system-gain".asSymbol, { |msg|
	if(msg.size >= 2) {
		var db = ~akmSafeFloat.value(msg[1], 0.0);
		~controlBusSystemGain.set(~akmDbToFactor.value(db));
		~oscSendNetAddr.sendMsg("/akm/server/ack/system/gain", db);
	};
}, "/akm/system/gain", nil, ~oscReceivePort);

// Quit
OSCdef("akm-server-quit".asSymbol, { |msg|
	~oscSendNetAddr.sendMsg("/akm/server/ack/quit", 1);
	if(~heartbeatRoutine.notNil) { ~heartbeatRoutine.stop };
	if(~stateBroadcastRoutine.notNil) { ~stateBroadcastRoutine.stop };
	if(~perfRoutine.notNil) { ~perfRoutine.stop };
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
// `/akm/server/perf` message at ~telemetryPerfHz (default 3 Hz). Going via the
// cached Server fields is more robust than installing our own /status.reply
// listener (the built-in one consumes the message first on the same port).
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
			// Log the first frame so we can confirm the pipe is alive.
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

// Real-time source state broadcast
~stateBroadcastRoutine = Routine({
	var interval = (1.0 / ~telemetryStateHz).max(0.016);
	loop {
		~sourceIds.do({ |sourceId|
			var vals = ~controlBussesInputs[sourceId.asSymbol].getnSynchronous(7);
			~oscSendNetAddr.sendMsg(("/akm/server/state/source/" ++ sourceId).asSymbol, *vals);
		});
		interval.wait;
	}
}).play(AppClock);

"[AKM] OSC ready.".postln;
)
