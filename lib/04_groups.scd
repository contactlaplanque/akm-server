(
"[AKM] creating groups...".postln;

~sourcesSpatPannersGroup = Group.new(s.defaultGroup, \addToTail);
~sourcesInputProcessingGroup = Group.new(s.defaultGroup, \addToTail);
~fxGroup = Group.new(s.defaultGroup, \addToTail);
~reverbGroup = Group.new(~fxGroup, \addToTail);
~filtersEqGroup = Group.new(~fxGroup, \addToTail);
~outputGroup = Group.new(~fxGroup, \addToTail);

s.sync;
"[AKM] groups ready.".postln;
)
