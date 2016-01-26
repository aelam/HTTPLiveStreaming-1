//
//  RTPClient.h
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 14..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

#define RTP_PAYLOAD_H264        98
#define RTP_PAYLOAD_AAC         96

@interface RTPClient : NSObject

@property (weak, nonatomic) NSString *address;
@property (nonatomic) NSInteger port;

- (void)publish:(NSData *)data payloadType:(int)payloadType timestamp:(CMTime)timestamp;

@end
