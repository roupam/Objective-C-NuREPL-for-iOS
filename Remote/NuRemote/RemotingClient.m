//
//  RemotingClient.m
//  NuRemoter
//
//  Created by Joachim Bengtsson on 2011-03-22.
//  Copyright 2011 Spotify AB. All rights reserved.
//

#import "RemotingClient.h"

@interface RemotingClient ()
@property(nonatomic,readwrite,retain) AsyncSocket *socket;
@property(nonatomic,copy) NSString *incomingDatasetName;
@property(nonatomic,copy) NSData *messageSeparator;
@end

typedef enum {
	kReadingCommand = 0,
	kReadingData = 1,
	kReadingDatasetPriming = 2,
} ReadingType;

NSDictionary *SPKeyValueStringToDict(NSString *kvString);
NSDictionary *SPKeyValueStringToDict(NSString *kvString) {
	NSArray *lines = [kvString componentsSeparatedByString:@"\n"];
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:[lines count]];
	for (NSString *line in lines) {
		NSArray *keyAndValue = [line componentsSeparatedByString:@":"];
		if([keyAndValue count] != 2) continue;
		NSString *key = [[keyAndValue objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *value = [[keyAndValue objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		[dict setObject:value forKey:key];
	}
	return dict;
}

@implementation RemotingClient
@synthesize delegate = _delegate, socket, name, incomingDatasetName, messageSeparator;

+(void)performSearchOnBrowser:(NSNetServiceBrowser*)browser;
{
	[browser searchForServicesOfType:kNuRemotingBonjourType inDomain:@""];
}
-(id)initWithService:(NSNetService*)service error:(NSError**)err;
{
	self.messageSeparator = [NSData dataWithBytes:"\xa\xa" length:2];
	
	self.socket = [[[AsyncSocket alloc] initWithDelegate:self] autorelease];
	[self.socket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];

	if(![socket connectToAddress:[service.addresses objectAtIndex:0] error:err]) {
		[self release];
		return nil;
	}
	
	self.name = service.name;
	delegateResponseMap = [NSMutableDictionary new];
	
	return self;
}
-(id)initWithHost:(NSString*)host port:(int)port error:(NSError**)err;
{
	self.messageSeparator = [NSData dataWithBytes:"\xa\xa" length:2];
	
	self.socket = [[[AsyncSocket alloc] initWithDelegate:self] autorelease];
	[self.socket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];

	if(![socket connectToHost:host onPort:port error:err]) {
		[self release];
		return nil;
	}
	
	self.name = host;
	delegateResponseMap = [NSMutableDictionary new];
	
	return self;

}
-(void)dealloc;
{
	self.messageSeparator = nil;
	self.socket.delegate = nil;
	self.socket = nil;
	[delegateResponseMap release]; delegateResponseMap = nil;
	[super dealloc];
}

#define MapResponse(sel) [delegateResponseMap setObject:[NSNumber numberWithBool:[_delegate respondsToSelector:@selector(sel)]] forKey:NSStringFromSelector(@selector(sel))];
#define DelegateResponds(sel) [[delegateResponseMap objectForKey:NSStringFromSelector(@selector(sel))] boolValue]
-(void)setDelegate:(id<RemotingClientDelegate>)delegate;
{
	_delegate = delegate;
	MapResponse(remotingClient:receivedOutput:withStatusCode:);
	MapResponse(remotingClient:receivedData:);
	MapResponse(remotingClient:receivedPoint:at:inSet:);
	MapResponse(remotingClientConnected:);
	MapResponse(remotingClient:willDisconnectWithError:);
	MapResponse(remotingClientDisconnected:);
}



- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err;
{
	if(DelegateResponds(remotingClient:willDisconnectWithError:))
		[_delegate remotingClient:self willDisconnectWithError:err];
}
- (void)onSocketDidDisconnect:(AsyncSocket *)sock
{
	if(DelegateResponds(remotingClientDisconnected:))
		[_delegate remotingClientDisconnected:self];
	self.socket = nil;
}
- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
	[self sendCommand:@"(connection useETBForMessageSeparator)"];
	self.messageSeparator = [NSData dataWithBytes:(char[]){23} length:1];
	[socket readDataToData:self.messageSeparator withTimeout:-1 tag:kReadingCommand];
	
	if(DelegateResponds(remotingClient:receivedOutput:withStatusCode:))
		[_delegate remotingClient:self receivedOutput:@"Enabling logging and stats...." withStatusCode:1];
	[self sendCommand:@"(connection setLoggingEnabled:1)"];
	[self sendCommand:@"(connection setStatsEnabled:1)"];
	
	if(DelegateResponds(remotingClientConnected:))
		[_delegate remotingClientConnected:self];
}
- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	if(tag == kReadingCommand) {
		data = [data subdataWithRange:NSMakeRange(0, data.length-self.messageSeparator.length)];

		NSString *cmd = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSString *code = [cmd substringToIndex:[cmd rangeOfString:@" "].location];
		NSRange r;
		r.location = [cmd rangeOfString:@"\t"].location + 1;
		r.length = [cmd length]-r.location;
		NSString *output = [cmd substringWithRange:r];
		
		if(SPRemoteHasDataAttachment([code intValue])) {
			NSDictionary *settings = SPKeyValueStringToDict(output);
			int length = [[settings objectForKey:@"Content-Length"] intValue];
			
			if([code intValue] == RemotingStatusStatsPriming) {
				self.incomingDatasetName = [settings objectForKey:@"Set-Name"];
				if(DelegateResponds(remotingClient:receivedOutput:withStatusCode:))
					[_delegate remotingClient:self receivedOutput:[NSString stringWithFormat:@"Receiving %d bytes of stats...", length] withStatusCode:[code intValue]];
				
				[socket readDataToLength:length withTimeout:-1 tag:kReadingDatasetPriming];
			} else if([code intValue] == RemotingDataReply) {
				if(DelegateResponds(remotingClient:receivedOutput:withStatusCode:))
					[_delegate remotingClient:self receivedOutput:[NSString stringWithFormat:@"Receiving %d bytes of data...", length] withStatusCode:[code intValue]];
				[socket readDataToLength:length withTimeout:-1 tag:kReadingData];
			}
		} else if([code intValue] == RemotingStatusStatsNewDataPoint) {
			if(DelegateResponds(remotingClient:receivedPoint:at:inSet:)) {
				NSArray *components = [output componentsSeparatedByString:@"\n"];
				NSAssert([components count] == 3, @"Missing component in data set");
				
				[_delegate remotingClient:self
					receivedPoint:[[components objectAtIndex:2] floatValue]
					at:[[components objectAtIndex:1] doubleValue]
					inSet:[components objectAtIndex:0]
				];
			}
			[socket readDataToData:self.messageSeparator withTimeout:-1 tag:kReadingCommand];

		} else {
			if(DelegateResponds(remotingClient:receivedOutput:withStatusCode:))
				[_delegate remotingClient:self receivedOutput:output withStatusCode:[code intValue]];
			[socket readDataToData:self.messageSeparator withTimeout:-1 tag:kReadingCommand];
		}
		
	} else if (tag == kReadingData) {
		if(DelegateResponds(remotingClient:receivedOutput:withStatusCode:))
			[_delegate remotingClient:self receivedOutput:[NSString stringWithFormat:@"Received %d bytes of data.", [data length]] withStatusCode:201];
		if(DelegateResponds(remotingClient:receivedData:))
			[_delegate remotingClient:self receivedData:data];
		[socket readDataToData:self.messageSeparator withTimeout:-1 tag:kReadingCommand];
	} else if (tag == kReadingDatasetPriming) {
		NSDictionary *primedStats = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		if(DelegateResponds(remotingClient:receivedOutput:withStatusCode:))
			[_delegate remotingClient:self receivedOutput:[NSString stringWithFormat:@"Primed %@ with %d data points.", self.incomingDatasetName, [primedStats count]] withStatusCode:201];
		
		if(DelegateResponds(remotingClient:receivedPoint:at:inSet:))
			for(NSNumber *when in [[primedStats allKeys] sortedArrayUsingSelector:@selector(compare:)])
				[_delegate remotingClient:self receivedPoint:[[primedStats objectForKey:when] floatValue] at:[when floatValue] inSet:self.incomingDatasetName];
		
		self.incomingDatasetName = nil;

		[socket readDataToData:self.messageSeparator withTimeout:-1 tag:kReadingCommand];
	}
}
-(void)sendCommand:(NSString*)commands;
{
	NSMutableData *data = [NSMutableData data];
	[data appendData:[commands dataUsingEncoding:NSUTF8StringEncoding]];
	[data appendData:self.messageSeparator];
	[socket writeData:data withTimeout:-1 tag:0];
}


@end
