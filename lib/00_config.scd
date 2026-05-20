(
var layout, server, speakers, roleSet, outputChannels, sourceIds, sourceInputChannels, satPositions;

"[AKM] loading JSON config...".postln;
layout = ~akmReadJSON.value(~layoutPath);
server = ~akmReadJSON.value(~serverPath);

~akmAssert.value(layout.at(\schemaVersion).notNil, "layout missing schemaVersion");
~akmAssert.value(server.at(\schemaVersion).notNil, "server missing schemaVersion");

speakers = layout.at(\speakers);
~akmAssert.value(speakers.notNil and: { speakers.size > 0 }, "layout requires speakers[]");

roleSet = [\satellite, \sub_mid, \sub_lf];
speakers.do({ |sp|
	~akmAssert.value(roleSet.includes(sp.at(\role).asSymbol), "invalid speaker role for " ++ sp.at(\id));
});
outputChannels = speakers.collect({ |sp| sp.at(\outputChannel).asInteger });
~akmAssert.value(outputChannels.asSet.size == outputChannels.size, "duplicate speaker outputChannel in layout");

sourceIds = server.at(\sources).collect({ |src| src.at(\id).asString });
sourceInputChannels = server.at(\sources).collect({ |src| src.at(\inputChannel).asInteger });
~akmAssert.value(sourceIds.asSet.size == sourceIds.size, "duplicate source id in server sources[]");
~akmAssert.value(sourceInputChannels.asSet.size == sourceInputChannels.size, "duplicate source inputChannel in server sources[]");

~akmAssert.value(server.at(\audio).at(\numInputBusChannels).asInteger == sourceIds.size, "numInputBusChannels must match sources[].size");
~akmAssert.value(server.at(\audio).at(\numOutputBusChannels).asInteger == speakers.size, "numOutputBusChannels must match speakers[].size");

~layoutConfig = layout;
~serverConfig = server;

~sourceIds = sourceIds;
~sourceInputChannels = sourceInputChannels;
~numSources = ~sourceIds.size;

~allSpeakers = speakers.collect({ |sp|
	(
		id: sp.at(\id).asString,
		role: sp.at(\role).asSymbol,
		position: [
			sp.at(\position).at(\x).asFloat,
			sp.at(\position).at(\y).asFloat,
			sp.at(\position).at(\z).asFloat
		],
		outputChannel: sp.at(\outputChannel).asInteger
	)
});

~satellites = ~allSpeakers.select({ |sp| sp[\role] == \satellite });
~subMid = ~allSpeakers.select({ |sp| sp[\role] == \sub_mid });
~subLf = ~allSpeakers.select({ |sp| sp[\role] == \sub_lf });

~numSatellites = ~satellites.size;
~numSubMid = ~subMid.size;
~numSubLf = ~subLf.size;
~numOutputs = ~allSpeakers.size;

~akmAssert.value(~numSatellites > 0, "at least one satellite is required");

~soundSpeedInAir = if(layout.at(\panning).at(\soundSpeed).notNil) { layout.at(\panning).at(\soundSpeed).asFloat } { 344.0 };
~numSourceParameters = 7;
~numEQParameters = 21;

~oscReceivePort = server.at(\osc).at(\listen).at(\port).asInteger;
~oscReceiveHost = server.at(\osc).at(\listen).at(\host).asString;
~oscSendNetAddr = NetAddr(server.at(\osc).at(\reply).at(\host).asString, server.at(\osc).at(\reply).at(\port).asInteger);

~telemetryStateHz = server.at(\telemetry).at(\stateBroadcastHz).asFloat.clip(1, 60);
~telemetryMetersHz = server.at(\telemetry).at(\metersHz).asFloat.clip(1, 60);
~telemetryPerfHz = if(server.at(\telemetry).at(\perfHz).notNil) {
	server.at(\telemetry).at(\perfHz).asFloat.clip(1, 10)
} { 3.0 };

satPositions = ~satellites.collect({ |sp| sp[\position] });
~satCentroid = {
	var centroid = layout.at(\panning).at(\centroid);
	if(centroid.isArray) {
		centroid.collect(_.asFloat)
	} {
		~akmCentroid.value(satPositions)
	}
}.value;
~satMaxRadius = ~akmMaxRadius.value(satPositions, ~satCentroid);
if(~satMaxRadius < 0.0001) { ~satMaxRadius = 0.0001 };

~speakerOutputById = IdentityDictionary.new;
~allSpeakers.do({ |sp| ~speakerOutputById[sp[\id].asSymbol] = sp[\outputChannel] });

~speakersByRole = (
	satellite: ~satellites,
	sub_mid: ~subMid,
	sub_lf: ~subLf
);

"[AKM] loaded config - speakers: % (sat: %, sub_mid: %, sub_lf: %), sources: %"
.format(~numOutputs, ~numSatellites, ~numSubMid, ~numSubLf, ~numSources).postln;
)
