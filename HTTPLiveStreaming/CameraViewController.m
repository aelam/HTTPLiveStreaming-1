//
//  CameraViewController.m
//  HTTPLiveStreaming
//
//  Created by Byeongwook Park on 2016. 1. 7..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import "CameraViewController.h"
#include "RTPClient.h"

@interface CameraViewController ()
{
    H264HWEncoder *h264Encoder;
    AACEncoder *aacEncoder;
    AVCaptureSession *captureSession;
    bool startCalled;
    AVCaptureVideoPreviewLayer *previewLayer;
    NSString *h264File;
//    NSString *aacFile;
    NSFileHandle *fileH264Handle;
//    NSFileHandle *fileAACHandle;
    AVCaptureConnection* connectionVideo;
    AVCaptureConnection* connectionAudio;
    RTPClient *rtsp;
}
@property (weak, nonatomic) IBOutlet UIButton *StartStopButton;
@end

@implementation CameraViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    h264Encoder = [[H264HWEncoder alloc] init];
    h264Encoder.delegate = self;
    
    aacEncoder = [[AACEncoder alloc] init];
    aacEncoder.delegate = self;
    
    startCalled = true;
    
    rtsp = [[RTPClient alloc] init];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

// Called when start/stop button is pressed
- (IBAction)OnStartStop:(id)sender {
    if (startCalled)
    {
        [self startCamera];
        startCalled = false;
        [_StartStopButton setTitle:@"Stop" forState:UIControlStateNormal];
    }
    else
    {
        [_StartStopButton setTitle:@"Start" forState:UIControlStateNormal];
        startCalled = true;
        [self stopCamera];
    }
}

- (void) startCamera
{
    // make input device
    
    NSError *deviceError;
    
    AVCaptureDevice *cameraDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *microphoneDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    
    AVCaptureDeviceInput *inputCameraDevice = [AVCaptureDeviceInput deviceInputWithDevice:cameraDevice error:&deviceError];
    AVCaptureDeviceInput *inputMicrophoneDevice = [AVCaptureDeviceInput deviceInputWithDevice:microphoneDevice error:&deviceError];
    
    // make output device
    
    AVCaptureVideoDataOutput *outputVideoDevice = [[AVCaptureVideoDataOutput alloc] init];
    
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* val = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:val forKey:key];
    outputVideoDevice.videoSettings = videoSettings;
    
    dispatch_queue_t queue = dispatch_queue_create("com.metapleasure.HTTPLiveStreaming", NULL);
    [outputVideoDevice setSampleBufferDelegate:self queue:queue];
    
    AVCaptureAudioDataOutput *outputAudioDevice = [[AVCaptureAudioDataOutput alloc] init];
    [outputAudioDevice setSampleBufferDelegate:self queue:queue];
    
    // initialize capture session
    
    captureSession = [[AVCaptureSession alloc] init];
    
    [captureSession addInput:inputCameraDevice];
    [captureSession addInput:inputMicrophoneDevice];
    [captureSession addOutput:outputVideoDevice];
    [captureSession addOutput:outputAudioDevice];
    
    // begin configuration for the AVCaptureSession
    [captureSession beginConfiguration];
    
    // picture resolution
    [captureSession setSessionPreset:[NSString stringWithString:AVCaptureSessionPreset640x480]];
    
    connectionVideo = [outputVideoDevice connectionWithMediaType:AVMediaTypeVideo];
    connectionAudio = [outputAudioDevice connectionWithMediaType:AVMediaTypeAudio];
    [self setRelativeVideoOrientation];
    
    NSNotificationCenter* notify = [NSNotificationCenter defaultCenter];
    
    [notify addObserver:self
               selector:@selector(statusBarOrientationDidChange:)
                   name:@"StatusBarOrientationDidChange"
                 object:nil];
    
    
    [captureSession commitConfiguration];
    
    // make preview layer and add so that camera's view is displayed on screen
    
    previewLayer = [AVCaptureVideoPreviewLayer    layerWithSession:captureSession];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    
    previewLayer.frame = self.view.bounds;
    [self.view.layer addSublayer:previewLayer];
    
    // go!
    
    [captureSession startRunning];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    // Drop file to raw 264 track
    h264File = [documentsDirectory stringByAppendingPathComponent:@"test.h264"];
    [fileManager removeItemAtPath:h264File error:nil];
    [fileManager createFileAtPath:h264File contents:nil attributes:nil];
    
    // Open the file using POSIX as this is anyway a test application
    fileH264Handle = [NSFileHandle fileHandleForWritingAtPath:h264File];
//
//    // Drop file to raw aac track
//    aacFile = [documentsDirectory stringByAppendingPathComponent:@"test.aac"];
//    [fileManager removeItemAtPath:aacFile error:nil];
//    [fileManager createFileAtPath:aacFile contents:nil attributes:nil];
//    
//    // Open the file using POSIX as this is anyway a test application
//    fileAACHandle = [NSFileHandle fileHandleForWritingAtPath:aacFile];
    
    [rtsp connect:@"192.168.0.144" port:1935 stream:@"mpegts"];
}

- (void)statusBarOrientationDidChange:(NSNotification*)notification {
    [self setRelativeVideoOrientation];
}

- (void)setRelativeVideoOrientation {
    switch ([[UIDevice currentDevice] orientation]) {
        case UIInterfaceOrientationPortrait:
#if defined(__IPHONE_8_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_8_0
        case UIInterfaceOrientationUnknown:
#endif
            connectionVideo.videoOrientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            connectionVideo.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            connectionVideo.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationLandscapeRight:
            connectionVideo.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        default:
            break;
    }
}

- (void) stopCamera
{
    [captureSession stopRunning];
    [previewLayer removeFromSuperlayer];
    [rtsp close];
    [fileH264Handle closeFile];
    fileH264Handle = NULL;
//    [fileAACHandle closeFile];
//    fileAACHandle = NULL;
}

-(void) captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection
{
    if(connection == connectionVideo)
    {
//        NSLog( @"frame captured at ");
        [h264Encoder encode:sampleBuffer];
    }
    else if(connection == connectionAudio)
    {
//        NSLog( @"audio captured at ");
        [aacEncoder encode:sampleBuffer];
    }
}

#pragma mark -  H264HWEncoderDelegate declare

- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps timestamp:(CMTime)timestamp
{
//    NSLog(@"gotSpsPps %d %d", (int)[sps length], (int)[pps length]);
    
    [fileH264Handle writeData:sps];
    [fileH264Handle writeData:pps];
    
    NSMutableData *data = [NSMutableData dataWithData:sps];
    [data appendData:pps];
    
    [rtsp publish:data timestamp:timestamp];
}

- (void)gotH264EncodedData:(NSData*)data timestamp:(CMTime)timestamp
{
//    NSLog(@"gotH264EncodedData %d", (int)[data length]);
    
    if (fileH264Handle != NULL)
    {
        [fileH264Handle writeData:data];
    }
    
    [rtsp publish:data timestamp:timestamp];
}

#pragma mark - AACEncoderDelegate declare

- (void)gotAACEncodedData:(NSData*)data timestamp:(CMTime)timestamp error:(NSError*)error
{
//    NSLog(@"gotAACEncodedData %d", (int)[data length]);
    
//    if (fileAACHandle != NULL)
//    {
//        [fileAACHandle writeData:data];
//    }
    
    [rtsp publish:data timestamp:timestamp];
}

@end
