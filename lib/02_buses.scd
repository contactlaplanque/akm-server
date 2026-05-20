(
var satEqDefaults, subEqDefaults, savedState, savedSystemGain, savedSpeakerGains, savedSpeakerMutes;
var savedSubMidReverb, savedSystemReverb, savedEq, savedFilter;
var encodeEqStateForBus;

"[AKM] allocating busses...".postln;

s.freeAll;
s.newBusAllocators;

// Convert a saved EQ state event (matching the frontend EqState shape) to the
// 21-float layout expected by the group EQ bus. Falls back to `defaults` per
// slot if any field is missing.
encodeEqStateForBus = { |eq, defaults|
	var pick, band;
	if(eq.isNil) {
		defaults
	} {
		pick = { |evt, key, fallback|
			if(evt.notNil and: { evt.at(key).notNil }) { evt.at(key).asFloat } { fallback }
		};
		band = { |bandKey, baseIdx|
			var b = eq.at(bandKey);
			[
				pick.value(b, \enabled, defaults[baseIdx]),
				pick.value(b, \freq, defaults[baseIdx + 1]),
				pick.value(b, \gainDb, defaults[baseIdx + 2]),
				pick.value(b, \rq, defaults[baseIdx + 3])
			]
		};
		[pick.value(eq, \enabled, defaults[0])]
			++ band.value(\lowShelf, 1)
			++ band.value(\peak1, 5)
			++ band.value(\peak2, 9)
			++ band.value(\peak3, 13)
			++ band.value(\highShelf, 17)
	}
};

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
~controlBusSpeakerMutes = Bus.control(s, ~numOutputs);
// Group-level gain in linear factor (dB on the wire). Slot order matches the
// role enum: 0=satellite, 1=sub_mid, 2=sub_lf.
~controlBusGroupGains = Bus.control(s, 3);
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

// Internal audio bus that mirrors the post-gain speaker signal in the
// concatenated order [satellites, sub_mid, sub_lf]. The dedicated `\meters`
// synth taps it (instead of using SendPeakRMS which interleaves peak/rms).
~audioBusMetersSpeakerOuts = Bus.audio(s, ~numOutputs);

satEqDefaults = [
	0, 0, 400, 0, 1,
	0, 2000, 0, 1,
	0, 6000, 0, 1,
	0, 12000, 0, 1,
	0, 16000, 0, 1
];
subEqDefaults = satEqDefaults.copy;

// `state` block in server.json is optional; when present we use it to hydrate
// every persisted bus so the SC server, on its own boot, matches the saved
// configuration without waiting for the frontend to push updates.
savedState = ~serverConfig[\state];

savedEq = savedState.notNil.if({ savedState[\eqByRole] }, { nil });
~controlBusGroupEq[\satellite].setn(
	encodeEqStateForBus.value(savedEq.notNil.if({ savedEq[\satellite] }, { nil }), satEqDefaults)
);
~controlBusGroupEq[\sub_mid].setn(
	encodeEqStateForBus.value(savedEq.notNil.if({ savedEq[\sub_mid] }, { nil }), subEqDefaults)
);
~controlBusGroupEq[\sub_lf].setn(
	encodeEqStateForBus.value(savedEq.notNil.if({ savedEq[\sub_lf] }, { nil }), subEqDefaults)
);

savedFilter = savedState.notNil.if({ savedState[\filterByRole] }, { nil });
~controlBusGroupFilter[\satellite].setn(
	(savedFilter.notNil and: { savedFilter[\satellite].notNil }).if(
		{ [savedFilter[\satellite][\freq].asFloat, savedFilter[\satellite][\rq].asFloat] },
		{ [120.0, 1.0] }
	)
);
~controlBusGroupFilter[\sub_mid].setn(
	(savedFilter.notNil and: { savedFilter[\sub_mid].notNil }).if(
		{ [savedFilter[\sub_mid][\freq].asFloat, savedFilter[\sub_mid][\rq].asFloat] },
		{ [180.0, 1.0] }
	)
);
~controlBusGroupFilter[\sub_lf].setn(
	(savedFilter.notNil and: { savedFilter[\sub_lf].notNil }).if(
		{ [savedFilter[\sub_lf][\freq].asFloat, savedFilter[\sub_lf][\rq].asFloat] },
		{ [90.0, 1.0] }
	)
);

savedSpeakerGains = savedState.notNil.if({ savedState[\speakerGains] }, { nil });
~controlBusSpeakerGains.setn(
	~allSpeakers.collect({ |sp|
		var saved = savedSpeakerGains.notNil.if({ savedSpeakerGains[sp[\id].asSymbol] }, { nil });
		saved.notNil.if({ ~akmDbToFactor.value(saved.asFloat) }, { 1.0 })
	})
);

savedSpeakerMutes = savedState.notNil.if({ savedState[\speakerMutes] }, { nil });
~controlBusSpeakerMutes.setn(
	~allSpeakers.collect({ |sp|
		var saved = savedSpeakerMutes.notNil.if({ savedSpeakerMutes[sp[\id].asSymbol] }, { nil });
		saved.notNil.if({ if(saved.asBoolean) { 1.0 } { 0.0 } }, { 0.0 })
	})
);

savedSystemGain = savedState.notNil.if({ savedState[\systemGainDb] }, { nil });
~controlBusSystemGain.set(
	savedSystemGain.notNil.if({ ~akmDbToFactor.value(savedSystemGain.asFloat) }, { 1.0 })
);

// Per-group gain bus (sat, sub_mid, sub_lf): hydrate from state.groupGainsDb
// if present, else neutral 0 dB.
~controlBusGroupGains.setn(
	[\satellite, \sub_mid, \sub_lf].collect({ |role|
		var saved = (savedState.notNil and: { savedState[\groupGainsDb].notNil }).if(
			{ savedState[\groupGainsDb][role] },
			{ nil }
		);
		saved.notNil.if({ ~akmDbToFactor.value(saved.asFloat) }, { 1.0 })
	})
);

savedSystemReverb = savedState.notNil.if({ savedState[\systemReverb] }, { nil });
~controlBusSystemReverb.setn(
	savedSystemReverb.notNil.if(
		{ [savedSystemReverb[\decay].asFloat, savedSystemReverb[\feedback].asFloat] },
		{ [~serverConfig[\reverb][\decay].asFloat, ~serverConfig[\reverb][\feedback].asFloat] }
	)
);

savedSubMidReverb = savedState.notNil.if({ savedState[\subMidReverb] }, { nil });
~controlBusSubMidReverb.setn(
	savedSubMidReverb.notNil.if(
		{ [savedSubMidReverb[\enabled].asFloat, savedSubMidReverb[\mix].asFloat] },
		{ [
			if(~serverConfig[\reverb][\subMidEnabled].asBoolean) { 1.0 } { 0.0 },
			0.35
		] }
	)
);

"[AKM] busses allocated.".postln;
)
