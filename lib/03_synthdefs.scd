(
var satX, satY, satZ, satOutCh;
var subMidX, subMidY, subMidZ, subMidOutCh;
var subLfX, subLfY, subLfZ, subLfOutCh;
var centroidX, centroidY, centroidZ, satMaxRadius, cSoundSpeed;
var numSatellites, numSubMid, numSubLf, numOutputs, numSources, numSourceParams, numEqParams;
var satFilterBus, satEqBus, subMidFilterBus, subMidEqBus, subLfFilterBus, subLfEqBus;
var sysReverbBus, subMidReverbBus, sysGainBus, speakerGainsBus;
var busSatDry, busSatPre, busSatPost, busSatProcessed;
var busSubMidDry, busSubMidPre, busSubMidPost, busSubMidProcessed;
var busSubLfDry, busSubLfProcessed;
var metersHz, satAllpassDelays, subMidAllpassDelays;

"[AKM] adding SynthDefs...".postln;

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
numSourceParams = ~numSourceParameters;
numEqParams = ~numEQParameters;

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

metersHz = ~telemetryMetersHz;
satAllpassDelays = { 0.050.rand } ! numSatellites;
subMidAllpassDelays = { 0.050.rand } ! numSubMid;

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
	satGains = Array.fill(numSatellites, { |i|
		(satWeights[i] * satNorm) * (satDist[i] < sourceRadius)
	});
	satDelays = satDist.collect({ |d| (d / cSoundSpeed) * delayLevel });

	subMidDist = Array.fill(numSubMid, { |i|
		(((posX - subMidX[i]).squared + (posY - subMidY[i]).squared + (posZ - subMidZ[i]).squared).sqrt + 0.00001)
	});
	subMidWeights = subMidDist.collect({ |d| d.pow(exponentA.neg) });
	subMidNorm = (subMidWeights.collect({ |w| w.squared }).sum + 1e-9).sqrt.reciprocal;
	subMidGains = Array.fill(numSubMid, { |i|
		(subMidWeights[i] * subMidNorm) * (subMidDist[i] < sourceRadius)
	});
	subMidDelays = subMidDist.collect({ |d| (d / cSoundSpeed) * delayLevel });

	subLfDist = Array.fill(numSubLf, { |i|
		(((posX - subLfX[i]).squared + (posY - subLfY[i]).squared + (posZ - subLfZ[i]).squared).sqrt + 0.00001)
	});
	subLfWeights = subLfDist.collect({ |d| d.pow(exponentA.neg) });
	subLfNorm = (subLfWeights.collect({ |w| w.squared }).sum + 1e-9).sqrt.reciprocal;
	subLfGains = Array.fill(numSubLf, { |i|
		(subLfWeights[i] * subLfNorm) * (subLfDist[i] < sourceRadius)
	});
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
	attenuation = In.kr(attenuationBus, 1);

	satGains = In.kr(satGainBus, numSatellites);
	satDelays = In.kr(satDelayBus, numSatellites);
	satDry = Array.fill(numSatellites, { |i|
		DelayC.ar(
			in: satGains[i] * audioIn * attenuation,
			maxdelaytime: 3.0,
			delaytime: satDelays[i].squared
		)
	});
	satWet = satDry * reverbMix;

	subMidGains = In.kr(subMidGainBus, numSubMid);
	subMidDelays = In.kr(subMidDelayBus, numSubMid);
	subMidDry = Array.fill(numSubMid, { |i|
		DelayC.ar(
			in: subMidGains[i] * audioIn * attenuation,
			maxdelaytime: 3.0,
			delaytime: subMidDelays[i].squared
		)
	});
	subMidWet = subMidDry * reverbMix;

	subLfGains = In.kr(subLfGainBus, numSubLf);
	subLfDelays = In.kr(subLfDelayBus, numSubLf);
	subLfDry = Array.fill(numSubLf, { |i|
		DelayC.ar(
			in: subLfGains[i] * audioIn * attenuation,
			maxdelaytime: 3.0,
			delaytime: subLfDelays[i].squared
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

	signals = In.ar(busSatPre, numSatellites);
	signals = OnePole.ar(signals, 0.72);
	signals = AllpassC.ar(signals, 0.3, LFNoise1.kr(1).range(0.03, 0.029), 3);

	fbk = LocalIn.ar(numSatellites);
	if(numSatellites > 1) { fbk = fbk.scramble };
	fbk = OnePole.ar(fbk, 0.2);
	fbk = fbk + signals;
	7.do({ fbk = AllpassN.ar(fbk, 0.05, satAllpassDelays, decay) });
	LocalOut.ar(fbk * feedback);
	Out.ar(busSatPost, fbk);
}).add;

SynthDef(\subMidReverbFX, {
	var signals, fbk, sysParams, subParams, decay, feedback, enabled, mix;
	sysParams = In.kr(sysReverbBus, 2);
	subParams = In.kr(subMidReverbBus, 2);
	decay = sysParams[0].clip(0.0, 5.0);
	feedback = sysParams[1].clip(0.0, 0.99);
	enabled = subParams[0].clip(0.0, 1.0);
	mix = subParams[1].clip(0.0, 1.0);

	signals = In.ar(busSubMidPre, numSubMid) * enabled * mix;
	signals = OnePole.ar(signals, 0.72);
	signals = AllpassC.ar(signals, 0.3, LFNoise1.kr(1).range(0.03, 0.029), 2);

	fbk = LocalIn.ar(numSubMid);
	if(numSubMid > 1) { fbk = fbk.scramble };
	fbk = OnePole.ar(fbk, 0.2);
	fbk = fbk + signals;
	5.do({ fbk = AllpassN.ar(fbk, 0.05, subMidAllpassDelays, decay) });
	LocalOut.ar(fbk * feedback);
	Out.ar(busSubMidPost, fbk);
}).add;

SynthDef(\groupSatFilterEq, {
	var dry, wet, sig, filterParams, eqParams, eqOn, signal;
	dry = In.ar(busSatDry, numSatellites);
	wet = In.ar(busSatPost, numSatellites);
	filterParams = In.kr(satFilterBus, 2);
	eqParams = In.kr(satEqBus, numEqParams);
	eqOn = eqParams[0];

	sig = (dry + wet).collect({ |ch|
		signal = RHPF.ar(ch, filterParams[0], filterParams[1]);
		signal = BLowShelf.ar(signal, freq: eqParams[2], rs: eqParams[4], db: eqOn * eqParams[1] * eqParams[3]);
		signal = BPeakEQ.ar(signal, freq: eqParams[6], rq: eqParams[8], db: eqOn * eqParams[5] * eqParams[7]);
		signal = BPeakEQ.ar(signal, freq: eqParams[10], rq: eqParams[12], db: eqOn * eqParams[9] * eqParams[11]);
		signal = BPeakEQ.ar(signal, freq: eqParams[14], rq: eqParams[16], db: eqOn * eqParams[13] * eqParams[15]);
		BHiShelf.ar(signal, freq: eqParams[18], rs: eqParams[20], db: eqOn * eqParams[17] * eqParams[19]);
	});
	Out.ar(busSatProcessed, sig);
}).add;

SynthDef(\groupSubMidFilterEq, {
	var dry, wet, sig, filterParams, eqParams, eqOn, signal;
	dry = In.ar(busSubMidDry, numSubMid);
	wet = In.ar(busSubMidPost, numSubMid);
	filterParams = In.kr(subMidFilterBus, 2);
	eqParams = In.kr(subMidEqBus, numEqParams);
	eqOn = eqParams[0];

	sig = (dry + wet).collect({ |ch|
		signal = RLPF.ar(ch, filterParams[0], filterParams[1]);
		signal = BLowShelf.ar(signal, freq: eqParams[2], rs: eqParams[4], db: eqOn * eqParams[1] * eqParams[3]);
		signal = BPeakEQ.ar(signal, freq: eqParams[6], rq: eqParams[8], db: eqOn * eqParams[5] * eqParams[7]);
		signal = BPeakEQ.ar(signal, freq: eqParams[10], rq: eqParams[12], db: eqOn * eqParams[9] * eqParams[11]);
		signal = BPeakEQ.ar(signal, freq: eqParams[14], rq: eqParams[16], db: eqOn * eqParams[13] * eqParams[15]);
		BHiShelf.ar(signal, freq: eqParams[18], rs: eqParams[20], db: eqOn * eqParams[17] * eqParams[19]);
	});
	Out.ar(busSubMidProcessed, sig);
}).add;

SynthDef(\groupSubLfFilterEq, {
	var dry, sig, filterParams, eqParams, eqOn, signal;
	dry = In.ar(busSubLfDry, numSubLf);
	filterParams = In.kr(subLfFilterBus, 2);
	eqParams = In.kr(subLfEqBus, numEqParams);
	eqOn = eqParams[0];

	sig = dry.collect({ |ch|
		signal = RLPF.ar(ch, filterParams[0], filterParams[1]);
		signal = BLowShelf.ar(signal, freq: eqParams[2], rs: eqParams[4], db: eqOn * eqParams[1] * eqParams[3]);
		signal = BPeakEQ.ar(signal, freq: eqParams[6], rq: eqParams[8], db: eqOn * eqParams[5] * eqParams[7]);
		signal = BPeakEQ.ar(signal, freq: eqParams[10], rq: eqParams[12], db: eqOn * eqParams[9] * eqParams[11]);
		signal = BPeakEQ.ar(signal, freq: eqParams[14], rq: eqParams[16], db: eqOn * eqParams[13] * eqParams[15]);
		BHiShelf.ar(signal, freq: eqParams[18], rs: eqParams[20], db: eqOn * eqParams[17] * eqParams[19]);
	});
	Out.ar(busSubLfProcessed, sig);
}).add;

SynthDef(\outputRouter, {
	var satSig, subMidSig, subLfSig, speakerGains, systemGain, allSignals;
	satSig = In.ar(busSatProcessed, numSatellites);
	subMidSig = In.ar(busSubMidProcessed, numSubMid);
	subLfSig = In.ar(busSubLfProcessed, numSubLf);
	speakerGains = In.kr(speakerGainsBus, numOutputs);
	systemGain = In.kr(sysGainBus, 1);

	allSignals = (satSig ++ subMidSig ++ subLfSig);
	SendPeakRMS.ar(allSignals, replyRate: metersHz, peakLag: 3, cmdName: '/akm/server/meters/raw');

	Array.fill(numSatellites, { |i|
		Out.ar(satOutCh[i], satSig[i] * speakerGains[i] * systemGain)
	});
	Array.fill(numSubMid, { |i|
		Out.ar(subMidOutCh[i], subMidSig[i] * speakerGains[i + numSatellites] * systemGain)
	});
	Array.fill(numSubLf, { |i|
		Out.ar(subLfOutCh[i], subLfSig[i] * speakerGains[i + numSatellites + numSubMid] * systemGain)
	});
}).add;

s.sync;
"[AKM] SynthDefs ready.".postln;
)
