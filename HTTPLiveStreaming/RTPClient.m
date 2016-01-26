//
//  RTPClient.mm
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 14..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//
//  https://en.wikipedia.org/wiki/Real_Time_Streaming_Protocol
//  http://stackoverflow.com/questions/17896008/can-ffmpeg-library-send-the-live-h264-ios-camera-stream-to-wowza-using-rtsp

#import "RTPClient.h"
#import <CocoaAsyncSocket/CocoaAsyncSocket.h>

typedef struct rtp_header {
    /* little-endian */
    /* byte 0 */
    uint8_t csrc_len:       4;  /* bit: 0~3 */
    uint8_t extension:      1;  /* bit: 4 */
    uint8_t padding:        1;  /* bit: 5*/
    uint8_t version:        2;  /* bit: 6~7 */
    /* byte 1 */
    uint8_t payload_type:   7;  /* bit: 0~6 */
    uint8_t marker:         1;  /* bit: 7 */
    /* bytes 2, 3 */
    uint16_t seq_no;
    /* bytes 4-7 */
    uint32_t timestamp;
    /* bytes 8-11 */
    uint32_t ssrc;
} __attribute__ ((packed)) rtp_header_t; /* 12 bytes */

typedef struct rtp_package {
    rtp_header_t rtp_package_header;
    uint8_t *rtp_load;
} rtp_t;

#define H264        96

#define SEND_BUF_SIZE               1500
#define SSRC_NUM                    10

@interface RTPClient() <AsyncSocketDelegate, AsyncUdpSocketDelegate>
{
    int cseq;
    
    AsyncUdpSocket *socket_rtp;
    
    uint8_t SENDBUFFER[SEND_BUF_SIZE];
}
@end

@implementation RTPClient

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        cseq = 0;
        
        socket_rtp = [[AsyncUdpSocket alloc] initWithDelegate:self];
        self.address = nil;
        self.port = 0;
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

#pragma mark - Connection Handshake

- (void)connect:(NSString *)address port:(NSInteger)port
{
    self.address = address;
    self.port = port;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error;
        [socket_rtp connectToHost:self.address onPort:self.port error:&error];
        if(error != nil)
        {
            NSLog(@"%@", [error localizedDescription]);
        }
    });
}

- (void)close
{
    [socket_rtp close];
    self.address = nil;
    self.port = 0;
}

#pragma mark - AsyncUdpSocketDelegate

- (BOOL)onUdpSocket:(AsyncUdpSocket *)sock didReceiveData:(NSData *)data withTag:(long)tag fromHost:(NSString *)host port:(UInt16)port
{
    return YES;
}

#pragma mark - Publish

- (void)publish:(NSData *)data timestamp:(CMTime)timestamp
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if(socket_rtp == nil || !socket_rtp.isConnected) return;
        
        rtp_header_t rtp_hdr;
        
        rtp_hdr.csrc_len = 0;
        rtp_hdr.extension = 0;
        rtp_hdr.padding = 0;
        rtp_hdr.version = 2;
        rtp_hdr.payload_type = H264;
        rtp_hdr.seq_no = htons(cseq++ % UINT16_MAX);
        rtp_hdr.timestamp = htonl(timestamp.value);
        rtp_hdr.ssrc = htonl(SSRC_NUM);
        
        struct rtp_package rtp_pkg;
        
        rtp_pkg.rtp_package_header = rtp_hdr;
        rtp_pkg.rtp_load = (u_int8_t *)[data bytes];
        
        NSData *packet = [NSData dataWithBytes:&rtp_pkg length:sizeof(rtp_pkg)];
        [socket_rtp sendData:packet toHost:self.address port:self.port withTimeout:-1 tag:0];
    });
}

@end
