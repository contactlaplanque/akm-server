(
var sourceDefaults, eqDefaults;

"[AKM] creating OSC I/O...".postln;

sourceDefaults = [0.0, 0.0, 1.7, 3.0, 1.0, 1.0, 0.2];
eqDefaults = [
	0, 0, 400, 0, 1,
	0, 2000, 0, 1,
	0, 6000, 0, 1,
	0, 12000, 0, 1,
	0, 16000, 0, 1
];

~sourceIds.do({ |sourceId|
	~controlBussesInputs[sourceId.asSymbol].setn(sourceDefaults);
});
~controlBusGroupEq[\satellite].setn(eqDefaults);
~controlBusGroupEq[\sub_mid].setn(eqDefaults);
~controlBusGroupEq[\sub_lf].setn(eqDefaults);

~ackPathFor = { |suffix| ("/akm/server/ack" ++ suffix).asSymbol };

// Source params
~sourceIds.do({ |sourceId|
	var path = ("/akm/source/" ++ sourceId ++ "/params").asSymbol;
	var ackPath = ~ackPathFor.value("/source/" ++ sourceId ++ "/params");
	var bus = ~controlBussesInputs[sourceId.asSymbol];
	OSCdef(("akm-src-" ++ sourceId).asSymbol, { |msg|
		var vals = msg.copyRange(1, 7);
		if(vals.size == 7) {
			bus.setn(vals);
			~oscSendNetAddr.sendMsg(ackPath, *vals);
		};
	}, path, NetAddr(~oscReceiveHost), ~oscReceivePort);
});

// Per speaker gain
~allSpeakers.do({ |sp, idx|
	var speakerId = sp[\id];
	var path = ("/akm/speaker/" ++ speakerId ++ "/gain").asSymbol;
	var ackPath = ~ackPathFor.value("/speaker/" ++ speakerId ++ "/gain");
	OSCdef(("akm-spk-" ++ speakerId).asSymbol, { |msg|
		var db = msg[1].asFloat;
		~controlBusSpeakerGains.setAt(idx, ~akmDbToFactor.value(db));
		~oscSendNetAddr.sendMsg(ackPath, db);
	}, path, NetAddr(~oscReceiveHost), ~oscReceivePort);
});

// Group EQ
[\satellite, \sub_mid, \sub_lf].do({ |role|
	var roleName = role.asString;
	var path = ("/akm/group/" ++ roleName ++ "/eq").asSymbol;
	var ackPath = ~ackPathFor.value("/group/" ++ roleName ++ "/eq");
	var bus = ~controlBusGroupEq[role];
	OSCdef(("akm-group-eq-" ++ roleName).asSymbol, { |msg|
		var vals = msg.copyRange(1, ~numEQParameters);
		if(vals.size == ~numEQParameters) {
			bus.setn(vals);
			~oscSendNetAddr.sendMsg(ackPath, *vals);
		};
	}, path, NetAddr(~oscReceiveHost), ~oscReceivePort);
});

// Group filters
[\satellite, \sub_mid, \sub_lf].do({ |role|
	var roleName = role.asString;
	var path = ("/akm/group/" ++ roleName ++ "/filter").asSymbol;
	var ackPath = ~ackPathFor.value("/group/" ++ roleName ++ "/filter");
	var bus = ~controlBusGroupFilter[role];
	OSCdef(("akm-group-filter-" ++ roleName).asSymbol, { |msg|
		var vals = msg.copyRange(1, 2);
		if(vals.size == 2) {
			bus.setn(vals);
			~oscSendNetAddr.sendMsg(ackPath, *vals);
		};
	}, path, NetAddr(~oscReceiveHost), ~oscReceivePort);
});

// Sub-mid reverb control
OSCdef("akm-submid-reverb".asSymbol, { |msg|
	if(msg.size >= 3) {
		var enabled = msg[1].asFloat.clip(0.0, 1.0);
		var mix = msg[2].asFloat.clip(0.0, 1.0);
		~controlBusSubMidReverb.setn([enabled, mix]);
		~oscSendNetAddr.sendMsg("/akm/server/ack/group/sub_mid/reverb", enabled, mix);
	};
}, "/akm/group/sub_mid/reverb", NetAddr(~oscReceiveHost), ~oscReceivePort);

// System reverb
OSCdef("akm-system-reverb".asSymbol, { |msg|
	if(msg.size >= 3) {
		var decay = msg[1].asFloat;
		var feedback = msg[2].asFloat;
		~controlBusSystemReverb.setn([decay, feedback]);
		~oscSendNetAddr.sendMsg("/akm/server/ack/system/reverb", decay, feedback);
	};
}, "/akm/system/reverb", NetAddr(~oscReceiveHost), ~oscReceivePort);

// System gain
OSCdef("akm-system-gain".asSymbol, { |msg|
	if(msg.size >= 2) {
		var db = msg[1].asFloat;
		~controlBusSystemGain.set(~akmDbToFactor.value(db));
		~oscSendNetAddr.sendMsg("/akm/server/ack/system/gain", db);
	};
}, "/akm/system/gain", NetAddr(~oscReceiveHost), ~oscReceivePort);

// Quit
OSCdef("akm-server-quit".asSymbol, { |msg|
	~oscSendNetAddr.sendMsg("/akm/server/ack/quit", 1);
	if(~heartbeatRoutine.notNil) { ~heartbeatRoutine.stop };
	if(~stateBroadcastRoutine.notNil) { ~stateBroadcastRoutine.stop };
	s.quit;
}, "/akm/server/quit", NetAddr(~oscReceiveHost), ~oscReceivePort);

// Meters forwarding from SendPeakRMS
OSCdef("akm-meters-forwarder".asSymbol, { |msg|
	var payload = msg.copyRange(3, msg.size - 1);
	~oscSendNetAddr.sendMsg("/akm/server/meters", *payload);
}, "/akm/server/meters/raw", s.addr);

// Heartbeat
~heartbeatRoutine = Routine({
	loop {
		if(s.serverRunning) {
			~oscSendNetAddr.sendMsg("/akm/server/heartbeat", 1);
		};
		1.0.wait;
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
