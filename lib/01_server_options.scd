(
var audio, scServer;

"[AKM] applying server options...".postln;

audio = ~serverConfig.at(\audio);
scServer = ~serverConfig.at(\scServer);

s = Server.default;

s.options.numBuffers = scServer.at(\numBuffers).asInteger;
s.options.memSize = scServer.at(\memSize).asInteger;
s.options.numWireBufs = scServer.at(\numWireBufs).asInteger;
s.options.maxNodes = scServer.at(\maxNodes).asInteger;

if(audio.at(\inDevice).notNil) { s.options.inDevice = audio.at(\inDevice).asString };
if(audio.at(\outDevice).notNil) { s.options.outDevice = audio.at(\outDevice).asString };
if(
	audio.at(\device).notNil
	and: { audio.at(\inDevice).isNil }
	and: { audio.at(\outDevice).isNil }
) {
	s.options.device = audio.at(\device).asString
};

s.options.sampleRate = audio.at(\sampleRate).asFloat;
s.options.safetyClipThreshold = audio.at(\safetyClipThreshold).asFloat;
s.options.numInputBusChannels = audio.at(\numInputBusChannels).asInteger;
s.options.numOutputBusChannels = audio.at(\numOutputBusChannels).asInteger;

"[AKM] server options applied.".postln;
)
