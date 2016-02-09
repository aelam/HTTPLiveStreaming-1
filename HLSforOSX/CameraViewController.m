//
//  ViewController.m
//  HLSforOSX
//
//  Created by Byeong-uk Park on 2016. 2. 9..
//  Copyright © 2016년 Metapleasure. All rights reserved.
//

#import "CameraViewController.h"
#import "RTSPClient.h"
#import "RTPClient.h"
#import <CoreAudio/CoreAudio.h>

@interface CameraViewController () <RTSPClientDelegate>
{
    H264HWEncoder *h264Encoder;
    AVCaptureSession *captureSession;
    bool startCalled;
    AVCaptureVideoPreviewLayer *previewLayer;
    NSString *h264File;
    NSString *aacFile;
    NSFileHandle *fileH264Handle;
    NSFileHandle *fileAACHandle;
    AVCaptureConnection* connectionVideo;
    AVCaptureConnection* connectionAudio;
    RTSPClient *rtsp;
    RTPClient *rtp;
}
@property (weak, nonatomic) IBOutlet NSButton *StartStopButton;
@property (weak, nonatomic) IBOutlet NSView *preview;
@end

@implementation CameraViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    h264Encoder = [[H264HWEncoder alloc] init];
    [h264Encoder setOutputSize:CGSizeMake(640, 360)];
    h264Encoder.delegate = self;
    
    startCalled = true;
    
    rtsp = [[RTSPClient alloc] init];
    rtsp.delegate = self;
    
    rtp = [[RTPClient alloc] init];
    
    [self initCamera];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Update the view, if already loaded.
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
        [_StartStopButton setTitle:@"Stop"];
    }
    else
    {
        [_StartStopButton setTitle:@"Start"];
        startCalled = true;
        [self stopCamera];
    }
}

#pragma mark - Camera Control

- (void) initCamera
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
    
    [outputVideoDevice setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
    
    AVCaptureAudioDataOutput *outputAudioDevice = [[AVCaptureAudioDataOutput alloc] init];
    
    NSDictionary *audioSettings = @{AVFormatIDKey : @(kAudioFormatMPEG4AAC), AVSampleRateKey : @44100, AVEncoderBitRateKey : @64000, AVNumberOfChannelsKey : @1};
    outputAudioDevice.audioSettings = audioSettings;
    
    [outputAudioDevice setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
    
    // initialize capture session
    
    captureSession = [[AVCaptureSession alloc] init];
    
    [captureSession addInput:inputCameraDevice];
    [captureSession addInput:inputMicrophoneDevice];
    [captureSession addOutput:outputVideoDevice];
    [captureSession addOutput:outputAudioDevice];
    
    // begin configuration for the AVCaptureSession
    [captureSession beginConfiguration];
    
    // picture resolution
    [captureSession setSessionPreset:[NSString stringWithString:AVCaptureSessionPreset1280x720]];
    
    connectionVideo = [outputVideoDevice connectionWithMediaType:AVMediaTypeVideo];
    connectionAudio = [outputAudioDevice connectionWithMediaType:AVMediaTypeAudio];
//    [self setRelativeVideoOrientation];
    
//    NSNotificationCenter* notify = [NSNotificationCenter defaultCenter];
//    
//    [notify addObserver:self
//               selector:@selector(statusBarOrientationDidChange:)
//                   name:@"StatusBarOrientationDidChange"
//                 object:nil];
    
    
    [captureSession commitConfiguration];
    
    // make preview layer and add so that camera's view is displayed on screen
    
    previewLayer = [AVCaptureVideoPreviewLayer    layerWithSession:captureSession];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    
    previewLayer.frame = self.preview.bounds;
}

- (void) startCamera
{
    [self.preview.layer addSublayer:previewLayer];
    
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

    // Drop file to raw aac track
    aacFile = [documentsDirectory stringByAppendingPathComponent:@"test.aac"];
    [fileManager removeItemAtPath:aacFile error:nil];
    [fileManager createFileAtPath:aacFile contents:nil attributes:nil];

    // Open the file using POSIX as this is anyway a test application
    fileAACHandle = [NSFileHandle fileHandleForWritingAtPath:aacFile];

//    [rtsp connect:@"192.168.0.3" port:1935 instance:@"app" stream:@"mpegts.stream"];
    
    rtp.address = @"192.168.0.3";
    rtp.port = 10000;
}

- (void) stopCamera
{
    [h264Encoder invalidate];
    [captureSession stopRunning];
    [previewLayer removeFromSuperlayer];
    [rtsp close];
    [fileH264Handle closeFile];
    fileH264Handle = NULL;
    [fileAACHandle closeFile];
    fileAACHandle = NULL;
}

/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw
 *  AAC data.
 *
 *  Note the packetLen must count in the ADTS header itself.
 *  See: http://wiki.multimedia.cx/index.php?title=ADTS
 *  Also: http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
 **/
- (NSData*) adtsDataForPacketLength:(NSUInteger)packetLength {
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 4;  //44.1KHz
    int chanCfg = 1;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF;	// 11111111  	= syncword
    packet[1] = (char)0xF9;	// 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

//- (void)statusBarOrientationDidChange:(NSNotification*)notification {
//    [self setRelativeVideoOrientation];
//}
//
//- (void)setRelativeVideoOrientation {
//    switch ([[UIDevice currentDevice] orientation]) {
//        case UIInterfaceOrientationPortrait:
//#if defined(__IPHONE_8_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_8_0
//        case UIInterfaceOrientationUnknown:
//#endif
//            connectionVideo.videoOrientation = AVCaptureVideoOrientationPortrait;
//            break;
//        case UIInterfaceOrientationPortraitUpsideDown:
//            connectionVideo.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
//            break;
//        case UIInterfaceOrientationLandscapeLeft:
//            connectionVideo.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
//            break;
//        case UIInterfaceOrientationLandscapeRight:
//            connectionVideo.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
//            break;
//        default:
//            break;
//    }
//}

-(void) captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection
{
    if(connection == connectionVideo)
    {
//        NSLog( @"frame captured at ");
        [h264Encoder encode:sampleBuffer];
    }
    else if(connection == connectionAudio)
    {
        CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        size_t length, totalLength;
        char *dataPointer;
        CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
        NSData *rawAAC = [NSData dataWithBytes:dataPointer length:totalLength];
        NSData *adtsHeader = [self adtsDataForPacketLength:totalLength];
        NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
        [fullData appendData:rawAAC];
        
        [fileAACHandle writeData:fullData];
        
        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        [rtp publish:fullData timestamp:timestamp payloadType:96];
    }
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

- (void)onRTSP:(RTSPClient *)rtsp didSETUP_AUDIOWithServerPort:(NSNumber *)server_port
{
    
}

- (void)onRTSP:(RTSPClient *)rtsp didSETUP_VIDEOWithServerPort:(NSNumber *)server_port
{
    
}

#pragma mark -  H264HWEncoderDelegate declare

- (void)gotH264EncodedData:(NSData*)data timestamp:(CMTime)timestamp
{
    NSLog(@"gotH264EncodedData %d", (int)[data length]);

//    if (fileH264Handle != NULL)
//    {
        [fileH264Handle writeData:data];
//    }
    
    [rtp publish:data timestamp:timestamp payloadType:98];
}

#pragma mark - AACEncoderDelegate declare

- (void)gotAACEncodedData:(NSData*)data timestamp:(CMTime)timestamp error:(NSError*)error
{
//    NSLog(@"gotAACEncodedData %d", (int)[data length]);

//    if (fileAACHandle != NULL)
//    {
//        [fileAACHandle writeData:data];
//    }

//    [rtp publish:data timestamp:timestamp payloadType:96];
}

@end
