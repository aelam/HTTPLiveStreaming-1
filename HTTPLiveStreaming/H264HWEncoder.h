//
//  H264HWEncoder.h
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 7..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//
//  https://github.com/manishganvir/iOS-h264Hw-Toolbox

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

@protocol H264HWEncoderDelegate <NSObject>

@required
- (void)gotH264EncodedData:(NSData*)data timestamp:(CMTime)timestamp;
- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps timestamp:(CMTime)timestamp;

@end

@interface H264HWEncoder : NSObject

- (void) encode:(CMSampleBufferRef )sampleBuffer;

@property (weak, nonatomic) id<H264HWEncoderDelegate> delegate;

@end
