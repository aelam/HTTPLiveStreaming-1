//
//  RTSPClient.m
//  HTTPLiveStreaming
//
//  Created by Byeong-uk Park on 2016. 1. 26..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//
//  https://en.wikipedia.org/wiki/Real_Time_Streaming_Protocol
//  http://stackoverflow.com/questions/17896008/can-ffmpeg-library-send-the-live-h264-ios-camera-stream-to-wowza-using-rtsp

#import "RTSPClient.h"
#import <CocoaAsyncSocket/CocoaAsyncSocket.h>

typedef NS_ENUM(NSInteger, RTSP_SEQ) {
    SEQ_IDLE = -1,
    SEQ_ANNOUNCE,
    SEQ_SETUP,
    SEQ_RECORD,
    SEQ_PUBLISH,
    SEQ_TEARDOWN
};

#define RTP_PORT    10000

@interface RTSPClient() <AsyncSocketDelegate>
{
    int cseq;
    
    AsyncSocket *socket_rtsp;
    
    RTSP_SEQ rtspSeq;
    
    NSMutableData *readBuffer;
}

- (void)sendMessage:(NSData *)data tag:(long)tag;
- (void)messageReceived:(NSData *)message tag:(long)tag;

@end

@implementation RTSPClient

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        cseq = 0;
        
        socket_rtsp = [[AsyncSocket alloc] initWithDelegate:self];
        rtspSeq = SEQ_IDLE;
        self.sessionid = nil;
        self.address = nil;
        self.port = 0;
        self.streamName = nil;
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
    
    self.sessionid = nil;
    readBuffer = nil;
    readBuffer = [[NSMutableData alloc] init];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error;
        [socket_rtsp connectToHost:address onPort:port withTimeout:-1 error:&error];
        if(error != nil)
        {
            NSLog(@"%@", [error localizedDescription]);
            if(self.delegate != nil && [self.delegate respondsToSelector:@selector(onRTSPDidConnectedFailed:)])
            {
                [self.delegate onRTSPDidConnectedFailed:self];
            }
        }
    });
}

- (void)close
{
    rtspSeq = SEQ_IDLE;
    [socket_rtsp disconnect];
    readBuffer = nil;
    self.sessionid = nil;
    self.address = nil;
    self.port = 0;
    self.streamName = nil;
}

#pragma mark - RTSP Handshake

- (void)sendANNOUNCE
{
    NSString* rtpHeader = [NSString stringWithFormat:@"ANNOUNCE %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/live/mp4:%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    if(self.sessionid != nil) rtpHeader = [rtpHeader stringByAppendingFormat:@"Session: %@\r\n", self.sessionid];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Content-Type: application/sdp\r\nContent-Length: 0\r\n"];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"\r\n"];
    NSLog(@"%@", rtpHeader);
    rtspSeq = SEQ_ANNOUNCE;
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_ANNOUNCE];
}

- (void)sendSETUP
{
    NSString* rtpHeader = [NSString stringWithFormat:@"SETUP %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/live/mp4:%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    if(self.sessionid != nil) rtpHeader = [rtpHeader stringByAppendingFormat:@"Session: %@\r\n", self.sessionid];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Transport: RTP/AVP;unicast;client_port=%d\r\n", RTP_PORT];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"\r\n"];
    NSLog(@"%@", rtpHeader);
    rtspSeq = SEQ_SETUP;
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_SETUP];
}

- (void)sendRECORD
{
    NSString* rtpHeader = [NSString stringWithFormat:@"RECORD %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/live/mp4:%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    if(self.sessionid != nil) rtpHeader = [rtpHeader stringByAppendingFormat:@"Session: %@\r\n", self.sessionid];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Range: npt=now-\r\n"];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"\r\n"];
    NSLog(@"%@", rtpHeader);
    rtspSeq = SEQ_RECORD;
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_RECORD];
}

- (void)sendTEARDOWN
{
    NSString* rtpHeader = [NSString stringWithFormat:@"TEARDOWN %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/live/mp4:%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    if(self.sessionid != nil) rtpHeader = [rtpHeader stringByAppendingFormat:@"Session: %@\r\n", self.sessionid];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"\r\n"];
    NSLog(@"%@", rtpHeader);
    rtspSeq = SEQ_TEARDOWN;
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_TEARDOWN];
}

#pragma mark - Handle Message

- (BOOL)checkHasSessionID:(NSString *)string
{
    NSError *error   = nil;
    NSRegularExpression *regexp = [NSRegularExpression regularExpressionWithPattern:@"Session:(.+)\r\n"
                                                                            options:0
                                                                              error:&error];
    
    if (error != nil) {
        NSLog(@"%@", error);
        return NO;
    }
    
    NSTextCheckingResult *match = [regexp firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    
    if(match.range.length > 0) return YES;
    
    return NO;
}

- (void)getRTSPSessionID:(NSString *)string
{
    if( [self checkHasSessionID:string] )
    {
        NSError *error   = nil;
        NSRegularExpression *regexp = [NSRegularExpression regularExpressionWithPattern:@"Session:(.+)\r\n"
                                                                                options:0
                                                                                  error:&error];
        
        if (error != nil) {
            NSLog(@"%@", error);
        } else {
            NSTextCheckingResult *match = [regexp firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
            NSString *substring = [string substringWithRange:[match rangeAtIndex:0]];
            NSRegularExpression *regexp_sub = [NSRegularExpression regularExpressionWithPattern:@"(?<=:).*?(?=;)|(?=\r\n)" options:0 error:&error];
            if(error != nil)
            {
                NSLog(@"%@", error);
            }
            else
            {
                NSTextCheckingResult *match_sub = [regexp_sub firstMatchInString:substring options:0 range:NSMakeRange(0, substring.length)];
                NSString *rawValue = [substring substringWithRange:[match_sub rangeAtIndex:0]];
                self.sessionid = [rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }
        }
    }
}

- (void)sendMessage:(NSData *)data tag:(long)tag
{
    [socket_rtsp writeData:data withTimeout:-1 tag:tag];
}

- (void)messageReceived:(NSData *)data tag:(long)tag
{
    if( rtspSeq == SEQ_ANNOUNCE )
    {
        NSString *string = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
        NSLog(@"%@", string);
        [readBuffer appendData:data];
        const char* bytes = (const char*)[data bytes];
        if(bytes[0] == 0x0d && bytes[1] == 0x0a)
        {
            NSString *bufferString = [[NSString alloc] initWithBytes:[readBuffer bytes] length:[readBuffer length] encoding:NSUTF8StringEncoding];
            BOOL is200OK = NO;
            if([bufferString containsString:@"RTSP/1.0 200 OK\r\n"])
            {
                if(self.sessionid == nil) [self getRTSPSessionID:bufferString];
                is200OK = YES;
            }
            else
            {
                [self close];
            }
            [readBuffer resetBytesInRange:NSMakeRange(0, [readBuffer length])];
            readBuffer = nil;
            if(is200OK)
            {
                readBuffer = [[NSMutableData alloc] init];
                [self performSelector:@selector(sendSETUP)];
            }
        }
    }
    else if( rtspSeq == SEQ_SETUP )
    {
        /**
         * Convert data to a string for logging.
         *
         * http://stackoverflow.com/questions/550405/convert-nsdata-bytes-to-nsstring
         */
        NSString *string = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
        NSLog(@"%@", string);
        [readBuffer appendData:data];
        const char* bytes = (const char*)[data bytes];
        if(bytes[0] == 0x0d && bytes[1] == 0x0a)
        {
            NSString *bufferString = [[NSString alloc] initWithBytes:[readBuffer bytes] length:[readBuffer length] encoding:NSUTF8StringEncoding];
            BOOL is200OK = NO;
            if([bufferString containsString:@"RTSP/1.0 200 OK\r\n"])
            {
                if(self.sessionid == nil) [self getRTSPSessionID:bufferString];
                is200OK = YES;
            }
            else
            {
                [self close];
            }
            [readBuffer resetBytesInRange:NSMakeRange(0, [readBuffer length])];
            readBuffer = nil;
            if(is200OK)
            {
                readBuffer = [[NSMutableData alloc] init];
                [self performSelector:@selector(sendRECORD)];
            }
        }
    }
    else if( rtspSeq == SEQ_RECORD )
    {
        /**
         * Convert data to a string for logging.
         *
         * http://stackoverflow.com/questions/550405/convert-nsdata-bytes-to-nsstring
         */
        NSString *string = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
        NSLog(@"%@", string);
        [readBuffer appendData:data];
        const char* bytes = (const char*)[data bytes];
        if(bytes[0] == 0x0d && bytes[1] == 0x0a)
        {
            NSString *bufferString = [[NSString alloc] initWithBytes:[readBuffer bytes] length:[readBuffer length] encoding:NSUTF8StringEncoding];
            BOOL is200OK = NO;
            if([bufferString containsString:@"RTSP/1.0 200 OK\r\n"])
            {
                if(self.sessionid == nil) [self getRTSPSessionID:bufferString];
                is200OK = YES;
            }
            else
            {
                [self close];
            }
            [readBuffer resetBytesInRange:NSMakeRange(0, [readBuffer length])];
            readBuffer = nil;
            rtspSeq = SEQ_PUBLISH;
            if(self.delegate != nil && [self.delegate respondsToSelector:@selector(onRTSPDidConnectedOK:)])
            {
                [self.delegate onRTSPDidConnectedOK:self];
            }
        }
    }
}

#pragma mark - AsyncSocketDelegate

- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err {
    NSLog(@"Disconnecting. Error: %@", [err localizedDescription]);
}

- (void)onSocketDidDisconnect:(AsyncSocket *)sock {
    NSLog(@"Disconnected.");
    if(self.delegate != nil && [self.delegate respondsToSelector:@selector(onRTSPDidDisConnected:)])
    {
        [self.delegate onRTSPDidDisConnected:self];
    }
}

- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port {
    NSLog(@"Connected To %@:%i.", host, port);
    
    rtspSeq = SEQ_ANNOUNCE;
    [socket_rtsp readDataToData:[AsyncSocket CRLFData] withTimeout:-1 tag:rtspSeq];
    [self sendANNOUNCE];
}

- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    [self messageReceived:data tag:tag];
    [socket_rtsp readDataToData:[AsyncSocket CRLFData] withTimeout:-1 tag:tag];
}

@end