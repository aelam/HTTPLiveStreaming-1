//
//  RTSPClient.h
//  HTTPLiveStreaming
//
//  Created by Byeong-uk Park on 2016. 1. 26..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import <CoreMedia/CoreMedia.h>

@class RTSPClient;

@protocol RTSPClientDelegate <NSObject>
- (void)onRTSPDidConnectedOK:(RTSPClient *)rtsp;
- (void)onRTSPDidConnectedFailed:(RTSPClient *)rtsp;
- (void)onRTSPDidDisConnected:(RTSPClient *)rtsp;
- (void)onRTSP:(RTSPClient *)rtsp didSETUP_AUDIOWithServerPort:(NSInteger)server_port;
- (void)onRTSP:(RTSPClient *)rtsp didSETUP_VIDEOWithServerPort:(NSInteger)server_port;
@end

@interface RTSPClient : NSObject

@property (weak, nonatomic) NSString *address;
@property (nonatomic) int32_t port;
@property (weak, nonatomic) NSString *streamName;
@property (weak, nonatomic) NSString *sessionid;
@property (weak, nonatomic) id<RTSPClientDelegate> delegate;

- (void)connect:(NSString *)address port:(NSInteger)port stream:(NSString *)stream;
- (void)close;

@end
