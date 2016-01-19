//
//  H264HWEncoder.m
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 7..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import "H264HWEncoder.h"

@import VideoToolbox;
@import AVFoundation;

@implementation H264HWEncoder
{
    VTCompressionSessionRef EncodingSession;
    int  frameCount;
    NSData *sps;
    NSData *pps;
}

void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
                     CMSampleBufferRef sampleBuffer )
{
    if (status != 0) return;
    
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        return;
    }
    H264HWEncoder* encoder = (__bridge H264HWEncoder*)outputCallbackRefCon;
    
    if (status == noErr) {
        return [encoder didReceiveSampleBuffer:sampleBuffer];
    }
    
    NSLog(@"Error: %@", [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]);
}

- (void)didReceiveSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) {
        return;
    }
    
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFBooleanRef dependsOnOthers = (CFBooleanRef)CFDictionaryGetValue(attachment, kCMSampleAttachmentKey_DependsOnOthers);
    bool isKeyframe = (dependsOnOthers == kCFBooleanFalse);
    if (isKeyframe) {
        char* bufferData;
        size_t size;
        CMBlockBufferGetDataPointer(block, 0, NULL, &size, &bufferData);
        
        NSData *data = [NSData dataWithBytes:bufferData length:size];
        
        if (self.delegate != nil) {
            [self.delegate gotH264EncodedData:data];
        }
    }
}

- (void) encode:(CMSampleBufferRef )sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    VTCompressionSessionRef session;
    OSStatus ret = VTCompressionSessionCreate(NULL, (int)width, (int)height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, NULL, &session);
    if (ret == noErr) {
        VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        
        CMTime presentationTimestamp = CMTimeMake(0, 1);
        VTCompressionSessionEncodeFrame(session, imageBuffer, presentationTimestamp, kCMTimeInvalid, NULL, NULL, NULL);
        VTCompressionSessionEndPass(session, false, NULL);
    }
    
    if (session) {
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
    }
}

@end
