(
"[AKM] creating synth instances...".postln;

~sourceSynths = IdentityDictionary.new;

~sourceIds.do({ |sourceId, i|
	var key = sourceId.asSymbol;
	var inputBus = ~controlBussesInputs[key];
	var spatSynth, inputSynth;

	spatSynth = Synth.tail(~sourcesSpatPannersGroup, \spatPannerSource, [
		\sourceInputBus, inputBus.index,
		\satGainBus, ~controlBussesSatGains[key].index,
		\satDelayBus, ~controlBussesSatDelays[key].index,
		\subMidGainBus, ~controlBussesSubMidGains[key].index,
		\subMidDelayBus, ~controlBussesSubMidDelays[key].index,
		\subLfGainBus, ~controlBussesSubLfGains[key].index,
		\subLfDelayBus, ~controlBussesSubLfDelays[key].index,
		\attenuationBus, ~controlBussesAttenuation[key].index
	]);

	inputSynth = Synth.tail(~sourcesInputProcessingGroup, \inputAudioProcessor, [
		\inputChannel, ~sourceInputChannels[i],
		\sourceInputBus, inputBus.index,
		\attenuationBus, ~controlBussesAttenuation[key].index,
		\satGainBus, ~controlBussesSatGains[key].index,
		\satDelayBus, ~controlBussesSatDelays[key].index,
		\subMidGainBus, ~controlBussesSubMidGains[key].index,
		\subMidDelayBus, ~controlBussesSubMidDelays[key].index,
		\subLfGainBus, ~controlBussesSubLfGains[key].index,
		\subLfDelayBus, ~controlBussesSubLfDelays[key].index
	]);

	~sourceSynths[key] = (
		spat: spatSynth,
		input: inputSynth
	);
});

~satReverbSynth = Synth.tail(~reverbGroup, \satReverbFX);
~subMidReverbSynth = Synth.tail(~reverbGroup, \subMidReverbFX);

~satFilterEqSynth = Synth.tail(~filtersEqGroup, \groupSatFilterEq);
~subMidFilterEqSynth = Synth.tail(~filtersEqGroup, \groupSubMidFilterEq);
~subLfFilterEqSynth = Synth.tail(~filtersEqGroup, \groupSubLfFilterEq);

~outputRouterSynth = Synth.tail(~outputGroup, \outputRouter);
// `\meters` taps both the source inputs (via SoundIn) and the post-gain
// speaker outputs (via the shared meter bus). It must run after the router so
// the meter bus reflects the current block's speaker output.
~metersSynth = Synth.tail(~outputGroup, \meters);

s.sync;
"[AKM] synth instances ready.".postln;
)
