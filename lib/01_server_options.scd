(
var audio, scServer, availableDevices, requestedDevices, missing, fatalAndExit;
var inDevs, outDevs;

"[AKM] applying server options...".postln;

audio = ~serverConfig.at(\audio);
scServer = ~serverConfig.at(\scServer);

s = Server.default;

s.options.numBuffers = scServer.at(\numBuffers).asInteger;
s.options.memSize = scServer.at(\memSize).asInteger;
s.options.numWireBufs = scServer.at(\numWireBufs).asInteger;
s.options.maxNodes = scServer.at(\maxNodes).asInteger;

// Validate that the audio devices named in server.json actually exist on
// this machine BEFORE handing scsynth a config it can't satisfy.
//
// When scsynth gets handed an outDevice name that doesn't exist on the host,
// it doesn't error out — it silently falls back to the system default output.
// On macOS that's usually "MacBook Pro Speakers" (2 ch). If our config also
// declared numOutputBusChannels > 2, the resulting CoreAudio open fails deep
// inside AVAudioSession teardown and surfaces as the cryptic
// `objc[]: Method cache corrupted ... selector '_isDeallocating' ... isa 'AVAudioSession'`
// crash, followed by `Server 'localhost' exited with exit code 0`. Catching
// it here gives the operator a clear, actionable message instead.
fatalAndExit = { |msg|
	("[AKM] FATAL: " ++ msg).postln;
	("[AKM] FATAL: " ++ msg).error;
	// Give sclang one AppClock tick to flush both streams to the agent's
	// log forwarder before we yank the process.
	AppClock.sched(0.1, { 0.exit; nil });
};

// Enumerate the CoreAudio device list. SC 3.14.1 exposes the working
// class method `ServerOptions.devices` (combined in+out, deduplicated).
// Older SC builds put it on the instance instead — fall back to that and
// finally to the per-direction primitives if both fail.
//
// CRITICAL: every entry is coerced to String. On some SC builds the
// primitive backing these accessors returns Symbols, and `String == Symbol`
// is false in SC even when the text matches — exactly the trap that made
// our previous pre-flight flag `BlackHole 64ch` as missing while listing
// it as available in the same log line.
availableDevices = try { ServerOptions.devices } { nil };
if(availableDevices.isNil) {
	availableDevices = try { s.options.devices } { nil };
};
if(availableDevices.isNil) {
	inDevs = try { s.options.inDevices } { nil } ? [];
	outDevs = try { s.options.outDevices } { nil } ? [];
	availableDevices = inDevs ++ outDevs;
};
if(availableDevices.isNil) { availableDevices = [] };
availableDevices = availableDevices.collect({ |d| d.asString });

if(availableDevices.size > 0) {
	requestedDevices = [];
	if(audio.at(\inDevice).notNil) {
		requestedDevices = requestedDevices.add((kind: "inDevice", name: audio.at(\inDevice).asString));
	};
	if(audio.at(\outDevice).notNil) {
		requestedDevices = requestedDevices.add((kind: "outDevice", name: audio.at(\outDevice).asString));
	};
	if(audio.at(\device).notNil
		and: { audio.at(\inDevice).isNil }
		and: { audio.at(\outDevice).isNil }) {
		requestedDevices = requestedDevices.add((kind: "device", name: audio.at(\device).asString));
	};

	// Coerce both sides to String + compare via `detect`. `Array.includes`
	// uses `==`, which is type-strict between Symbol and String even when
	// the underlying text matches — that's the trap that previously made
	// this check report `BlackHole 64ch` as missing even though it was
	// listed right next to it in the same log line.
	missing = requestedDevices.select({ |entry|
		var needle = entry.at(\name).asString;
		availableDevices.detect({ |dev| dev.asString == needle }).isNil
	});

	if(missing.size > 0) {
		var detail = missing.collect({ |entry|
			(entry.at(\kind) ++ " '" ++ entry.at(\name) ++ "'")
		}).join(", ");
		fatalAndExit.value(
			"audio device(s) not available on this host: " ++ detail
			++ ". Available devices: ["
			++ availableDevices.collect({ |n| "'" ++ n ++ "'" }).join(", ")
			++ "]. Fix the `audio.inDevice` / `audio.outDevice` / `audio.device` fields in server.json (or plug the device in) before retrying."
		);
	} {
		"[AKM] audio devices OK: %".format(
			requestedDevices.collect({ |entry|
				entry.at(\kind) ++ "='" ++ entry.at(\name) ++ "'"
			}).join(", ")
		).postln;
	};
} {
	// Couldn't enumerate any devices via either inDevices or outDevices —
	// either the primitives aren't wired up in this SC build or the host
	// genuinely has no CoreAudio devices. Not fatal: let scsynth itself
	// surface whatever it sees.
	"[AKM] WARN: could not enumerate audio devices via ServerOptions.devices / s.options.*Devices; skipping device pre-flight".postln;
};

// Device routing mode:
//   - split mode: explicit inDevice/outDevice
//   - single mode: device
//
// IMPORTANT: clear the mutually-exclusive fields so ServerOptions doesn't
// carry stale values across boots (which can make CoreAudio routing ambiguous
// on some macOS/SC combos and lead to silent "exit code 0" right after audio
// driver init).
if(audio.at(\inDevice).notNil or: { audio.at(\outDevice).notNil }) {
	if(audio.at(\device).notNil) {
		"[AKM] WARN: audio.device is set but split routing is configured; ignoring audio.device and using audio.inDevice/audio.outDevice".postln;
	};
	s.options.device = nil;
	if(audio.at(\inDevice).notNil) { s.options.inDevice = audio.at(\inDevice).asString };
	if(audio.at(\outDevice).notNil) { s.options.outDevice = audio.at(\outDevice).asString };
	"[AKM] audio routing mode: split (in='%', out='%')".format(
		(audio.at(\inDevice) ? "<default>").asString,
		(audio.at(\outDevice) ? "<default>").asString
	).postln;
} {
	s.options.inDevice = nil;
	s.options.outDevice = nil;
	if(audio.at(\device).notNil) {
		s.options.device = audio.at(\device).asString;
		"[AKM] audio routing mode: single (device='%')".format(
			audio.at(\device).asString
		).postln;
	} {
		s.options.device = nil;
		"[AKM] audio routing mode: default device".postln;
	};
};

s.options.sampleRate = audio.at(\sampleRate).asFloat;
s.options.safetyClipThreshold = audio.at(\safetyClipThreshold).asFloat;
s.options.numInputBusChannels = audio.at(\numInputBusChannels).asInteger;
s.options.numOutputBusChannels = audio.at(\numOutputBusChannels).asInteger;

"[AKM] server options applied.".postln;
)
