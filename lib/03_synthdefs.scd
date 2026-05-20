(
var satX, satY, satZ, satOutCh;
var subMidX, subMidY, subMidZ, subMidOutCh;
var subLfX, subLfY, subLfZ, subLfOutCh;
var centroidX, centroidY, centroidZ, satMaxRadius, cSoundSpeed;
var numSatellites, numSubMid, numSubLf, numOutputs, numSources, numSourceParams, numEqParams;
var satFilterBus, satEqBus, subMidFilterBus, subMidEqBus, subLfFilterBus, subLfEqBus;
var sysReverbBus, subMidReverbBus, sysGainBus, speakerGainsBus, speakerMutesBus, groupGainsBus;
var busSatDry, busSatPre, busSatPost, busSatProcessed;
var busSubMidDry, busSubMidPre, busSubMidPost, busSubMidProcessed;
var busSubLfDry, busSubLfProcessed;
var busMetersSpeakerOuts;
var sourceInputChannels;
var metersHz;
// Diagnostic A/B: set true to pass wet buses straight through with no
// LocalIn/LocalOut feedback. If glitches disappear, the reverb loop is
// the culprit. Set false (and restart the server) for normal operation.
var bypassReverbDiag;
bypassReverbDiag = true;

"[AKM] adding SynthDefs...".postln;
if(bypassReverbDiag) {
	"[AKM] DIAG: reverb BYPASSED — sat/sub_mid wet buses pass through unchanged (no feedback). Set bypassReverbDiag = false in lib/03_synthdefs.scd and restart to restore.".postln;
};

satX = ~satellites.collect({ |sp| sp[\position][0] });
satY = ~satellites.collect({ |sp| sp[\position][1] });
satZ = ~satellites.collect({ |sp| sp[\position][2] });
satOutCh = ~satellites.collect({ |sp| sp[\outputChannel] });

subMidX = ~subMid.collect({ |sp| sp[\position][0] });
subMidY = ~subMid.collect({ |sp| sp[\position][1] });
subMidZ = ~subMid.collect({ |sp| sp[\position][2] });
subMidOutCh = ~subMid.collect({ |sp| sp[\outputChannel] });

subLfX = ~subLf.collect({ |sp| sp[\position][0] });
subLfY = ~subLf.collect({ |sp| sp[\position][1] });
subLfZ = ~subLf.collect({ |sp| sp[\position][2] });
subLfOutCh = ~subLf.collect({ |sp| sp[\outputChannel] });

centroidX = ~satCentroid[0];
centroidY = ~satCentroid[1];
centroidZ = ~satCentroid[2];
satMaxRadius = ~satMaxRadius.asFloat;
cSoundSpeed = ~soundSpeedInAir.asFloat;

numSatellites = ~numSatellites;
numSubMid = ~numSubMid;
numSubLf = ~numSubLf;
numOutputs = ~numOutputs;
numSources = ~numSources;
numSourceParams = ~numSourceParameters;
numEqParams = ~numEQParameters;
sourceInputChannels = ~sourceInputChannels;

satFilterBus = ~controlBusGroupFilter[\satellite].index;
satEqBus = ~controlBusGroupEq[\satellite].index;
subMidFilterBus = ~controlBusGroupFilter[\sub_mid].index;
subMidEqBus = ~controlBusGroupEq[\sub_mid].index;
subLfFilterBus = ~controlBusGroupFilter[\sub_lf].index;
subLfEqBus = ~controlBusGroupEq[\sub_lf].index;

sysReverbBus = ~controlBusSystemReverb.index;
subMidReverbBus = ~controlBusSubMidReverb.index;
sysGainBus = ~controlBusSystemGain.index;
speakerGainsBus = ~controlBusSpeakerGains.index;
speakerMutesBus = ~controlBusSpeakerMutes.index;
groupGainsBus = ~controlBusGroupGains.index;

busSatDry = ~audioBusSatDry.index;
busSatPre = ~audioBusSatPre.index;
busSatPost = ~audioBusSatPost.index;
busSatProcessed = ~audioBusSatProcessed.index;
busSubMidDry = ~audioBusSubMidDry.index;
busSubMidPre = ~audioBusSubMidPre.index;
busSubMidPost = ~audioBusSubMidPost.index;
busSubMidProcessed = ~audioBusSubMidProcessed.index;
busSubLfDry = ~audioBusSubLfDry.index;
busSubLfProcessed = ~audioBusSubLfProcessed.index;
busMetersSpeakerOuts = ~audioBusMetersSpeakerOuts.index;

metersHz = ~telemetryMetersHz;

SynthDef(\spatPannerSource, {
	|sourceInputBus=0, satGainBus=0, satDelayBus=0, subMidGainBus=0, subMidDelayBus=0, subLfGainBus=0, subLfDelayBus=0, attenuationBus=0|
	var params, posX, posY, posZ, sourceRadius, exponentA, delayLevel, satDist, satWeights, satNorm, satGains, satDelays;
	var subMidDist, subMidWeights, subMidNorm, subMidGains, subMidDelays;
	var subLfDist, subLfWeights, subLfNorm, subLfGains, subLfDelays;
	var distToCenter, alpha = 0.04, qExp = 0.2, pExp, attenuation;

	params = In.kr(sourceInputBus, numSourceParams);
	posX = params[0];
	posY = params[1];
	posZ = params[2];
	sourceRadius = params[3].max(0.0001);
	exponentA = params[4].max(0.01);
	delayLevel = params[5];

	satDist = Array.fill(numSatellites, { |i|
		(((posX - satX[i]).squared + (posY - satY[i]).squared + (posZ - satZ[i]).squared).sqrt + 0.00001)
	});
	satWeights = satDist.collect({ |d| d.pow(exponentA.neg) });
	satNorm = (satWeights.collect({ |w| w.squared }).sum + 1e-9).sqrt.reciprocal;
	// Soft radius edge (0.15 m) instead of a hard `(dist < radius)` gate. The
	// hard gate clicked whenever a source crossed the boundary and injected
	// AM sidebands into the wet bus; in the reverb feedback loop that reads
	// as distortion that grows while audio is playing.
	satGains = Array.fill(numSatellites, { |i|
		var gate = ((sourceRadius - satDist[i]) / (sourceRadius * 0.15 + 0.001)).clip(0, 1);
		satWeights[i] * satNorm * gate
	});
	satDelays = satDist.collect({ |d| (d / cSoundSpeed) * delayLevel });

	subMidDist = Array.fill(numSubMid, { |i|
		(((posX - subMidX[i]).squared + (posY - subMidY[i]).squared + (posZ - subMidZ[i]).squared).sqrt + 0.00001)
	});
	subMidWeights = subMidDist.collect({ |d| d.pow(exponentA.neg) });
	subMidNorm = (subMidWeights.collect({ |w| w.squared }).sum + 1e-9).sqrt.reciprocal;
	subMidGains = Array.fill(numSubMid, { |i|
		var gate = ((sourceRadius - subMidDist[i]) / (sourceRadius * 0.15 + 0.001)).clip(0, 1);
		subMidWeights[i] * subMidNorm * gate
	});
	subMidDelays = subMidDist.collect({ |d| (d / cSoundSpeed) * delayLevel });

	subLfDist = Array.fill(numSubLf, { |i|
		(((posX - subLfX[i]).squared + (posY - subLfY[i]).squared + (posZ - subLfZ[i]).squared).sqrt + 0.00001)
	});
	subLfWeights = subLfDist.collect({ |d| d.pow(exponentA.neg) });
	subLfNorm = (subLfWeights.collect({ |w| w.squared }).sum + 1e-9).sqrt.reciprocal;
	// sub_lf: no radius gate — all sources always feed into LF subs.
	// Distance-based attenuation still applies via the shared `attenuation` bus
	// (computed below from the satellite centroid / maxRadius).
	subLfGains = Array.fill(numSubLf, { |i| subLfWeights[i] * subLfNorm });
	subLfDelays = subLfDist.collect({ |d| (d / cSoundSpeed) * delayLevel });

	distToCenter = ((posX - centroidX).squared + (posY - centroidY).squared + (posZ - centroidZ).squared).sqrt;
	pExp = 1 + (distToCenter / satMaxRadius).pow(qExp);
	attenuation = 1 / (1 + (alpha * (distToCenter / satMaxRadius).pow(pExp)));

	Out.kr(satGainBus, satGains);
	Out.kr(satDelayBus, satDelays);
	Out.kr(subMidGainBus, subMidGains);
	Out.kr(subMidDelayBus, subMidDelays);
	Out.kr(subLfGainBus, subLfGains);
	Out.kr(subLfDelayBus, subLfDelays);
	Out.kr(attenuationBus, attenuation);
}).add;

SynthDef(\inputAudioProcessor, {
	|inputChannel=0, sourceInputBus=0, attenuationBus=0, satGainBus=0, satDelayBus=0, subMidGainBus=0, subMidDelayBus=0, subLfGainBus=0, subLfDelayBus=0|
	var params, reverbMix, audioIn, attenuation;
	var satGains, satDelays, satDry, satWet;
	var subMidGains, subMidDelays, subMidDry, subMidWet;
	var subLfGains, subLfDelays, subLfDry;

	params = In.kr(sourceInputBus, numSourceParams);
	reverbMix = params[6].clip(0.0, 1.0);
	audioIn = SoundIn.ar(inputChannel);
	attenuation = In.kr(attenuationBus, 1).lag(0.05);

	satGains = In.kr(satGainBus, numSatellites).lag(0.05);
	// .lag(0.05) smooths the per-channel delay-time bus so DelayC.ar's
	// interpolated read doesn't click on instantaneous steps (boot-time
	// `delayLevel` 0->1, fast source moves, large slider jumps).
	satDelays = In.kr(satDelayBus, numSatellites).lag(0.05);
	satDry = Array.fill(numSatellites, { |i|
		DelayC.ar(
			in: satGains[i] * audioIn * attenuation,
			maxdelaytime: 3.0,
			// Clamp before squaring: DelayC needs delaytime < maxdelaytime (3.0).
			delaytime: satDelays[i].clip(0, 1.73).squared
		)
	});
	satWet = satDry * reverbMix;

	subMidGains = In.kr(subMidGainBus, numSubMid).lag(0.05);
	subMidDelays = In.kr(subMidDelayBus, numSubMid).lag(0.05);
	subMidDry = Array.fill(numSubMid, { |i|
		DelayC.ar(
			in: subMidGains[i] * audioIn * attenuation,
			maxdelaytime: 3.0,
			delaytime: subMidDelays[i].clip(0, 1.73).squared
		)
	});
	subMidWet = subMidDry * reverbMix;

	subLfGains = In.kr(subLfGainBus, numSubLf).lag(0.05);
	subLfDelays = In.kr(subLfDelayBus, numSubLf).lag(0.05);
	subLfDry = Array.fill(numSubLf, { |i|
		DelayC.ar(
			in: subLfGains[i] * audioIn * attenuation,
			maxdelaytime: 3.0,
			delaytime: subLfDelays[i].clip(0, 1.73).squared
		)
	});

	Out.ar(busSatDry, satDry);
	Out.ar(busSatPre, satWet);
	Out.ar(busSubMidDry, subMidDry);
	Out.ar(busSubMidPre, subMidWet);
	Out.ar(busSubLfDry, subLfDry);
}).add;

SynthDef(\satReverbFX, {
	var signals, fbk, params, decay, feedback;
	params = In.kr(sysReverbBus, 2);
	decay = params[0].clip(0.0, 5.0);
	feedback = params[1].clip(0.0, 0.99);

	if(bypassReverbDiag) {
		// Wet send only (pre-delay panner output). No allpass, no LocalIn/Out.
		Out.ar(busSatPost, In.ar(busSatPre, numSatellites));
	} {
		signals = In.ar(busSatPre, numSatellites);
		// Headroom before the feedback path: many sources sum into busSatPre, so
		// the wet bus can run hot even when each source only sends a little reverb.
		signals = (signals * 0.35).tanh;
		signals = OnePole.ar(signals, 0.72);
		signals = AllpassC.ar(signals, 0.3, LFNoise1.kr(1).range(0.3, 0.29), 3);

		fbk = LocalIn.ar(numSatellites);
		if(numSatellites > 1) { fbk = fbk.scramble };
		fbk = OnePole.ar(fbk, 0.2);
		fbk = fbk + signals;
		7.do({ fbk = AllpassN.ar(fbk, 0.05, { 0.050.rand } ! numSatellites, decay) });
		fbk = LeakDC.ar(fbk, 0.99);
		fbk = HPF.ar(fbk, 40);
		LocalOut.ar((fbk * feedback).clip(-0.95, 0.95));
		Out.ar(busSatPost, fbk);
	};
}).add;

SynthDef(\subMidReverbFX, {
	var signals, fbk, sysParams, subParams, decay, feedback, enabled, mix;
	sysParams = In.kr(sysReverbBus, 2);
	subParams = In.kr(subMidReverbBus, 2);
	decay = sysParams[0].clip(0.0, 5.0);
	feedback = sysParams[1].clip(0.0, 0.99);
	enabled = subParams[0].clip(0.0, 1.0);
	mix = subParams[1].clip(0.0, 1.0);

	if(bypassReverbDiag) {
		Out.ar(busSubMidPost, In.ar(busSubMidPre, numSubMid) * enabled * mix);
	} {
		signals = In.ar(busSubMidPre, numSubMid) * enabled * mix;
		signals = (signals * 0.35).tanh;
		signals = OnePole.ar(signals, 0.72);
		signals = AllpassC.ar(signals, 0.3, LFNoise1.kr(1).range(0.3, 0.29), 2);

		fbk = LocalIn.ar(numSubMid);
		if(numSubMid > 1) { fbk = fbk.scramble };
		fbk = OnePole.ar(fbk, 0.2);
		fbk = fbk + signals;
		5.do({ fbk = AllpassN.ar(fbk, 0.05, { 0.050.rand } ! numSubMid, decay) });
		fbk = LeakDC.ar(fbk, 0.99);
		fbk = HPF.ar(fbk, 40);
		LocalOut.ar((fbk * feedback).clip(-0.95, 0.95));
		Out.ar(busSubMidPost, fbk);
	};
}).add;

// Group filter + 3-band parametric EQ. v3 layout: eqOn at [0], then
// (enabled, freq, gainDb, rq) at offsets [1..4], [5..8], [9..12].
// All freq/db/rq inputs and the upstream filter cutoff/rq are smoothed
// with .lag(0.05). Without lag, BPeakEQ / RHPF / RLPF re-derive their
// biquad coefficients every control block straight from the bus, so a
// 60 Hz slider drag is heard as zipper noise and, at extreme settings,
// transient instabilities that the satellite reverb feedback loop then
// stretches into "growing distortion".
SynthDef(\groupSatFilterEq, {
	var dry, wet, sig, filterParams, eqParams, eqOn, fFreq, fRq, signal;
	dry = In.ar(busSatDry, numSatellites);
	wet = In.ar(busSatPost, numSatellites);
	filterParams = In.kr(satFilterBus, 2);
	eqParams = In.kr(satEqBus, numEqParams);
	eqOn = eqParams[0];
	fFreq = filterParams[0].lag(0.05);
	fRq = filterParams[1].lag(0.05);

	sig = (dry + wet).collect({ |ch|
		signal = RHPF.ar(ch, fFreq, fRq);
		signal = BPeakEQ.ar(signal,
			freq: eqParams[2].lag(0.05),
			rq:   eqParams[4].lag(0.05),
			db:   (eqOn * eqParams[1] * eqParams[3]).lag(0.05));
		signal = BPeakEQ.ar(signal,
			freq: eqParams[6].lag(0.05),
			rq:   eqParams[8].lag(0.05),
			db:   (eqOn * eqParams[5] * eqParams[7]).lag(0.05));
		BPeakEQ.ar(signal,
			freq: eqParams[10].lag(0.05),
			rq:   eqParams[12].lag(0.05),
			db:   (eqOn * eqParams[9] * eqParams[11]).lag(0.05));
	});
	Out.ar(busSatProcessed, sig);
}).add;

SynthDef(\groupSubMidFilterEq, {
	var dry, wet, sig, filterParams, eqParams, eqOn, fFreq, fRq, signal;
	dry = In.ar(busSubMidDry, numSubMid);
	wet = In.ar(busSubMidPost, numSubMid);
	filterParams = In.kr(subMidFilterBus, 2);
	eqParams = In.kr(subMidEqBus, numEqParams);
	eqOn = eqParams[0];
	fFreq = filterParams[0].lag(0.05);
	fRq = filterParams[1].lag(0.05);

	sig = (dry + wet).collect({ |ch|
		signal = RLPF.ar(ch, fFreq, fRq);
		signal = BPeakEQ.ar(signal,
			freq: eqParams[2].lag(0.05),
			rq:   eqParams[4].lag(0.05),
			db:   (eqOn * eqParams[1] * eqParams[3]).lag(0.05));
		signal = BPeakEQ.ar(signal,
			freq: eqParams[6].lag(0.05),
			rq:   eqParams[8].lag(0.05),
			db:   (eqOn * eqParams[5] * eqParams[7]).lag(0.05));
		BPeakEQ.ar(signal,
			freq: eqParams[10].lag(0.05),
			rq:   eqParams[12].lag(0.05),
			db:   (eqOn * eqParams[9] * eqParams[11]).lag(0.05));
	});
	Out.ar(busSubMidProcessed, sig);
}).add;

SynthDef(\groupSubLfFilterEq, {
	var dry, sig, filterParams, eqParams, eqOn, fFreq, fRq, signal;
	dry = In.ar(busSubLfDry, numSubLf);
	filterParams = In.kr(subLfFilterBus, 2);
	eqParams = In.kr(subLfEqBus, numEqParams);
	eqOn = eqParams[0];
	fFreq = filterParams[0].lag(0.05);
	fRq = filterParams[1].lag(0.05);

	sig = dry.collect({ |ch|
		signal = RLPF.ar(ch, fFreq, fRq);
		signal = BPeakEQ.ar(signal,
			freq: eqParams[2].lag(0.05),
			rq:   eqParams[4].lag(0.05),
			db:   (eqOn * eqParams[1] * eqParams[3]).lag(0.05));
		signal = BPeakEQ.ar(signal,
			freq: eqParams[6].lag(0.05),
			rq:   eqParams[8].lag(0.05),
			db:   (eqOn * eqParams[5] * eqParams[7]).lag(0.05));
		BPeakEQ.ar(signal,
			freq: eqParams[10].lag(0.05),
			rq:   eqParams[12].lag(0.05),
			db:   (eqOn * eqParams[9] * eqParams[11]).lag(0.05));
	});
	Out.ar(busSubLfProcessed, sig);
}).add;

SynthDef(\outputRouter, {
	var satSig, subMidSig, subLfSig, speakerGains, speakerMutes, groupGains, systemGain;
	var satFinal, subMidFinal, subLfFinal;
	satSig = In.ar(busSatProcessed, numSatellites);
	subMidSig = In.ar(busSubMidProcessed, numSubMid);
	subLfSig = In.ar(busSubLfProcessed, numSubLf);
	speakerGains = In.kr(speakerGainsBus, numOutputs);
	// Per-speaker mute: 1.0 mutes, 0.0 passes through. Multiplied as (1 - mute)
	// so the bus is naturally 0.0 = unmuted at boot.
	speakerMutes = In.kr(speakerMutesBus, numOutputs);
	// Per-group gain in linear factor. Slot 0=sat, 1=sub_mid, 2=sub_lf.
	groupGains = In.kr(groupGainsBus, 3);
	systemGain = In.kr(sysGainBus, 1);

	satFinal = Array.fill(numSatellites, { |i|
		satSig[i] * groupGains[0] * speakerGains[i] * (1 - speakerMutes[i]) * systemGain
	});
	subMidFinal = Array.fill(numSubMid, { |i|
		subMidSig[i] * groupGains[1] * speakerGains[i + numSatellites] * (1 - speakerMutes[i + numSatellites]) * systemGain
	});
	subLfFinal = Array.fill(numSubLf, { |i|
		subLfSig[i] * groupGains[2] * speakerGains[i + numSatellites + numSubMid] * (1 - speakerMutes[i + numSatellites + numSubMid]) * systemGain
	});

	// Per-speaker output: route each to the configured `outputChannel`.
	Array.fill(numSatellites, { |i| Out.ar(satOutCh[i], satFinal[i]) });
	Array.fill(numSubMid, { |i| Out.ar(subMidOutCh[i], subMidFinal[i]) });
	Array.fill(numSubLf, { |i| Out.ar(subLfOutCh[i], subLfFinal[i]) });

	// Speaker output meters reflect the signal that actually leaves each bus
	// (post per-speaker gain and post system gain). Write each speaker's
	// signal into the meter bus AT its outputChannel index, so the browser
	// can index `meters.speakerOuts[outputChannel]` directly regardless of
	// the layout's speaker ordering.
	Array.fill(numSatellites, { |i| Out.ar(busMetersSpeakerOuts + satOutCh[i], satFinal[i]) });
	Array.fill(numSubMid, { |i| Out.ar(busMetersSpeakerOuts + subMidOutCh[i], subMidFinal[i]) });
	Array.fill(numSubLf, { |i| Out.ar(busMetersSpeakerOuts + subLfOutCh[i], subLfFinal[i]) });
}).add;

// Dedicated meter synth: reads source inputs from SoundIn and speaker outputs
// from a shared meter bus (filled by outputRouter), computes amplitudes, and
// sends a single OSC reply per tick with the concatenated array
// `[sourceIns..., speakerOuts...]`. SendReply omits the interleaved RMS that
// SendPeakRMS would add, so the browser can index by channel directly.
SynthDef(\meters, {
	var srcAudio, spkAudio, srcAmps, spkAmps, lag = 0.1;
	// Use the configured input channel mapping so srcAmps[i] aligns with the
	// browser's `sources[i].inputChannel` regardless of how the server.json
	// orders channels.
	srcAudio = SoundIn.ar(sourceInputChannels);
	spkAudio = In.ar(busMetersSpeakerOuts, numOutputs);
	srcAmps = Amplitude.kr(srcAudio, attackTime: 0.01, releaseTime: lag);
	spkAmps = Amplitude.kr(spkAudio, attackTime: 0.01, releaseTime: lag);
	SendReply.kr(
		Impulse.kr(metersHz),
		'/akm/server/meters/raw',
		srcAmps ++ spkAmps
	);
}).add;

s.sync;
"[AKM] SynthDefs ready.".postln;
)
