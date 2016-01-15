//
//  CameraViewController.h
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 7..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "H264HWEncoder.h"
#import "AACEncoder.h"

@interface CameraViewController : UIViewController <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, H264HWEncoderDelegate, AACEncoderDelegate>

@end
