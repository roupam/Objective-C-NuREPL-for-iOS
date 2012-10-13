//
//  RemotingClient.h
//  NuRemoter
//
//  Created by Joachim Bengtsson on 2011-03-22.
//  Copyright 2011 Spotify AB. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AsyncSocket.h"
#import "Shared.h"


@class RemotingClient;
@protocol RemotingClientDelegate <NSObject>
@optional
-(void)remotingClient:(RemotingClient*)client receivedOutput:(NSString*)output withStatusCode:(int)code;
-(void)remotingClient:(RemotingClient*)client receivedData:(NSData*)output;
-(void)remotingClient:(RemotingClient*)client receivedPoint:(float)pt at:(NSTimeInterval)sinceRef inSet:(NSString*)datasetName;

-(void)remotingClientConnected:(RemotingClient*)client;
-(void)remotingClient:(RemotingClient*)client willDisconnectWithError:(NSError*)err;
-(void)remotingClientDisconnected:(RemotingClient*)client;
@end


@interface RemotingClient : NSObject {
	id<RemotingClientDelegate> _delegate;
	AsyncSocket *socket;
	NSString *name;
	NSString *incomingDatasetName;
	NSMutableDictionary *delegateResponseMap;
	NSData *messageSeparator;
}
@property(nonatomic,assign) id<RemotingClientDelegate> delegate;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,readonly,retain) AsyncSocket *socket;
+(void)performSearchOnBrowser:(NSNetServiceBrowser*)browser;
-(id)initWithService:(NSNetService*)service error:(NSError**)err;
-(id)initWithHost:(NSString*)host port:(int)port error:(NSError**)err;

-(void)sendCommand:(NSString*)commands;
@end
