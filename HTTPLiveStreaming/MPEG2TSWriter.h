//
//  MPEG2TSWriter.h
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 14..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MPEG2TSWriter : NSObject
+ (instancetype)sharedInstance;
- (void)publish:(void *)data length:(int)length;
@end
