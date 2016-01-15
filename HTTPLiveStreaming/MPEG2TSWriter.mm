//
//  MPEG2TSWriter.mm
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 14..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#include "MPEG2TSWriter.h"

#include <liveMedia.hh>
#include <BasicUsageEnvironment.hh>

UsageEnvironment* env;

@implementation MPEG2TSWriter
{
    char const* outputFileName;
}

+ (instancetype)sharedInstance
{
    static MPEG2TSWriter *_gSharedWrapper = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _gSharedWrapper = [MPEG2TSWriter new];
    });
    return _gSharedWrapper;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        NSLog(@"init ts writer");
    }
    return self;
}

- (void)publish:(void *)data length:(int)length
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        // Begin by setting up our usage environment:
        TaskScheduler* scheduler = BasicTaskScheduler::createNew();
        env = BasicUsageEnvironment::createNew(*scheduler);
        
        // Open the input file as a 'byte-stream file source':
        FramedSource* inputSource = ByteStreamMemoryBufferSource::createNew(*env, (u_int8_t*)data, length);
        if (inputSource == NULL) {
            *env << "Unable to publish data as a byte-stream file source\n";
            return;
        }
        
        // Create a 'framer' filter for this file source, to generate presentation times for each NAL unit:
        H264VideoStreamFramer* framer = H264VideoStreamFramer::createNew(*env, inputSource, True/*includeStartCodeInOutput*/);
        
        // Then create a filter that packs the H.264 video data into a Transport Stream:
        MPEG2TransportStreamFromESSource* tsFrames = MPEG2TransportStreamFromESSource::createNew(*env);
        tsFrames->addNewVideoSource(framer, 5/*mpegVersion: H.264*/);
        
        // Open the output file as a 'file sink':
        MediaSink* outputSink = FileSink::createNew(*env, outputFileName);
        if (outputSink == NULL) {
            *env << "Unable to open file \"" << outputFileName << "\" as a file sink\n";
            return;
        }
        
        // Finally, start playing:
        *env << "Beginning to read...\n";
        outputSink->startPlaying(*tsFrames, NULL, NULL);
        
        env->taskScheduler().doEventLoop(); // does not return
    });
}

@end
