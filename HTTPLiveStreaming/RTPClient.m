//
//  RTPClient.mm
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 14..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//
//  https://en.wikipedia.org/wiki/Real_Time_Streaming_Protocol
//  http://stackoverflow.com/questions/17896008/can-ffmpeg-library-send-the-live-h264-ios-camera-stream-to-wowza-using-rtsp
//  https://github.com/goertzenator/lwip/blob/master/contrib-1.4.0/apps/rtp/rtp.c

#import "RTPClient.h"
#import <CocoaAsyncSocket/CocoaAsyncSocket.h>

#include <string.h>

/* These macros should be calculated by the preprocessor and are used
 with compile-time constants only (so that there is no little-endian
 overhead at runtime). */
#define PP_HTONS(x) ((((x) & 0xff) << 8) | (((x) & 0xff00) >> 8))
#define PP_NTOHS(x) PP_HTONS(x)
#define PP_HTONL(x) ((((x) & 0xff) << 24) | \
                    (((x) & 0xff00) << 8) | \
                    (((x) & 0xff0000UL) >> 8) | \
                    (((x) & 0xff000000UL) >> 24))
#define PP_NTOHL(x) PP_HTONL(x)

#define PACK_STRUCT_FIELD(fld) fld

/** RTP packet/payload size */
#define RTP_PACKET_SIZE             1500
#define RTP_PAYLOAD_SIZE            1024

/** RTP header constants */
#define RTP_VERSION                 0x80
#define RTP_PAYLOADTYPE             96
#define RTP_MARKER_MASK             0x80

/** RTP message header */
struct rtp_hdr {
    PACK_STRUCT_FIELD(uint8_t  version);
    PACK_STRUCT_FIELD(uint8_t  payloadtype);
    PACK_STRUCT_FIELD(uint16_t seqNum);
    PACK_STRUCT_FIELD(uint32_t timestamp);
    PACK_STRUCT_FIELD(uint32_t ssrc);
};

@interface RTPClient() <AsyncUdpSocketDelegate>
{
    AsyncUdpSocket *socket_rtp;
    
    /** RTP packets */
    uint8_t rtp_send_packet[RTP_PACKET_SIZE];
    
    uint16_t seqNum;
}
@end

@implementation RTPClient

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        socket_rtp = [[AsyncUdpSocket alloc] initWithDelegate:self];
        self.address = nil;
        self.port = 554;
    }
    return self;
}

#pragma mark - AsyncUdpSocketDelegate

- (void)onUdpSocket:(AsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
    
}

- (void)onUdpSocket:(AsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error
{
    
}

- (BOOL)onUdpSocket:(AsyncUdpSocket *)sock didReceiveData:(NSData *)data withTag:(long)tag fromHost:(NSString *)host port:(UInt16)port
{
    return YES;
}

#pragma mark - Publish

- (void)publish:(NSData *)data timestamp:(CMTime)timestamp
{
    dispatch_async(dispatch_get_main_queue(), ^{
        struct rtp_hdr* rtphdr;
        uint8_t*        rtp_payload;
        int             rtp_payload_size;
        int             rtp_data_index;
        
        int32_t t = ((float)timestamp.value / timestamp.timescale) * 1000;
        
        /* send RTP stream packets */
        rtp_data_index = 0;
        do {
            // set data to 0
            memset(rtp_send_packet, 0, sizeof(rtp_send_packet));
            
            /* prepare RTP packet */
            rtphdr = (struct rtp_hdr*)rtp_send_packet;
            rtphdr->version     = RTP_VERSION;
            rtphdr->payloadtype = 0;
            rtphdr->ssrc        = htonl( (int32_t)self.port );
            rtphdr->seqNum      = seqNum;
            rtphdr->timestamp   = htonl( t );
            
            rtp_payload      = rtp_send_packet + sizeof(struct rtp_hdr);
            rtp_payload_size = fmin(RTP_PAYLOAD_SIZE, ([data length] - rtp_data_index));
            
            memcpy(rtp_payload, [data bytes] + rtp_data_index, rtp_payload_size);
            
            /* set MARKER bit in RTP header on the last packet of an image */
            rtphdr->payloadtype = RTP_PAYLOADTYPE | (((rtp_data_index + rtp_payload_size) >= [data length]) ? RTP_MARKER_MASK : 0);
            
            /* send RTP stream packet */
            NSData *packet = [NSData dataWithBytes:rtp_send_packet length:(rtp_payload_size + sizeof(struct rtp_hdr))];
            
            [socket_rtp sendData:packet toHost:self.address port:self.port withTimeout:-1 tag:0];
            seqNum  = htons(ntohs(rtphdr->seqNum) + 1);
            rtp_data_index += rtp_payload_size;
        }while (rtp_data_index < [data length]);
    });
}

@end
