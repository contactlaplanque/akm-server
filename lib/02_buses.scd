(
var satEqDefaults, subEqDefaults;

"[AKM] allocating busses...".postln;

s.freeAll;
s.newBusAllocators;

~controlBussesInputs = IdentityDictionary.new;
~controlBussesSatGains = IdentityDictionary.new;
~controlBussesSatDelays = IdentityDictionary.new;
~controlBussesSubMidGains = IdentityDictionary.new;
~controlBussesSubMidDelays = IdentityDictionary.new;
~controlBussesSubLfGains = IdentityDictionary.new;
~controlBussesSubLfDelays = IdentityDictionary.new;
~controlBussesAttenuation = IdentityDictionary.new;

~sourceIds.do({ |sourceId|
	var key = sourceId.asSymbol;
	~controlBussesInputs[key] = Bus.control(s, ~numSourceParameters);
	~controlBussesSatGains[key] = Bus.control(s, ~numSatellites);
	~controlBussesSatDelays[key] = Bus.control(s, ~numSatellites);
	~controlBussesSubMidGains[key] = Bus.control(s, ~numSubMid);
	~controlBussesSubMidDelays[key] = Bus.control(s, ~numSubMid);
	~controlBussesSubLfGains[key] = Bus.control(s, ~numSubLf);
	~controlBussesSubLfDelays[key] = Bus.control(s, ~numSubLf);
	~controlBussesAttenuation[key] = Bus.control(s, 1);
});

~controlBusGroupEq = (
	satellite: Bus.control(s, ~numEQParameters),
	sub_mid: Bus.control(s, ~numEQParameters),
	sub_lf: Bus.control(s, ~numEQParameters)
);

~controlBusGroupFilter = (
	satellite: Bus.control(s, 2),
	sub_mid: Bus.control(s, 2),
	sub_lf: Bus.control(s, 2)
);

~controlBusSpeakerGains = Bus.control(s, ~numOutputs);
~controlBusSystemGain = Bus.control(s, 1);
~controlBusSystemReverb = Bus.control(s, 2);
~controlBusSubMidReverb = Bus.control(s, 2);

~audioBusSatDry = Bus.audio(s, ~numSatellites);
~audioBusSatPre = Bus.audio(s, ~numSatellites);
~audioBusSatPost = Bus.audio(s, ~numSatellites);

~audioBusSubMidDry = Bus.audio(s, ~numSubMid);
~audioBusSubMidPre = Bus.audio(s, ~numSubMid);
~audioBusSubMidPost = Bus.audio(s, ~numSubMid);

~audioBusSubLfDry = Bus.audio(s, ~numSubLf);

~audioBusSatProcessed = Bus.audio(s, ~numSatellites);
~audioBusSubMidProcessed = Bus.audio(s, ~numSubMid);
~audioBusSubLfProcessed = Bus.audio(s, ~numSubLf);

satEqDefaults = [
	0, 0, 400, 0, 1,
	0, 2000, 0, 1,
	0, 6000, 0, 1,
	0, 12000, 0, 1,
	0, 16000, 0, 1
];
subEqDefaults = satEqDefaults.copy;

~controlBusGroupEq[\satellite].setn(satEqDefaults);
~controlBusGroupEq[\sub_mid].setn(subEqDefaults);
~controlBusGroupEq[\sub_lf].setn(subEqDefaults);

~controlBusGroupFilter[\satellite].setn([120.0, 1.0]); // RHPF
~controlBusGroupFilter[\sub_mid].setn([180.0, 1.0]);   // RLPF
~controlBusGroupFilter[\sub_lf].setn([90.0, 1.0]);     // RLPF

~controlBusSpeakerGains.setn(Array.fill(~numOutputs, { 1.0 }));
~controlBusSystemGain.set(1.0);

~controlBusSystemReverb.setn([
	~serverConfig[\reverb][\decay].asFloat,
	~serverConfig[\reverb][\feedback].asFloat
]);
~controlBusSubMidReverb.setn([
	if(~serverConfig[\reverb][\subMidEnabled].asBoolean) { 1.0 } { 0.0 },
	0.35
]);

"[AKM] busses allocated.".postln;
)
