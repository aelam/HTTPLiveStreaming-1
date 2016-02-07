//
//  ViewController.m
//  HLSforOSX
//
//  Created by Byeong-uk Park on 2016. 2. 7..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import "ViewController.h"
#import "RTSPClient.h"
#import "RTPClient.h"

@interface ViewController () <RTSPClientDelegate>
{
    H264HWEncoder *h264Encoder;
    AACEncoder *aacEncoder;
    AVCaptureSession *captureSession;
    AVCaptureVideoPreviewLayer *previewLayer;
//    NSString *h264File;
//    NSString *aacFile;
//    NSFileHandle *fileH264Handle;
//    NSFileHandle *fileAACHandle;
    AVCaptureConnection* connectionVideo;
//    AVCaptureConnection* connectionAudio;
    RTSPClient *rtsp;
    RTPClient *rtp_video;
    RTPClient *rtp_audio;
}
@property (weak, nonatomic) IBOutlet NSView *preview;
@end

@implementation ViewController

- (void)dealloc {
    [self stopCamera];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    h264Encoder = [[H264HWEncoder alloc] init];
    h264Encoder.delegate = self;
    
    aacEncoder = [[AACEncoder alloc] init];
    aacEncoder.delegate = self;
    
    rtsp = [[RTSPClient alloc] init];
    rtsp.delegate = self;
    
    rtp_video = [[RTPClient alloc] init];
    rtp_audio = [[RTPClient alloc] init];
    
    [self initCamera];
}

- (void)viewDidAppear {
    [self startCamera];
    [super viewDidAppear];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

#pragma mark - Camera Control

- (void) initCamera
{
    // make input device
    
    NSError *deviceError;
    
    AVCaptureDevice *cameraDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
//    AVCaptureDevice *microphoneDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    
    AVCaptureDeviceInput *inputCameraDevice = [AVCaptureDeviceInput deviceInputWithDevice:cameraDevice error:&deviceError];
//    AVCaptureDeviceInput *inputMicrophoneDevice = [AVCaptureDeviceInput deviceInputWithDevice:microphoneDevice error:&deviceError];
    
    // make output device
    
    AVCaptureVideoDataOutput *outputVideoDevice = [[AVCaptureVideoDataOutput alloc] init];
    
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* val = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:val forKey:key];
    outputVideoDevice.videoSettings = videoSettings;
    
    dispatch_queue_t queue = dispatch_queue_create("com.metapleasure.HTTPLiveStreaming", NULL);
    [outputVideoDevice setSampleBufferDelegate:self queue:queue];
    
//    AVCaptureAudioDataOutput *outputAudioDevice = [[AVCaptureAudioDataOutput alloc] init];
//    [outputAudioDevice setSampleBufferDelegate:self queue:queue];
    
    // initialize capture session
    
    captureSession = [[AVCaptureSession alloc] init];
    
    [captureSession addInput:inputCameraDevice];
//    [captureSession addInput:inputMicrophoneDevice];
    [captureSession addOutput:outputVideoDevice];
//    [captureSession addOutput:outputAudioDevice];
    
    // begin configuration for the AVCaptureSession
    [captureSession beginConfiguration];
    
    // picture resolution
    [captureSession setSessionPreset:[NSString stringWithString:AVCaptureSessionPreset640x480]];
    
    connectionVideo = [outputVideoDevice connectionWithMediaType:AVMediaTypeVideo];
//    connectionAudio = [outputAudioDevice connectionWithMediaType:AVMediaTypeAudio];
    
    [captureSession commitConfiguration];
}

- (void) startCamera
{
    // make preview layer and add so that camera's view is displayed on screen
    
    previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    
    previewLayer.frame = self.view.bounds;
    
    [self.preview.layer addSublayer:previewLayer];
    
    [captureSession startRunning];
    
//    NSFileManager *fileManager = [NSFileManager defaultManager];
//    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
//    NSString *documentsDirectory = [paths objectAtIndex:0];
//
//    // Drop file to raw 264 track
//    h264File = [documentsDirectory stringByAppendingPathComponent:@"test.h264"];
//    [fileManager removeItemAtPath:h264File error:nil];
//    [fileManager createFileAtPath:h264File contents:nil attributes:nil];
//
//    // Open the file using POSIX as this is anyway a test application
//    fileH264Handle = [NSFileHandle fileHandleForWritingAtPath:h264File];
//
//    // Drop file to raw aac track
//    aacFile = [documentsDirectory stringByAppendingPathComponent:@"test.aac"];
//    [fileManager removeItemAtPath:aacFile error:nil];
//    [fileManager createFileAtPath:aacFile contents:nil attributes:nil];
//
//    // Open the file using POSIX as this is anyway a test application
//    fileAACHandle = [NSFileHandle fileHandleForWritingAtPath:aacFile];
    
    [rtsp connect:@"192.168.0.3" port:1935 stream:@"mpegts"];
    
    rtp_video.address = @"192.168.0.3";
    rtp_video.port = 10001; // This is an meanless information
    
    rtp_audio.address = @"192.168.0.3";
    rtp_audio.port = 10000; // This is an meanless information
}

- (void) stopCamera
{
    [captureSession stopRunning];
    [previewLayer removeFromSuperlayer];
    [rtsp close];
//    [fileH264Handle closeFile];
//    fileH264Handle = NULL;
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
//    else if(connection == connectionAudio)
//    {
//        NSLog( @"audio captured at ");
//        [aacEncoder encode:sampleBuffer];
//    }
}

#pragma mark - RTSPClientDelegate

- (void)onRTSPDidConnectedOK:(RTSPClient *)_rtsp
{
}

- (void)onRTSPDidConnectedFailed:(RTSPClient *)_rtsp
{
    [rtsp close];
}

- (void)onRTSPDidDisConnected:(RTSPClient *)_rtsp
{
    [rtsp close];
}

- (void)onRTSP:(RTSPClient *)rtsp didSETUP_AUDIOWithServerPort:(NSInteger)server_port
{
    rtp_audio.port = server_port; // We have use this port given from server
}

- (void)onRTSP:(RTSPClient *)rtsp didSETUP_VIDEOWithServerPort:(NSInteger)server_port
{
    rtp_video.port = server_port; // We have use this port given from server
}

#pragma mark -  H264HWEncoderDelegate declare

- (void)gotH264EncodedData:(NSData*)data timestamp:(CMTime)timestamp
{
//    NSLog(@"gotH264EncodedData %d", (int)[data length]);

//    if (fileH264Handle != NULL)
//    {
//        [fileH264Handle writeData:data];
//    }
    
    [rtp_video publish:data timestamp:timestamp];
}

#pragma mark - AACEncoderDelegate declare

- (void)gotAACEncodedData:(NSData*)data timestamp:(CMTime)timestamp error:(NSError*)error
{
//    NSLog(@"gotAACEncodedData %d", (int)[data length]);

//    if (fileAACHandle != NULL)
//    {
//        [fileAACHandle writeData:data];
//    }

//    [rtp_audio publish:data timestamp:timestamp];
}

@end
