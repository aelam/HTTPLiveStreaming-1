//
//  TSClient.mm
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 14..
//  Copyright © 2016년 . All rights reserved.
//
//  https://en.wikipedia.org/wiki/Real_Time_Streaming_Protocol
//  http://stackoverflow.com/questions/17896008/can-ffmpeg-library-send-the-live-h264-ios-camera-stream-to-wowza-using-rtsp
//  https://github.com/goertzenator/lwip/blob/master/contrib-1.4.0/apps/rtp/rtp.c

#import "RTPClient.h"
#import <CocoaAsyncSocket/CocoaAsyncSocket.h>


struct rtpbits {
    int     sequence:16;     /* sequence number: random */
    int     pt:7;            /* payload type: 14 for MPEG audio */
    int     m:1;             /* marker: 0 */
    int     cc:4;            /* number of CSRC identifiers: 0 */
    int     x:1;             /* number of extension headers: 0 */
    int     p:1;             /* is there padding appended: 0 */
    int     v:2;             /* version: 2 */
};

struct rtpheader {           /* in network byte order */
    struct rtpbits b;
    int     timestamp;       /* start: random */
    int     ssrc;            /* random */
    int     iAudioHeader;    /* =0?! */
};

struct rtpheader RTPheader;


struct rtp_header {
    u_int16_t v:2; /* protocol version */
    u_int16_t p:1; /* padding flag */
    u_int16_t x:1; /* header extension flag */
    u_int16_t cc:4; /* CSRC count */
    u_int16_t m:1; /* marker bit */
    u_int16_t pt:7; /* payload type */
    u_int16_t seq:16; /* sequence number */
    u_int32_t ts; /* timestamp */
    u_int32_t ssrc; /* synchronization source */
};

void
rtp_initialization(void);
static NSData *
rtp_send(unsigned char const *data, int len);


@interface RTPClient()
{
    GCDAsyncUdpSocket *socket_rtp;
    
    uint16_t seqNum;
    
    dispatch_queue_t queue;
    
    uint32_t start_t;
}
@end

@implementation RTPClient

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        socket_rtp = [[GCDAsyncUdpSocket alloc] init];
        [socket_rtp setDelegateQueue:queue];
        self.address = nil;
        self.port = 554;
        seqNum = 0;
        start_t = 0;
    }
    return self;
}

- (void)dealloc {
    [self reset];
    [socket_rtp closeAfterSending];
}

- (void)reset
{
    start_t = 0;
    seqNum = 0;
}

#pragma mark - Publish

- (void)publish:(NSData *)data timestamp:(CMTime)timestamp payloadType:(NSInteger)payloadType
{
    int32_t t = ((float)timestamp.value / timestamp.timescale) * 1000;
    if(start_t == 0) start_t = t;
    
    struct rtp_header header;
    
    //fill the header array of byte with RTP header fields
    header.v = 2;  // 2
    header.p = 0;  // 1
    header.x = 0;  // 1
    header.cc = 0; // 4
    header.m = 0;  // 1
    header.pt = 0;//payloadType;
    header.seq = seqNum;
    header.ts = t - start_t;
    header.ssrc = (u_int32_t)self.port;
    
    /* send RTP stream packet */
    
    int    *cast = (int *) &header;
    
    NSMutableData *packet = [NSMutableData dataWithBytes:&header length:12];
    [packet appendData:data];

    NSLog(@"OC HEADER: %@", [[NSData alloc] initWithBytes:&header length:12]);
    
    rtp_initialization();
    NSData* data2 = rtp_send(data.bytes, data.length);

    [socket_rtp sendData:(NSData *)data2 toHost:self.address port:self.port withTimeout:-1 tag:0];
    
    seqNum++;


}


- (void)testData {
    
}

@end


void
rtp_initialization(void)
{
    struct rtpheader *foo = &RTPheader;
    foo->b.v = 2;
    foo->b.p = 0;
    foo->b.x = 0;
    foo->b.cc = 0;
    foo->b.m = 0;
    foo->b.pt = 0;     /* MPEG Audio */
    foo->b.sequence = rand() & 65535;
    foo->timestamp = rand();
    foo->ssrc = rand();
    foo->iAudioHeader = 0;
}

static NSData *
rtp_send(unsigned char const *data, int len)
{
    struct rtpheader *foo = &RTPheader;
//    foo->iAudioHeader = 1;
    char   *buffer = malloc(len + sizeof(struct rtpheader));
    int    *cast = (int *) foo;
    int    *outcast = (int *) buffer;
    int     count, size;

    outcast[0] = htonl(cast[0]);
    outcast[1] = htonl(cast[1]);
    outcast[2] = htonl(cast[2]);
    outcast[3] = htonl(cast[3]);
    memmove(buffer + ( sizeof(struct rtpheader)  ), data, len);
    size = len + sizeof(*foo);
    //count = send(s, buffer, size, 0);
    
    NSData *nsdata = [[NSData alloc] initWithBytes:buffer length:size];
    
    free(buffer);

    return nsdata;
}
