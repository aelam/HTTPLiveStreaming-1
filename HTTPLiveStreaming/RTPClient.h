//
//  RTPClient.h
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 14..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import <Foundation/Foundation.h>

#define TAG_CONNECT 0
#define TAG_PUBLISH 1

@interface RTPClient : NSObject

@property (weak, nonatomic) NSString *address;
@property (nonatomic) NSInteger port;
@property (weak, nonatomic) NSString *streamName;

- (void)connect:(NSString *)address port:(NSInteger)port stream:(NSString *)stream;
- (void)close;

- (void)publish:(NSData *)data;

@end
