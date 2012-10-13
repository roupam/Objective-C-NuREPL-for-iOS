#import "SPNuRemote.h"
#import "NRStats.h"

#if !TARGET_OS_IPHONE
#import <SystemConfiguration/SystemConfiguration.h>
#endif
#import <sys/sysctl.h>

//#import <Nu/Nu.h>
@interface NSObject (NuStuff)
+(id)parser;
-(void)reset;
-(id)parseEval:(NSString*)code;
@end


@interface SPNuRemote () <NSNetServiceDelegate>
@property(nonatomic,readonly) NSMutableArray *clients;
@property(nonatomic,readonly) NSMutableArray *datasets;
-(void)publishAndAvoidCollision:(BOOL)avoidCollision;

#if TARGET_OS_IPHONE
-(void)activated;
#endif
@end


@interface SPNRClient : NSObject
{
@public
	AsyncSocket *sock;
	id parser;
	SPNuRemote *parent;
	NSData *_messageSeparator;
	BOOL _statsEnabled;
	BOOL _loggingEnabled;
}
-(id)init:(AsyncSocket*)s :(SPNuRemote*)parent_;
-(void)sendInitialDatasets;

// Public API over wire
@property (retain) NSData *messageSeparator;
-(void)useETBForMessageSeparator;
@property(nonatomic) BOOL statsEnabled;
@property(nonatomic) BOOL loggingEnabled;
@end

@implementation SPNRClient
@synthesize messageSeparator = _messageSeparator;
@synthesize statsEnabled = _statsEnabled;
@synthesize loggingEnabled = _loggingEnabled;
-(id)init:(AsyncSocket*)s :(SPNuRemote*)parent_;
{
	if(!(self = [super init])) return nil;
	
	parser = [[NSClassFromString(@"Nu") parser] retain];
	if(!parser) {
		[self release];
		return nil;
	}
	
	self.messageSeparator = [NSData dataWithBytes:"\xa\xa" length:2];
	
	parent = parent_;
	sock = [s retain];
	[parser parseEval:@"(set log (NuBridgedFunction functionWithName:\"NSLog\" signature:\"v@\"))"];
	[parser setValue:self forKey:@"connection"];
	[parser setValue:parent_ forKey:@"remote"];
	
	[sock setDelegate:self];
	[sock readDataToData:self.messageSeparator withTimeout:-1 tag:0];
	
	return self;
}
-(void)dealloc;
{
	self.messageSeparator = nil;
	[sock release];
	[parser release];
	[super dealloc];
}
- (void)onSocketDidDisconnect:(AsyncSocket *)sock_;
{
	[parser parseEval:@"(set connection nil) (set remote nil)"];
	[sock release]; sock = nil;
	[parent.clients removeObject:self]; // I will be deallocated now
}
-(void)reply:(NSString*)code :(NSString*)reply;
{
	NSData *d = [[NSString stringWithFormat:@"%@\t%@", code, reply] dataUsingEncoding:NSUTF8StringEncoding];
	[sock writeData:d withTimeout:-1 tag:0];
	[sock writeData:self.messageSeparator withTimeout:-1 tag:0];
	[sock readDataToData:self.messageSeparator withTimeout:-1 tag:0];
}

-(void)replyData:(NSData*)data
{
	NSData *header = [[NSString stringWithFormat:@"201 OK data transfer\t\nContent-Length: %d", [data length]] dataUsingEncoding:NSUTF8StringEncoding];
	[sock writeData:header withTimeout:-1 tag:0];
	[sock writeData:self.messageSeparator withTimeout:-1 tag:0];
	[sock writeData:data withTimeout:-1 tag:0];
	[sock readDataToData:self.messageSeparator withTimeout:-1 tag:0];
}


- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag;
{
	data = [data subdataWithRange:NSMakeRange(0, data.length-self.messageSeparator.length)];
	NSString *cmd = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	if(!cmd) return [self reply:@"501 Bad Request" :@"Command not UTF8"];
	
	NSString *reply = nil;
	@try {
		reply = [parser parseEval:cmd];
	}
	@catch (NSException * e) {
		[self reply:@"502 Exception Thrown" :[e description]];
		[parser reset];
		return;
	}
	
	return [self reply:@"200 OK" :reply];
}
-(void)writeLogLine:(NSString*)line logLevel:(int)logLevel;
{
	if(!_loggingEnabled) return;
	
	[self reply:[NSString stringWithFormat:@"6%02d Log message", logLevel] :[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
}
-(void)addDataPoint:(float)data atTime:(NSTimeInterval)interval toDataSet:(NSString*)setName;
{
	if(!_statsEnabled) return;
	
	[self reply:@"701 New Data Point" :[NSString stringWithFormat:@"%@\n%f\n%f", 
		setName, interval, data
	]];
}
-(void)sendInitialDatasets;
{
	for(NRStats *dataset in parent.datasets) {
		NSData *data = [NSKeyedArchiver archivedDataWithRootObject:dataset.dictionaryRepresentation];
		NSData *header = [[NSString stringWithFormat:@"702 Dataset Priming\t\nSet-Name: %@\nContent-Length: %d", dataset.name, [data length]] dataUsingEncoding:NSUTF8StringEncoding];
		[sock writeData:header withTimeout:-1 tag:0];
		[sock writeData:self.messageSeparator withTimeout:-1 tag:0];
		[sock writeData:data withTimeout:-1 tag:0];
		/*for(int i = 0, c = dataset.data.count; i < c; i++)
			[self addDataPoint:[[dataset.data objectAtIndex:i] floatValue] atTime:[[dataset.times objectAtIndex:i] doubleValue] toDataSet:dataset.name];*/
	}
}
-(void)useETBForMessageSeparator;
{
	self.messageSeparator = [NSData dataWithBytes:(char[]){23} length:1];
}
-(void)setStatsEnabled:(BOOL)wantStats;
{
	_statsEnabled = wantStats;
	
	if(wantStats)
		[self sendInitialDatasets];
}
@end



@implementation SPNuRemote
@synthesize listenSocket, publisher, clients, datasets;
-(id)init;
{
	clients = [NSMutableArray new];
	datasets = [NSMutableArray new];

	return self;
}
-(void)run;
{
	if(!NSClassFromString(@"Nu") || listenSocket)
		return;

	self.listenSocket = [[[AsyncSocket alloc] initWithDelegate:self] autorelease];
	
#if TARGET_OS_IPHONE
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(activated) name:UIApplicationDidBecomeActiveNotification object:nil];
#endif
	
	NSError *err = nil;
	if(![listenSocket acceptOnPort:kNuRemotingPort error:&err]) {
		NSLog(@"SPNuRemote listen failure: %@", err);
		return;
	}
	

	[self publishAndAvoidCollision:NO];
}
-(void)dealloc;
{
	self.listenSocket = nil;
	self.publisher = nil;
	for(SPNRClient *client in clients) {
		client->parent = nil;
		[client->sock disconnect];
	}
	[clients release];
	[datasets release];
	[super dealloc];
}
-(void)activated;
{
	[self.publisher stop];
	listenSocket.delegate = nil;
	[listenSocket disconnect];
	listenSocket.delegate = self;
	NSError *err = nil;
	if(![listenSocket acceptOnPort:kNuRemotingPort error:&err])
		NSLog(@"SPNuRemote listen failure: %@", err);
	else
		[self publishAndAvoidCollision:NO];
}


- (void)onSocket:(AsyncSocket *)sock didAcceptNewSocket:(AsyncSocket *)newSocket;
{
    SPNRClient *client = [[SPNRClient alloc] init:newSocket :self];
    [client setLoggingEnabled:YES];
    [client setStatsEnabled:YES];
	[clients addObject:[client autorelease]];
}
- (void)onSocketDidDisconnect:(AsyncSocket *)sock;
{
	self.listenSocket = nil;
	self.publisher = nil;
	[self activated];
}

-(void)writeLogLine:(NSString *)line logLevel:(int)level;
{
	for(SPNRClient *client in clients)
		[client writeLogLine:line logLevel:level];
}

-(NRStats*)statsNamed:(NSString*)name;
{
	for(NRStats *stats in datasets)
		if([stats.name isEqual:name]) return stats;
	NRStats *stats = [[[NRStats alloc] initWithName:name] autorelease];
	[[self mutableArrayValueForKey:@"datasets"] addObject:stats];
	return stats;
}

-(void)addDataPoint:(float)data toDataSet:(NSString*)setName;
{
	NRStats *stats = [self statsNamed:setName];

	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	
	[stats addPoint:data atTime:now];
	
	for(SPNRClient *client in clients)
		[client addDataPoint:data atTime:now toDataSet:setName];
}

#pragma mark Bonjour
-(void)publishAndAvoidCollision:(BOOL)avoidCollision;
{
	NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
	
#if TARGET_IPHONE_SIMULATOR
	char buf[512];
	size_t buf_size = sizeof(buf) - 1;
	sysctlbyname("kern.hostname", buf, &buf_size, NULL, 0);
	NSString *deviceName = [NSString stringWithUTF8String:buf];
#elif TARGET_OS_IPHONE
	NSString *deviceName = [UIDevice currentDevice].name;
#else
	SCDynamicStoreRef dynstore = SCDynamicStoreCreate(kCFAllocatorSystemDefault, (CFStringRef)appName, nil, nil);
	NSDictionary *computerNameEntry = [(id)SCDynamicStoreCopyValue(dynstore,(CFStringRef)@"Setup:/System") autorelease];
	CFRelease(dynstore);
	NSString *deviceName = [computerNameEntry objectForKey:@"ComputerName"];
#endif
	
	NSString *collisionAvoidance = @"";
	if(avoidCollision) {
		NSArray *components = [self.publisher.name componentsSeparatedByString:@" "];
		int v = [[components lastObject] intValue];
		collisionAvoidance = [NSString stringWithFormat:@" %d", v + 1];
	}
	
	NSString *pubName = [NSString stringWithFormat:@"%@: %@%@",
		deviceName,
		appName,
		collisionAvoidance
	];
	
	[self.publisher stop];
	self.publisher = [[[NSNetService alloc] initWithDomain:@"" type:kNuRemotingBonjourType name:pubName	port:kNuRemotingPort] autorelease];
	self.publisher.delegate = self;
	[self.publisher publish];
}

/* Sent to the NSNetService instance's delegate when the publication of the instance is complete and successful.
*/
- (void)netServiceDidPublish:(NSNetService *)sender;
{
	NSLog(@"SPNuRemote successfully published");
}

/* Sent to the NSNetService instance's delegate when an error in publishing the instance occurs. The error dictionary will contain two key/value pairs representing the error domain and code (see the NSNetServicesError enumeration above for error code constants). It is possible for an error to occur after a successful publication.
*/
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict;
{
	NSLog(@"SPNuRemote failed to publish: %@", errorDict);
	
	if([[errorDict valueForKey:NSNetServicesErrorCode] intValue] == NSNetServicesCollisionError)
		[self publishAndAvoidCollision:YES];
}

/* Sent to the NSNetService instance's delegate when an error in resolving the instance occurs. The error dictionary will contain two key/value pairs representing the error domain and code (see the NSNetServicesError enumeration above for error code constants).
*/
- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict;
{
	NSLog(@"SPNuRemote resolution failed: %@", errorDict);
}

@end
