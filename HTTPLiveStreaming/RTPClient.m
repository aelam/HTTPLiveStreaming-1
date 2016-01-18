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

typedef NS_ENUM(NSInteger, RTSP_SEQ) {
    SEQ_IDLE = -1,
    SEQ_OPTIONS,
    SEQ_DESCRIBE,
    SEQ_SETUP,
    SEQ_PLAY,
    SEQ_RECORD,
    SEQ_ANNOUNCE,
    SEQ_TEARDOWN
};

@interface RTPClient() <AsyncSocketDelegate>
{
    int cseq;
    
    GCDAsyncSocket *socket;
    RTSP_SEQ rtspSeq;
    
    NSMutableData *readBuffer;
}

- (void)sendOPTIONS;
- (void)sendMessage:(NSData *)data tag:(long)tag;
- (void)messageReceived:(NSData *)message tag:(long)tag;

@end

@implementation RTPClient

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        cseq = 0;
        
        dispatch_queue_t mainQueue = dispatch_get_main_queue();
        socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:mainQueue];
        rtspSeq = SEQ_IDLE;
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

#pragma mark - Connection Handshake

- (void)connect:(NSString *)address port:(NSInteger)port stream:(NSString *)stream
{
    self.address = address;
    self.port = port;
    self.streamName = stream;
    
    readBuffer = nil;
    readBuffer = [[NSMutableData alloc] init];
    
    NSError *error;
    [socket connectToHost:address onPort:port withTimeout:-1 error:&error];
    if(error != nil)
    {
        NSLog(@"%@", [error localizedDescription]);
    }
}

- (void)close
{
    rtspSeq = SEQ_IDLE;
    [socket disconnect];
}

#pragma mark - RTSP Handshake

- (void)sendOPTIONS
{
    NSString* rtpHeader = [NSString stringWithFormat:@"OPTIONS %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Require: implicit-play\r\nProxy-Require: gzipped-messages\r\n\r\n"];
    NSLog(@"%@", rtpHeader);
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_OPTIONS];
}

- (void)sendDESCRIBE
{
    NSString* rtpHeader = [NSString stringWithFormat:@"DESCRIBE %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n\r\n",cseq++];
    NSLog(@"%@", rtpHeader);
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_DESCRIBE];
}

- (void)sendSETUP
{
    NSString* rtpHeader = [NSString stringWithFormat:@"SETUP %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Transport: RTP/AVP;unicast;client_port=10000\r\n\r\n"];
    NSLog(@"%@", rtpHeader);
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_SETUP];
}

- (void)sendTEARDOWN
{
    NSString* rtpHeader = [NSString stringWithFormat:@"TEARDOWN %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n\r\n",cseq++];
    NSLog(@"%@", rtpHeader);
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_TEARDOWN];
}

#pragma mark - Handle Message

- (void)sendMessage:(NSData *)data tag:(long)tag
{
    [socket writeData:data withTimeout:-1 tag:tag];
}

- (void)messageReceived:(NSData *)data tag:(long)tag
{
    if( tag == SEQ_OPTIONS )
    {
        /**
         * Convert data to a string for logging.
         *
         * http://stackoverflow.com/questions/550405/convert-nsdata-bytes-to-nsstring
         */
        NSString *string = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
        NSLog(@"%@", string);
        [readBuffer appendData:data];
        if([string isEqual:@"\r\n"])
        {
            NSString *bufferString = [[NSString alloc] initWithBytes:[readBuffer bytes] length:[readBuffer length] encoding:NSUTF8StringEncoding];
            if([bufferString containsString:@"RTSP/1.0 200 OK\r\n"])
            {
                readBuffer = nil;
                readBuffer = [[NSMutableData alloc] init];
                [self sendDESCRIBE];
            }
            else
            {
                [self close];
            }
            readBuffer = nil;
        }
    }
    else if( tag == SEQ_DESCRIBE )
    {
        /**
         * Convert data to a string for logging.
         *
         * http://stackoverflow.com/questions/550405/convert-nsdata-bytes-to-nsstring
         */
        NSString *string = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
        NSLog(@"%@", string);
        [readBuffer appendData:data];
        if([string isEqual:@"\r\n"])
        {
            NSString *bufferString = [[NSString alloc] initWithBytes:[readBuffer bytes] length:[readBuffer length] encoding:NSUTF8StringEncoding];
            if([bufferString containsString:@"RTSP/1.0 200 OK\r\n"])
            {
                readBuffer = nil;
                readBuffer = [[NSMutableData alloc] init];
                [self sendSETUP];
            }
            else
            {
                [self close];
            }
            readBuffer = nil;
        }
    }
    else if( tag == SEQ_SETUP )
    {
        /**
         * Convert data to a string for logging.
         *
         * http://stackoverflow.com/questions/550405/convert-nsdata-bytes-to-nsstring
         */
        NSString *string = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
        NSLog(@"%@", string);
        [readBuffer appendData:data];
        if([string isEqual:@"\r\n"])
        {
            NSString *bufferString = [[NSString alloc] initWithBytes:[readBuffer bytes] length:[readBuffer length] encoding:NSUTF8StringEncoding];
            if([bufferString containsString:@"RTSP/1.0 200 OK\r\n"])
            {
                readBuffer = nil;
                readBuffer = [[NSMutableData alloc] init];
                rtspSeq = SEQ_ANNOUNCE;
            }
            else
            {
                [self close];
            }
            readBuffer = nil;
        }
    }
    else if( tag == SEQ_ANNOUNCE )
    {
        NSString *string = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
        NSLog(@"%@", string);
        [readBuffer appendData:data];
        if([string isEqual:@"\r\n"])
        {
            NSString *bufferString = [[NSString alloc] initWithBytes:[readBuffer bytes] length:[readBuffer length] encoding:NSUTF8StringEncoding];
            if([bufferString containsString:@"RTSP/1.0 200 OK\r\n"])
            {
                readBuffer = nil;
                readBuffer = [[NSMutableData alloc] init];
            }
            readBuffer = nil;
        }
    }
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err {
    NSLog(@"Disconnecting. Error: %@", [err localizedDescription]);
}

- (void)socketDidDisconnect:(AsyncSocket *)sock {
    NSLog(@"Disconnected.");
}

- (void)socket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port {
    NSLog(@"Connected To %@:%i.", host, port);
    
    rtspSeq = SEQ_OPTIONS;
    [socket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:-1 tag:rtspSeq];
    [self sendOPTIONS];
}

- (void)socket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    [self messageReceived:data tag:tag];
    [socket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:-1 tag:tag];
}

#pragma mark - Publish

- (void)publish:(NSData *)data
{
    if(socket == nil || !socket.isConnected || rtspSeq != SEQ_ANNOUNCE) return;
    
    NSString* rtpHeader = [NSString stringWithFormat:@"ANNOUNCE %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Content-Type: application/sdp\r\nContent-Length: %lu\r\n\r\n", (unsigned long)data.length];
    
    NSMutableData *packet = [NSMutableData dataWithData:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding]];
    [packet appendData:data];
    
    [socket writeData:data withTimeout:-1 tag:rtspSeq];
}

@end
