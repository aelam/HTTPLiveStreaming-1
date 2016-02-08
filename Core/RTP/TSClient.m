//
//  TSClient.m
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 14..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//
//  https://en.wikipedia.org/wiki/Real_Time_Streaming_Protocol
//  http://stackoverflow.com/questions/17896008/can-ffmpeg-library-send-the-live-h264-ios-camera-stream-to-wowza-using-rtsp
//  https://github.com/goertzenator/lwip/blob/master/contrib-1.4.0/apps/rtp/rtp.c

#import "TSClient.h"
#import <CocoaAsyncSocket/CocoaAsyncSocket.h>

@interface TSClient()
{
    GCDAsyncUdpSocket *socket;
    
    dispatch_queue_t queue;
}
@end

@implementation TSClient

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        socket = [[GCDAsyncUdpSocket alloc] init];
        [socket setDelegateQueue:queue];
        self.address = nil;
        self.port = 554;
    }
    return self;
}

- (void)dealloc {
    [socket closeAfterSending];
}

#pragma mark - Publish

- (void)publish:(NSData *)data timestamp:(CMTime)timestamp
{
    dispatch_async(queue, ^{
        int32_t t = ((float)timestamp.value / timestamp.timescale) * 1000;
        
        [socket sendData:data toHost:self.address port:self.port withTimeout:-1 tag:0];
    });
}

@end
