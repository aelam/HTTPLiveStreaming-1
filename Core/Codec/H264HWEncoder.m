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
    NSData *sps;
    NSData *pps;
    
    VTCompressionSessionRef session;
    CGSize outputSize;
}

- (void) dealloc {
    [self invalidate];
}

- (id) init {
    if (self = [super init]) {
        session = NULL;
        outputSize = CGSizeMake(640, 360);
    }
    return self;
}

void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
                     CMSampleBufferRef sampleBuffer )
{
    H264HWEncoder* encoder = (__bridge H264HWEncoder*)outputCallbackRefCon;
    
    if (status == noErr) {
        return [encoder didReceiveSampleBuffer:sampleBuffer];
    }
    
    NSLog(@"Error %d : %@", infoFlags, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]);
}

- (void)didReceiveSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) {
        return;
    }
    
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFBooleanRef dependsOnOthers = (CFBooleanRef)CFDictionaryGetValue(attachment, kCMSampleAttachmentKey_DependsOnOthers);
    bool isKeyframe = (dependsOnOthers == kCFBooleanFalse);
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    NSMutableData *fulldata = [NSMutableData data];
    if (isKeyframe) {
        
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
                self->sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                self->pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                
                const char bytes[] = "\x00\x00\x00\x01"; // SPS PPS Header
                size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
                NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
                NSMutableData *fullSPSData = [NSMutableData dataWithData:byteHeader];
                NSMutableData *fullPPSData = [NSMutableData dataWithData:byteHeader];
                
                [fullSPSData appendData:self->sps];
                [fullPPSData appendData:self->pps];
                
                [fulldata appendData:fullSPSData];
                [fulldata appendData:fullPPSData];
                
                self->sps = fullSPSData;
                self->pps = fullPPSData;
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
            
            [fulldata appendData:fullAVCData];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
    
    if (self.delegate != nil) {
        [self.delegate gotH264EncodedData:fulldata timestamp:timestamp];
    }
}

- (void) setOutputSize:(CGSize)size
{
    outputSize = size;
}

- (void) initSession
{
    CFMutableDictionaryRef encoderSpecifications = NULL;
    
#if !TARGET_OS_IPHONE
    /** iOS is always hardware-accelerated **/
    CFStringRef key = kVTVideoEncoderSpecification_EncoderID;
    CFStringRef value = CFSTR("com.apple.videotoolbox.videoencoder.h264.gva");
    
    CFStringRef bkey = kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder;
    CFBooleanRef bvalue = kCFBooleanTrue;
    
    CFStringRef ckey = kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder;
    CFBooleanRef cvalue = kCFBooleanTrue;
    
    encoderSpecifications = CFDictionaryCreateMutable(
                                                      kCFAllocatorDefault,
                                                      3,
                                                      &kCFTypeDictionaryKeyCallBacks,
                                                      &kCFTypeDictionaryValueCallBacks);
    
    CFDictionaryAddValue(encoderSpecifications, bkey, bvalue);
    CFDictionaryAddValue(encoderSpecifications, ckey, cvalue);
    CFDictionaryAddValue(encoderSpecifications, key, value);
#endif
    
    OSStatus ret = VTCompressionSessionCreate(kCFAllocatorDefault, outputSize.width, outputSize.height, kCMVideoCodecType_H264, encoderSpecifications, NULL, NULL, didCompressH264, (__bridge void *)(self), &session);
    if (ret == noErr) {
        VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_3_0);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_AspectRatio16x9, kCFBooleanTrue);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(90));
        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxH264SliceBytes, (__bridge CFTypeRef)@(144));
        
#if !TARGET_OS_IPHONE
        VTSessionSetProperty(session, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, kCFBooleanTrue);
#endif
        
        int bitrate = 600;
        int v = bitrate;
        CFNumberRef ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &v);
        
        OSStatus ret = VTSessionSetProperty(session, kVTCompressionPropertyKey_AverageBitRate, ref);
        
        CFRelease(ref);
        ret = VTSessionCopyProperty(session, kVTCompressionPropertyKey_AverageBitRate, kCFAllocatorDefault, &ref);
        
        if(ret == noErr && ref) {
            SInt32 br = 0;
            
            CFNumberGetValue(ref, kCFNumberSInt32Type, &br);
            
            bitrate = br;
            CFRelease(ref);
        } else {
            bitrate = v;
        }
        v = 550 / 8;
        CFNumberRef bytes = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v);
        v = 1;
        CFNumberRef duration = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v);
        
        CFMutableArrayRef limit = CFArrayCreateMutable(kCFAllocatorDefault, 2, &kCFTypeArrayCallBacks);
        
        CFArrayAppendValue(limit, bytes);
        CFArrayAppendValue(limit, duration);
        
        VTSessionSetProperty(session, kVTCompressionPropertyKey_DataRateLimits, limit);
        CFRelease(bytes);
        CFRelease(duration);
        CFRelease(limit);
        
        VTCompressionSessionPrepareToEncodeFrames(session);
    }
}

- (void) invalidate
{
    if(session)
    {
        VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
    }
}

- (void) encode:(CMSampleBufferRef )sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    if(session == NULL)
    {
        [self initSession];
    }
    
    // Create properties
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    VTCompressionSessionEncodeFrame(session, imageBuffer, timestamp, kCMTimeInvalid, NULL, NULL, NULL);
}

@end
