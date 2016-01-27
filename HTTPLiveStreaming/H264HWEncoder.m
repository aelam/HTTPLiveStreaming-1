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
}

- (void) dealloc {
}

- (id) init {
    if (self = [super init]) {
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
    
    NSLog(@"Error: %@", [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]);
}

- (void)didReceiveSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) {
        return;
    }
    
//    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFBooleanRef dependsOnOthers = (CFBooleanRef)CFDictionaryGetValue(attachment, kCMSampleAttachmentKey_DependsOnOthers);
    bool isKeyframe = (dependsOnOthers == kCFBooleanFalse);
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
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
                
                self->sps = fullSPSData;
                self->pps = fullPPSData;
                
                if (self.delegate && [self.delegate respondsToSelector:@selector(gotSpsPps:pps:timestamp:)]) [self.delegate gotSpsPps:self->sps pps:self->pps timestamp:timestamp];
            }
        }
        
//        char* bufferData;
//        size_t size;
//        CMBlockBufferGetDataPointer(block, 0, NULL, &size, &bufferData);
//        
//        NSData *data = [NSData dataWithBytes:bufferData length:size];
//        
//        const char bytes[] = "\x00\x00\x00\x01"; // AVC Header
//        size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
//        NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
//        NSMutableData *fullAVCData = [NSMutableData dataWithData:byteHeader];
//
//        [fullAVCData appendData:data];
//        data = fullAVCData;
//
//        if (self.delegate != nil) {
//            [self.delegate gotH264EncodedData:data];
//        }
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
            
            if (self.delegate != nil) {
                [self.delegate gotH264EncodedData:data timestamp:timestamp];
            }
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}

- (void) encode:(CMSampleBufferRef )sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    VTCompressionSessionRef session;
    OSStatus ret = VTCompressionSessionCreate(NULL, (int)width, (int)height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self), &session);
    if (ret == noErr) {
        VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        
        // Create properties
        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        
        VTCompressionSessionEncodeFrame(session, imageBuffer, timestamp, kCMTimeInvalid, NULL, NULL, NULL);
        VTCompressionSessionEndPass(session, false, NULL);
    }
    
    if (session) {
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
    }
}

@end
