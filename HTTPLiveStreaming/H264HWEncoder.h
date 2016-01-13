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

- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps;
- (void)gotH264EncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame;

@end

@interface H264HWEncoder : NSObject

- (void) initWithConfiguration;
- (void) startEncode:(int)width  height:(int)height bitrate:(int)bitrate;
- (void) encode:(CMSampleBufferRef )sampleBuffer;
- (void) end;


@property (weak, nonatomic) NSString *error;
@property (weak, nonatomic) id<H264HWEncoderDelegate> delegate;

@end
