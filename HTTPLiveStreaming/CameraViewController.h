//
//  CameraViewController.h
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 7..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "H264HWEncoder.h"

@import AVFoundation;

@interface CameraViewController : UIViewController <AVCaptureVideoDataOutputSampleBufferDelegate, H264HWEncoderDelegate>

@end
