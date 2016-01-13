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
    dispatch_queue_t aQueue;
    int  frameCount;
    NSData *sps;
    NSData *pps;
    int m_bitrate;
}
@synthesize error;

- (void) initWithConfiguration
{
    EncodingSession = nil;
    aQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    frameCount = 0;
    sps = NULL;
    pps = NULL;
    m_bitrate = 550;
}

void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
                     CMSampleBufferRef sampleBuffer )
{
    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    if (status != 0) return;
    
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    H264HWEncoder* encoder = (__bridge H264HWEncoder*)outputCallbackRefCon;
    
    // Check if we have got a key frame first
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        // CFDictionaryRef extensionDict = CMFormatDescriptionGetExtensions(format);
        // Get the extensions
        // From the extensions get the dictionary with key "SampleDescriptionExtensionAtoms"
        // From the dict, get the value for the key "avcC"
        
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            // Found sps and now check for pps
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                // Found pps
                encoder->sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                encoder->pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                
                const char bytes[] = "\x00\x00\x00\x01"; // SPS PPS Header
                size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
                NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
                NSMutableData *fullSPSData = [NSMutableData dataWithData:byteHeader];
                NSMutableData *fullPPSData = [NSMutableData dataWithData:byteHeader];
                
                [fullSPSData appendData:encoder->sps];
                [fullPPSData appendData:encoder->pps];
                
                encoder->sps = fullSPSData;
                encoder->pps = fullPPSData;
                
                if (encoder->_delegate)
                {
                    [encoder->_delegate gotSpsPps:encoder->sps pps:encoder->pps];
                }
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // Convert the length value from Big-endian to Little-endian
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            
            const char bytes[] = "\x00\x00\x00\x01"; // AVC Header
            size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
            NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
            NSMutableData *fullAVCData = [NSMutableData dataWithData:byteHeader];
            
            [fullAVCData appendData:data];
            data = fullAVCData;
            
            [encoder->_delegate gotH264EncodedData:data isKeyFrame:keyframe];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}

- (void) startEncode:(int)width  height:(int)height bitrate:(int)bitrate
{
    dispatch_sync(aQueue, ^{
        // For testing out the logic, lets read from a file and then send it to encoder to create h264 stream
        
        // Create the compression session
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self),  &EncodingSession);
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        
        if (status != 0)
        {
            NSLog(@"H264: Unable to create a H264 session");
            error = @"H264: Unable to create a H264 session";
            
            return ;
        }
        
        // Set the properties
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
        
        // Set the bitrate properties
        int v = m_bitrate;
        CFNumberRef ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &v);
        OSStatus ret = VTSessionSetProperty((VTCompressionSessionRef)EncodingSession, kVTCompressionPropertyKey_AverageBitRate, ref);
        
        if(ret != noErr) {
            NSLog(@"H264Encode::setBitrate Error setting bitrate! %d", (int) ret);
        }
        CFRelease(ref);
        ret = VTSessionCopyProperty((VTCompressionSessionRef)EncodingSession, kVTCompressionPropertyKey_AverageBitRate, kCFAllocatorDefault, &ref);
        
        if(ret == noErr && ref) {
            SInt32 br = 0;
            
            CFNumberGetValue(ref, kCFNumberSInt32Type, &br);
            
            m_bitrate = br;
            CFRelease(ref);
        } else {
            m_bitrate = v;
        }
        v = bitrate / 8;
        CFNumberRef bytes = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v);
        v = 1;
        CFNumberRef duration = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v);
        
        CFMutableArrayRef limit = CFArrayCreateMutable(kCFAllocatorDefault, 2, &kCFTypeArrayCallBacks);
        
        CFArrayAppendValue(limit, bytes);
        CFArrayAppendValue(limit, duration);
        
        VTSessionSetProperty((VTCompressionSessionRef)EncodingSession, kVTCompressionPropertyKey_DataRateLimits, limit);
        CFRelease(bytes);
        CFRelease(duration);
        CFRelease(limit);
        
        // Tell the encoder to start encoding
        VTCompressionSessionPrepareToEncodeFrames(EncodingSession);
    });
}

- (void) encode:(CMSampleBufferRef )sampleBuffer
{
    dispatch_sync(aQueue, ^{
        frameCount++;
        // Get the CV Image buffer
        CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        
        // Create properties
        CMTime presentationTimeStamp = CMTimeMake(frameCount, 1000);
        //CMTime duration = CMTimeMake(1, DURATION);
        VTEncodeInfoFlags flags;
        
        // Pass it to the encoder
        OSStatus statusCode = VTCompressionSessionEncodeFrame(EncodingSession,
                                                              imageBuffer,
                                                              presentationTimeStamp,
                                                              kCMTimeInvalid,
                                                              NULL, NULL, &flags);
        // Check for error
        if (statusCode != noErr) {
            NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
            error = @"H264: VTCompressionSessionEncodeFrame failed ";
            
            // End the session
            VTCompressionSessionInvalidate(EncodingSession);
            CFRelease(EncodingSession);
            EncodingSession = NULL;
            error = NULL;
            return;
        }
        NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
    });
}

- (void) end
{
    // Mark the completion
    VTCompressionSessionCompleteFrames(EncodingSession, kCMTimeInvalid);
    
    // End the session
    VTCompressionSessionInvalidate(EncodingSession);
    CFRelease(EncodingSession);
    EncodingSession = NULL;
    error = NULL;
}

@end
