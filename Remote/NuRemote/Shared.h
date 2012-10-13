static NSString *const kNuRemotingBonjourType = @"_nuremote._tcp.";
static const int kNuRemotingPort = 8023;

enum RemotingStatusCodes {
	RemotingStatusClassSuccess = 200,
	
	RemotingStatusOK = RemotingStatusClassSuccess + 0,
	RemotingDataReply = RemotingStatusClassSuccess + 1,
	
	RemotingStatusClassError = 500,
	
	RemotingStatusException = RemotingStatusClassError + 0,
	RemotingStatusBadRequest = RemotingStatusClassError + 1,
	
	RemotingStatusClassLog = 600,
	RemotingStatusLogFatal = RemotingStatusClassLog + 0,
	RemotingStatusLogAssertionFailure = RemotingStatusClassLog + 1,
	RemotingStatusLogAssertionError = RemotingStatusClassLog + 2,
	RemotingStatusLogAssertionWarning = RemotingStatusClassLog + 3,
	RemotingStatusLogAssertionInfo = RemotingStatusClassLog + 4,
	RemotingStatusLogAssertionSpam = RemotingStatusClassLog + 5,
	RemotingStatusLogAssertionDebug = RemotingStatusClassLog + 6,
	
	RemotingStatusClassStats = 700,
	RemotingStatusStatsNewDataPoint = RemotingStatusClassStats + 1,
	RemotingStatusStatsPriming = RemotingStatusClassStats + 2,
	
	
};

static inline BOOL SPRemoteHasDataAttachment(int code) {
	return code == RemotingDataReply || code == RemotingStatusStatsPriming;
}