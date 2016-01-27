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
#include <ifaddrs.h>
#include <arpa/inet.h>

typedef NS_ENUM(NSInteger, RTSP_SEQ) {
    SEQ_IDLE = -1,
    SEQ_ANNOUNCE,
    SEQ_SETUP_AUDIO,
    SEQ_SETUP_VIDEO,
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

/** There are 13 supported frequencies by ADTS. **/
 int AUDIO_SAMPLING_RATES[] = {
    96000, // 0
    88200, // 1
    64000, // 2
    48000, // 3
    44100, // 4
    32000, // 5
    24000, // 6
    22050, // 7
    16000, // 8
    12000, // 9
    11025, // 10
    8000,  // 11
    7350,  // 12
    -1,   // 13
    -1,   // 14
    -1,   // 15
};

- (NSString *)getIPAddress
{
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    NSString *wifiAddress = nil;
    NSString *cellAddress = nil;
    
    // retrieve the current interfaces - returns 0 on success
    if(!getifaddrs(&interfaces)) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            sa_family_t sa_type = temp_addr->ifa_addr->sa_family;
            if(sa_type == AF_INET || sa_type == AF_INET6) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                NSString *addr = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)]; // pdp_ip0
//                NSLog(@"NAME: \"%@\" addr: %@", name, addr); // see for yourself
                
                if([name isEqualToString:@"en0"]) {
                    // Interface is the wifi connection on the iPhone
                    wifiAddress = addr;
                } else
                    if([name isEqualToString:@"pdp_ip0"]) {
                        // Interface is the cell connection on the iPhone
                        cellAddress = addr;
                    }
            }
            temp_addr = temp_addr->ifa_next;
        }
        // Free memory
        freeifaddrs(interfaces);
    }
    NSString *addr = wifiAddress ? wifiAddress : cellAddress;
    return addr ? addr : @"0.0.0.0";
}

- (void)sendANNOUNCE
{
    NSString *myip = [self getIPAddress];
    
    NSString* session = @"v=0\r\n";
    session = [session stringByAppendingFormat:@"o=- 0 0 IN IP4 %@\r\n", myip];
    session = [session stringByAppendingFormat:@"s=HTTPLiveStreaming\r\n"];
    session = [session stringByAppendingFormat:@"c=IN IP4 %@\r\n", myip];
    session = [session stringByAppendingFormat:@"t=0 0\r\n"];
    session = [session stringByAppendingFormat:@"a=tool:HTTPLiveStreaming\r\n"];
    session = [session stringByAppendingFormat:@"m=audio 49230 RTP/AVP 96\r\n"];
    session = [session stringByAppendingFormat:@"a=rtpmap:96 MP4A-LATM/24000/2\r\n"];
    session = [session stringByAppendingFormat:@"a=fmtp:96 profile-level-id=1; bitrate=64000;cpresent=0;object=2;config=400026203fc0\r\n"];
    session = [session stringByAppendingFormat:@"a=control:trackID=0\r\n"];
    session = [session stringByAppendingFormat:@"m=video 49170 RTP/AVP 98\r\n"];
    session = [session stringByAppendingFormat:@"a=rtpmap:98 H264/90000\r\n"];
    session = [session stringByAppendingFormat:@"a=fmtp:98 packetization-mode=1;profile-level-id=42A01E;sprop-parameter-sets=Z0IAKOkBQHsg,aM4xUg==;\r\n"];
    session = [session stringByAppendingFormat:@"a=control:trackID=1\r\n"];
    session = [session stringByAppendingFormat:@"\r\n"];
    
    NSString* rtpHeader = [NSString stringWithFormat:@"ANNOUNCE %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/live/%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    if(self.sessionid != nil) rtpHeader = [rtpHeader stringByAppendingFormat:@"Session: %@\r\n", self.sessionid];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Content-Type: application/sdp\r\n"];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Content-Length: %ld\r\n", [session length]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"\r\n"];
    rtpHeader = [rtpHeader stringByAppendingString:session];
    
    NSLog(@"%@", rtpHeader);
    rtspSeq = SEQ_ANNOUNCE;
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_ANNOUNCE];
}

- (void)sendSETUPAudio
{
    NSString* rtpHeader = [NSString stringWithFormat:@"SETUP %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/live/%@/trackID=0", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    if(self.sessionid != nil) rtpHeader = [rtpHeader stringByAppendingFormat:@"Session: %@\r\n", self.sessionid];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Transport: RTP/AVP/UDP;unicast;client_port=%d\r\n", RTP_PORT];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Content-Length: 0\r\n"];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"\r\n"];
    NSLog(@"%@", rtpHeader);
    rtspSeq = SEQ_SETUP_AUDIO;
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_SETUP_AUDIO];
}

- (void)sendSETUPVideo
{
    NSString* rtpHeader = [NSString stringWithFormat:@"SETUP %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/live/%@/trackID=1", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    if(self.sessionid != nil) rtpHeader = [rtpHeader stringByAppendingFormat:@"Session: %@\r\n", self.sessionid];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Transport: RTP/AVP/UDP;unicast;client_port=%d\r\n", RTP_PORT+1];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Content-Length: 0\r\n"];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"\r\n"];
    NSLog(@"%@", rtpHeader);
    rtspSeq = SEQ_SETUP_VIDEO;
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_SETUP_VIDEO];
}

- (void)sendRECORD
{
    NSString* rtpHeader = [NSString stringWithFormat:@"RECORD %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/live/%@", self.address, self.port, self.streamName]];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"CSeq: %d\r\n",cseq++];
    if(self.sessionid != nil) rtpHeader = [rtpHeader stringByAppendingFormat:@"Session: %@\r\n", self.sessionid];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Range: npt=now-\r\n"];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"Content-Length: 0\r\n"];
    rtpHeader = [rtpHeader stringByAppendingFormat:@"\r\n"];
    NSLog(@"%@", rtpHeader);
    rtspSeq = SEQ_RECORD;
    [self sendMessage:[rtpHeader dataUsingEncoding:NSUTF8StringEncoding] tag:SEQ_RECORD];
}

- (void)sendTEARDOWN
{
    NSString* rtpHeader = [NSString stringWithFormat:@"TEARDOWN %@ RTSP/1.0\r\n", [NSString stringWithFormat:@"rtsp://%@:%ld/live/%@", self.address, self.port, self.streamName]];
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

- (NSInteger)getServerPort:(NSString *)string
{
    NSError *error = nil;
    NSRegularExpression *regexp = [NSRegularExpression regularExpressionWithPattern:@"server_port=([0-9]*)" options:0 error:&error];
    if(error != nil)
    {
        NSLog(@"%@", [error localizedDescription]);
        return -1;
    }
    else
    {
        NSTextCheckingResult *match = [regexp firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
        NSString *substring = [string substringWithRange:[match rangeAtIndex:0]];
        NSRegularExpression *regexp_sub = [NSRegularExpression regularExpressionWithPattern:@"(?<==).*" options:0 error:&error];
        if(error != nil)
        {
            NSLog(@"%@", error);
            return -1;
        }
        else
        {
            NSTextCheckingResult *match_sub = [regexp_sub firstMatchInString:substring options:0 range:NSMakeRange(0, substring.length)];
            NSString *rawValue = [substring substringWithRange:[match_sub rangeAtIndex:0]];
            return [rawValue integerValue];
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
                [self performSelector:@selector(sendSETUPAudio)];
            }
        }
    }
    else if( rtspSeq == SEQ_SETUP_AUDIO )
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
                if(self.delegate != nil && [self.delegate respondsToSelector:@selector(onRTSP:didSETUP_AUDIOWithServerPort:)] && [self getServerPort:bufferString] >= 0)
                {
                    [self.delegate onRTSP:self didSETUP_AUDIOWithServerPort:[self getServerPort:bufferString]];
                }
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
                [self performSelector:@selector(sendSETUPVideo)];
            }
        }
    }
    else if( rtspSeq == SEQ_SETUP_VIDEO )
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
                if(self.delegate != nil && [self.delegate respondsToSelector:@selector(onRTSP:didSETUP_VIDEOWithServerPort:)] && [self getServerPort:bufferString] >= 0)
                {
                    [self.delegate onRTSP:self didSETUP_VIDEOWithServerPort:[self getServerPort:bufferString]];
                }
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