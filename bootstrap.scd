(
var baseDir, layoutPath, serverPath;

baseDir = thisProcess.nowExecutingPath.dirname;
layoutPath = thisProcess.argv.at(0);
serverPath = thisProcess.argv.at(1);

if(layoutPath.isNil) {
	layoutPath = baseDir +/+ "../packages/akm-config/venues/main/layout.json";
};

if(serverPath.isNil) {
	serverPath = baseDir +/+ "../packages/akm-config/venues/main/server.json";
};

layoutPath = layoutPath.standardizePath;
serverPath = serverPath.standardizePath;

~akmBaseDir = baseDir;
~layoutPath = layoutPath;
~serverPath = serverPath;

(baseDir +/+ "lib/07_util.scd").load;
(baseDir +/+ "lib/00_config.scd").load;
(baseDir +/+ "lib/01_server_options.scd").load;

"[AKM] booting server...".postln;

s = Server.default;
s.waitForBoot({
	(baseDir +/+ "lib/02_buses.scd").load;
	(baseDir +/+ "lib/03_synthdefs.scd").load;
	(baseDir +/+ "lib/04_groups.scd").load;
	(baseDir +/+ "lib/05_synths.scd").load;
	(baseDir +/+ "lib/06_osc.scd").load;

	"--------------------------------------------------------".postln;
	"AKM SERVER READY".postln;
	~oscSendNetAddr.sendMsg("/akm/server/ready", 1);
	"--------------------------------------------------------".postln;
});
)
