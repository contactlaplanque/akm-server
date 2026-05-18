~akmReadJSON = { |path|
	var normalized = path.standardizePath;
	var content, parsed;

	if(File.exists(normalized).not) {
		Error("[AKM] missing JSON file: " ++ normalized).throw;
	};

	content = File.readAllString(normalized);
	parsed = JSONlib.convertToSC(content, useEvent: true, postWarnings: false);
	parsed;
};

~akmAssert = { |condition, message|
	if(condition.not) {
		Error("[AKM] " ++ message).throw;
	};
};

~akmDistance = { |pointA, pointB|
	var vx, vy, vz;
	vx = pointB[0] - pointA[0];
	vy = pointB[1] - pointA[1];
	vz = pointB[2] - pointA[2];
	(vx.squared + vy.squared + vz.squared).sqrt;
};

~akmCentroid = { |points|
	var sum = [0.0, 0.0, 0.0];
	points.do({ |p|
		sum = [sum[0] + p[0], sum[1] + p[1], sum[2] + p[2]];
	});
	[sum[0] / points.size, sum[1] / points.size, sum[2] / points.size];
};

~akmMaxRadius = { |points, center|
	var radii = points.collect({ |p| ~akmDistance.value(center, p) });
	if(radii.isEmpty) { 1.0 } { radii.sort.last };
};

~akmDbToFactor = { |val|
	10.0 ** (val / 20.0);
};
