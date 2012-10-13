#import <Foundation/Foundation.h>
#import "AsyncSocket.h"
#import "Shared.h"

/**
	@class SPNuRemote
	@abstract Starts a server that acts as a remote Nu (http://programming.nu)
	          console, for introspecting your application over the network.
	
	By default, to talk to a SPNuRemote instance, you send raw Nu code separated by
	double newlines to its socket on port 8023. The service is also announced over Bonjour
	as _nuremote._tcp.
	
	Incoming messages are formatted thusly:
	[Code] [human-readable code description]\t[reply][message separator]
	
	where Code is:
	- 501 Bad Request: [reply] is reason.
	- 502 Exception Thrown: [reply] is exception description
	- 200 OK: [reply] is Nu response
	- 6xx Log message: [reply] is a log message, x is a verbosity level, as sent to -[writeLogLine:logLevel:]
	
	In addition, there are some odd messages, formatted like this:
	- 201 OK data transfer\t\nContent-Length: [length][message separator][data of length 'length']
	  (see replyData for description)
	- 701 New Data Point\n[name]\n[time]\n[data][message separator]
	   Data, as sent to -[addDataPoint:toDataSet], where [name] is the dataset name, 
	   [time] is the time the data was sent, and [data] is a floating-point datum.
	- 702 Dataset Priming\t\nSet-Name: [name]\nContent-Length: [length][message separator][data of length 'length']
	   Receive some of the data collected before you connected. The data is
	   an NSKeyedArchive of an NSDictionary of time:datum pairs for the given sset.
	  
	
	
	If you are using code to talk to SPNuRemote, you might want to change some protocol settings.
	You send these as ordinary Nu code. Available settings:
	- (connection setMessageSeparator:(NSData ...)) # Change message separator
	- (connection useETBForMessageSeparator) # Specifically switch to ascii 23 for separator
	- (connection setStatsEnabled:1)        # Enable stats
	- (connection setLoggingEnabled:1)      # Enable receiving log messages
	
	
	If you are writing a Nu script and want to send some data back to the controlling
	socket (e g a screenshot), you can use the following command to send a 201 message:
	(connection replyData:(NSData ...))

	
	@see RemotingClient for talking to an SPNuRemote from a Cocoa application.
	
*/
@interface SPNuRemote : NSObject
@property (retain) AsyncSocket *listenSocket;
@property (retain) NSNetService *publisher;
-(void)run;

-(void)writeLogLine:(NSString*)line logLevel:(int)level;

-(void)addDataPoint:(float)data toDataSet:(NSString*)setName;
@end

