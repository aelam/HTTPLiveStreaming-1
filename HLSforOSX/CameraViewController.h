//
//  ViewController.h
//  HLSforOSX
//
//  Created by Byeong-uk Park on 2016. 2. 9..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import "H264HWEncoder.h"

@interface CameraViewController : NSViewController <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, H264HWEncoderDelegate>

@end

