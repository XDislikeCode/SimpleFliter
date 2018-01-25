//
//  LVCaptureController.m
//  CaptureDemo
//
//  Created by canoe on 2017/11/2.
//  Copyright © 2017年 canoe. All rights reserved.
//

#import "LVCaptureController.h"
#import "GPUImage.h"

typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);

@interface LVCaptureController ()<UIGestureRecognizerDelegate,GPUImageVideoCameraDelegate,GPUImageMovieWriterDelegate>

@property(nonatomic, strong) GPUImageStillCamera *videoCamera;//输入源
@property (nonatomic, strong) GPUImageView *filterView; //显示的View
@property(nonatomic, strong) GPUImageOutput<GPUImageInput> *filter;//最后处理的滤镜
@property(nonatomic, strong) GPUImageMovieWriter *movieWriter;//视频录制
@property(nonatomic, strong) NSURL *outputUrl; //视频输出地址
@property (copy, nonatomic) NSString *cameraQuality;//拍摄质量

//聚焦
@property (strong, nonatomic) UITapGestureRecognizer *tapGesture;//点击手势
@property (strong, nonatomic) CALayer *focusBoxLayer;//聚焦图层
@property (strong, nonatomic) CAAnimation *focusBoxAnimation;//聚焦动画

//缩放
@property (strong, nonatomic) UIPinchGestureRecognizer *pinchGesture;//放大缩小
@property (nonatomic, assign) CGFloat beginGestureScale;//原始放大倍数
@property (nonatomic, assign) CGFloat effectiveScale;//有效倍数

@property (nonatomic, copy) void (^didRecordCompletionBlock)(LVCaptureController *camera, NSURL *outputFileUrl, NSError *error);//视频拍摄完成回调

@end

NSString *const LVCameraErrorDomain = @"LVCameraErrorDomain";

@implementation LVCaptureController

#pragma mark - Initialize

-(instancetype) init
{
    return [self initWithQuality:AVCaptureSessionPresetHigh];
}

-(instancetype) initWithQuality:(NSString *)quality
{
    return [self initWithQuality:quality position:LVCapturePositionRear];
}

-(instancetype) initWithQuality:(NSString *)quality position:(LVCapturePosition)position
{
    return [self initWithQuality:quality position:position enableRecording:NO];
}

-(instancetype) initWithQuality:(NSString *)quality position:(LVCapturePosition)position enableRecording:(BOOL)recordingEnabled
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        [self setupWithQuality:quality position:position enableRecording:recordingEnabled];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self setupWithQuality:AVCaptureSessionPresetHigh
                      position:LVCapturePositionRear
                  enableRecording:NO];
    }
    return self;
}

-(void)setupWithQuality:(NSString *)quality position:(LVCapturePosition)position enableRecording:(BOOL)recordingEnabled
{
    _cameraQuality = quality;
    _position = position;
    _recordingEnabled = recordingEnabled;
    _flash = LVCaptureFlashOff;
    _mirror = LVCaptureMirrorAuto;
    _whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
    _useDeviceOrientation = YES;
    _tapToFocus = NO;
    _recording = NO;
    _zoomingEnabled = YES;
    _effectiveScale = 1.0f;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.autoresizingMask = UIViewAutoresizingNone;
    
    self.preview = [[UIView alloc] initWithFrame:CGRectZero];
    self.preview.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.preview];
    
    //聚焦
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(previewTapped:)];
    self.tapGesture.numberOfTapsRequired = 1;
    self.tapGesture.delaysTouchesEnded = NO;//手势识别失败立即发送touchend结束触摸事件
    [self.preview addGestureRecognizer:self.tapGesture];
    
    //缩放
    if (_zoomingEnabled) {
        self.pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(previewPinned:)];
        self.pinchGesture.delegate = self;
        [self.preview addGestureRecognizer:self.pinchGesture];
    }
    
    //添加聚焦动画
    [self addDefaultFocusBox];
}

#pragma mark - Camera
- (void)attachToViewController:(UIViewController *)vc withFrame:(CGRect)frame
{
    [vc addChildViewController:self];
    self.view.frame = frame;
    [vc.view addSubview:self.view];
    [self didMoveToParentViewController:vc];
}

- (void)start
{
    [LVCaptureController requestCameraPermission:^(BOOL granted) {
        if (granted) {
            //如果是视频录制，额外需要麦克风权限  没有麦克风权限的话就没有声音
            if (self.recordingEnabled) {
                 [self initialize];
//                [LVCaptureController requestMicrophonePermission:^(BOOL granted) {
//                    if (granted) {
                    
//                    }else
//                    {
//                        NSError *error = [NSError errorWithDomain:LVCameraErrorDomain
//                                                             code:LVCameraErrorCodeCameraPermission
//                                                         userInfo:nil];
//                        [self passError:error];
//                    }
//                }];
            }else
            {
                [self initialize];
            }
        }else
        {
            NSError *error = [NSError errorWithDomain:LVCameraErrorDomain
                                                 code:LVCameraErrorCodeCameraPermission
                                             userInfo:nil];
            [self passError:error];
        }
    }];
}

//初始化
-(void)initialize
{
    if (!_videoCamera) {
        AVCaptureDevicePosition devicePosition;
        switch (self.position) {
            case LVCapturePositionRear:
                if([self.class isRearCameraAvailable]) {
                    devicePosition = AVCaptureDevicePositionBack;
                } else {
                    devicePosition = AVCaptureDevicePositionFront;
                    _position = LVCapturePositionFront;
                }
                break;
            case LVCapturePositionFront:
                if([self.class isFrontCameraAvailable]) {
                    devicePosition = AVCaptureDevicePositionFront;
                } else {
                    devicePosition = AVCaptureDevicePositionBack;
                    _position = LVCapturePositionRear;
                }
                break;
            default:
                devicePosition = AVCaptureDevicePositionUnspecified;
                break;
        }
        _videoCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:self.cameraQuality cameraPosition:devicePosition];
        _videoCamera.outputImageOrientation = UIInterfaceOrientationPortrait;   //输出图片方向
        _videoCamera.horizontallyMirrorFrontFacingCamera = YES; //前置相机是否镜像
//        _videoCamera.inputCamera.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        
        self.filter = [[GPUImageFilter alloc] init];
        
        self.filterView = [[GPUImageView alloc] initWithFrame:self.preview.bounds];
        self.filterView.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
        [self.preview addSubview:self.filterView];
        
        [_videoCamera addTarget:self.filter];
        [self.filter addTarget:self.filterView];
        
        if (self.isRecordingEnabled) {
            [_videoCamera addAudioInputsAndOutputs];
        }
    }
    [self.videoCamera startCameraCapture];
    
//    if (!_session) {
//        _session = [[AVCaptureSession alloc] init];
//        _session.sessionPreset = self.cameraQuality;
        
        //preView layer
//        CGRect bounds = self.preview.layer.bounds;
//        _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
//        _captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
//        _captureVideoPreviewLayer.bounds = bounds;
//        _captureVideoPreviewLayer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
//        [self.preview.layer addSublayer:_captureVideoPreviewLayer];
        
        //获取相机设备
//        AVCaptureDevicePosition devicePosition;
//        switch (self.position) {
//            case LVCapturePositionRear:
//                if([self.class isRearCameraAvailable]) {
//                    devicePosition = AVCaptureDevicePositionBack;
//                } else {
//                    devicePosition = AVCaptureDevicePositionFront;
//                    _position = LVCapturePositionFront;
//                }
//                break;
//                case LVCapturePositionFront:
//                if([self.class isFrontCameraAvailable]) {
//                    devicePosition = AVCaptureDevicePositionFront;
//                } else {
//                    devicePosition = AVCaptureDevicePositionBack;
//                    _position = LVCapturePositionRear;
//                }
//                break;
//            default:
//                devicePosition = AVCaptureDevicePositionUnspecified;
//                break;
//        }
        
//        if (devicePosition == AVCaptureDevicePositionUnspecified) {
//            self.videoCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
//        }else
//        {
//            self.videoCaptureDevice = [self cameraWithPosition:devicePosition];
//        }
        
        //配置输入数据管理对象
//        NSError *error = nil;
//        _videoDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:self.videoCaptureDevice error:&error];
//
//        if (!_videoDeviceInput) {
//            [self passError:error];
//            return;
//        }
//
//        if ([_session canAddInput:_videoDeviceInput]) {
//            [_session addInput:_videoDeviceInput];
//            self.captureVideoPreviewLayer.connection.videoOrientation = [self orientationForConnection];
//        }
//
//        if (self.recordingEnabled) {
//            _audioCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
//            _audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:_audioCaptureDevice error:&error];
//            if (!_audioDeviceInput) {
//                [self passError:error];
//            }
//
//            if ([_session canAddInput:_audioDeviceInput]) {
//                [_session addInput:_audioDeviceInput];
//            }
//
//            _movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
//            [_movieFileOutput setMovieFragmentInterval:kCMTimeInvalid];
//            if ([self.session canAddOutput:_movieFileOutput]) {
//                [self.session addOutput:_movieFileOutput];
//            }
//        }
        
//        //白平衡
//        self.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
//
//        //输出数据管理对象
//        self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
//        NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:AVVideoCodecJPEG,AVVideoCodecKey, nil];
//        [self.stillImageOutput setOutputSettings:outputSettings];
//        [self.session addOutput:self.stillImageOutput];
//    }
    
//    if (![self.captureVideoPreviewLayer.connection isEnabled]) {
//        [self.captureVideoPreviewLayer.connection setEnabled:YES];
//    }
//
//    [self.session startRunning];
}

- (void)stop
{
    [self.videoCamera stopCameraCapture];
}

#pragma mark - image Capture
-(void)capture:(void (^)(LVCaptureController *capture,UIImage *image, NSError *error))onCapture exactSeenImage:(BOOL)exactSeenImage animationBlock:(void (^)(void))animationBlock
{
    if (!self.videoCamera.captureSession) {
        NSError *error = [NSError errorWithDomain:LVCameraErrorDomain code:LVCameraErrorCodeSession userInfo:nil];
        onCapture(self,nil,error);
        return;
    }
    //根据设备输出获得链接
    self.videoCamera.outputImageOrientation = (NSInteger)[self orientationForConnection];
    
    BOOL flashActive =  self.videoCamera.inputCamera.flashActive;
    if (!flashActive && animationBlock) {
        animationBlock();
    }
    
    [self.videoCamera capturePhotoAsImageProcessedUpToFilter:nil withCompletionHandler:^(UIImage *processedImage, NSError *error) {
        UIImage *image = nil;
        if (onCapture) {
            dispatch_async(dispatch_get_main_queue(), ^{
                onCapture(self,image,error);
            });
        }
    }];
    
    
//    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:captureConnection completionHandler:^(CMSampleBufferRef  _Nullable imageDataSampleBuffer, NSError * _Nullable error) {
//        UIImage *image = nil;
//
//        if (imageDataSampleBuffer) {
//            NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
//            image = [UIImage imageWithData:imageData];
//            if (exactSeenImage) {
//                image = [self cropImage:image usingPreviewLayer:self.captureVideoPreviewLayer];
//            }
//        }
//
//
//    }];
}

-(void)capture:(void (^)(LVCaptureController *camera, UIImage *image, NSError *error))onCapture exactSeenImage:(BOOL)exactSeenImage
{
    [self capture:onCapture exactSeenImage:exactSeenImage animationBlock:nil];
    
//    [self capture:onCapture exactSeenImage:exactSeenImage animationBlock:^() {
//        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
//        animation.duration = 0.1;
//        animation.autoreverses = YES;
//        animation.repeatCount = 0.0;
//        animation.fromValue = [NSNumber numberWithFloat:1.0];
//        animation.toValue = [NSNumber numberWithFloat:0.1];
//        animation.fillMode = kCAFillModeForwards;
//        animation.removedOnCompletion = NO;
//        [layer addAnimation:animation forKey:@"animateOpacity"];
//    }];
}

-(void)capture:(void (^)(LVCaptureController *camera, UIImage *image, NSError *error))onCapture
{
    [self capture:onCapture exactSeenImage:NO];
}


#pragma mark - Video Capture
- (void)startRecordingWithOutputUrl:(NSURL *)url didRecord:(void (^)(LVCaptureController *, NSURL *, NSError *))completionBlock
{
    if (!self.recordingEnabled) {
        NSError *error = [NSError errorWithDomain:LVCameraErrorDomain code:LVCameraErrorCodeVideoNotEnabled userInfo:nil];
        [self passError:error];
        return;
    }
    
    if (self.flash == LVCaptureFlashOn) {
        [self enableTorch:YES];
    }
    
    self.videoCamera.outputImageOrientation = (NSInteger)[self orientationForConnection];
    
    self.didRecordCompletionBlock = completionBlock;
    
    self.outputUrl = url;
    self.movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:url size:CGSizeMake(480, 640)];
    self.movieWriter.encodingLiveVideo = YES;
    [self.filter addTarget:self.movieWriter];
    self.videoCamera.audioEncodingTarget = self.movieWriter;
    [self.movieWriter startRecording];
    self.recording = YES;
//    [self.movieFileOutput startRecordingToOutputFileURL:url recordingDelegate:self];
}

-(void)stopRecording
{
    if (!self.recordingEnabled) {
        return;
    }
    
    self.recording = NO;
    [self.filter removeTarget:self.movieWriter];
    self.videoCamera.audioEncodingTarget = nil;
    [self.movieWriter finishRecording];
}

//-(void)captureOutput:(AVCaptureFileOutput *)output didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray<AVCaptureConnection *> *)connections
//{
//
//    if (self.onStartRecording) {
//        self.onStartRecording(self);
//    }
//}

-(void)movieRecordingCompleted
{
    self.recording = NO;
    [self enableTorch:NO];
    [self.filter removeTarget:self.movieWriter];
    self.videoCamera.audioEncodingTarget = nil;
    [self.movieWriter finishRecording];
    
    if (self.didRecordCompletionBlock) {
        self.didRecordCompletionBlock(self, self.outputUrl, nil);
    }
}

-(void)movieRecordingFailedWithError:(NSError *)error
{
    self.recording = NO;
    [self enableTorch:NO];
    [self.filter removeTarget:self.movieWriter];
    self.videoCamera.audioEncodingTarget = nil;
    [self.movieWriter finishRecording];
    
    if (self.didRecordCompletionBlock) {
        self.didRecordCompletionBlock(self, self.outputUrl, error);
    }
}

- (void)enableTorch:(BOOL)enabled
{
    // check if the device has a torch, otherwise don't do anything
    if([self isTorchAvailable]) {
        AVCaptureTorchMode torchMode = enabled ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
        [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
            [self.videoCamera.inputCamera setTorchMode:torchMode];
        }];
    }
}

#pragma mark - Pinch scale
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if ( [gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]] ) {
        _beginGestureScale = _effectiveScale;
    }
    return YES;
}

- (void)previewPinned:(UIPinchGestureRecognizer *)recognizer
{
    BOOL allTouchesAreOnThePreviewLayer = YES;
    NSUInteger numTouches = [recognizer numberOfTouches], i;
    for ( i = 0; i < numTouches; ++i ) {
        CGPoint location = [recognizer locationOfTouch:i inView:self.preview];
        CGPoint convertedLocation = [self.preview.layer convertPoint:location fromLayer:self.view.layer];
        if ( ! [self.preview.layer containsPoint:convertedLocation] ) {
            allTouchesAreOnThePreviewLayer = NO;
            break;
        }
    }
    
    if (allTouchesAreOnThePreviewLayer) {
        _effectiveScale = _beginGestureScale * recognizer.scale;
        if (_effectiveScale < 1.0f)
            _effectiveScale = 1.0f;
        if (_effectiveScale > self.videoCamera.inputCamera.activeFormat.videoMaxZoomFactor)
            _effectiveScale = self.videoCamera.inputCamera.activeFormat.videoMaxZoomFactor;
        
        [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
            [self.videoCamera.inputCamera rampToVideoZoomFactor:_effectiveScale withRate:100];
        }];
    }
}

#pragma mark - Focus
- (void)addDefaultFocusBox
{
    CALayer *focusBox = [[CALayer alloc] init];
    focusBox.cornerRadius = 5.0f;
    focusBox.bounds = CGRectMake(0.0f, 0.0f, 70, 60);
    focusBox.borderWidth = 3.0f;
    focusBox.borderColor = [[UIColor yellowColor] CGColor];
    focusBox.opacity = 0.0f;
    [self.view.layer addSublayer:focusBox];
    
    CABasicAnimation *focusBoxAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    focusBoxAnimation.duration = 0.75;
    focusBoxAnimation.autoreverses = NO;
    focusBoxAnimation.repeatCount = 0.0;
    focusBoxAnimation.fromValue = [NSNumber numberWithFloat:1.0];
    focusBoxAnimation.toValue = [NSNumber numberWithFloat:0.0];
    
    [self clickFocusBox:focusBox animation:focusBoxAnimation];
}
-(void)clickFocusBox:(CALayer *)layer animation:(CAAnimation *)animation
{
    self.focusBoxLayer = layer;
    self.focusBoxAnimation = animation;
}

- (void)previewTapped:(UIGestureRecognizer *)gestureRecognizer
{
    if(!self.tapToFocus) {
        return;
    }
    CGPoint touchedPoint = [gestureRecognizer locationInView:self.preview];
//    CGPoint pointOfInterest = [self.preview captureDevicePointOfInterestForPoint:touchedPoint];
    [self focusAtPoint:touchedPoint];
    [self showFocusBox:touchedPoint];
}

//更改聚焦状态
- (void)focusAtPoint:(CGPoint)point
{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
         if (captureDevice.isFocusPointOfInterestSupported && [captureDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
             captureDevice.focusPointOfInterest = point;
             captureDevice.focusMode = AVCaptureFocusModeContinuousAutoFocus;
         }
    }];
}

//显示聚焦动画
- (void)showFocusBox:(CGPoint)point
{
    if(self.focusBoxLayer) {
        // clear animations
        [self.focusBoxLayer removeAllAnimations];
        
        // move layer to the touch point
        [CATransaction begin];
        [CATransaction setValue: (id) kCFBooleanTrue forKey: kCATransactionDisableActions];
        self.focusBoxLayer.position = point;
        [CATransaction commit];
    }
    
    if(self.focusBoxAnimation) {
        // run the animation
        [self.focusBoxLayer addAnimation:self.focusBoxAnimation forKey:@"animateOpacity"];
    }
}

#pragma mark - setter

-(void)setWhiteBalanceMode:(AVCaptureWhiteBalanceMode)whiteBalanceMode
{
    if ([self.videoCamera.inputCamera isWhiteBalanceModeSupported:whiteBalanceMode]) {
        [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
            [self.videoCamera.inputCamera setWhiteBalanceMode:whiteBalanceMode];
        }];
    }
}

//-(void)setMirror:(LVCaptureMirror)mirror
//{
//    _mirror = mirror;
//
//    if (!self.session) {
//        return;
//    }
//
//    AVCaptureConnection *videoConnection = [_movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
//    AVCaptureConnection *pictureConnection = [_stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
//
//    switch (mirror) {
//        case LVCaptureMirrorOff:
//            if ([videoConnection isVideoMirroringSupported]) {
//                [videoConnection setVideoMirrored:NO];
//            }
//
//            if ([pictureConnection isVideoMirroringSupported]) {
//                [pictureConnection setVideoMirrored:NO];
//            }
//            break;
//        case LVCaptureMirrorOn:
//            if ([videoConnection isVideoMirroringSupported]) {
//                [videoConnection setVideoMirrored:YES];
//            }
//
//            if ([pictureConnection isVideoMirroringSupported]) {
//                [pictureConnection setVideoMirrored:YES];
//            }
//            break;
//        case LVCaptureMirrorAuto:
//        {
//            BOOL shouldMirror = (_position == LVCapturePositionFront);
//            if ([videoConnection isVideoMirroringSupported]) {
//                [videoConnection setVideoMirrored:shouldMirror];
//            }
//
//            if ([pictureConnection isVideoMirroringSupported]) {
//                [pictureConnection setVideoMirrored:shouldMirror];
//            }
//        }
//            break;
//
//        default:
//            break;
//    }
//    return;
//}

- (void)setCameraPosition:(LVCapturePosition)cameraPosition
{
    if (_position == cameraPosition || !self.videoCamera.captureSession) {
        return;
    }
    
    if(cameraPosition == LVCapturePositionRear && ![self.class isRearCameraAvailable]) {
        return;
    }
    
    if(cameraPosition == LVCapturePositionFront && ![self.class isFrontCameraAvailable]) {
        return;
    }
    //修改摄像头
    if (cameraPosition == LVCapturePositionRear && self.videoCamera.cameraPosition != AVCaptureDevicePositionBack) {
        [self.videoCamera rotateCamera];
    }
    
    if (cameraPosition == LVCapturePositionFront && self.videoCamera.cameraPosition != AVCaptureDevicePositionFront) {
        [self.videoCamera rotateCamera];
    }
    _position = cameraPosition;
    
//    //开始配置
//    [self.session beginConfiguration];
//
//    //移除原始数据输入对象
//    [self.session removeInput:self.videoDeviceInput];
//
//    //获取新的数据输入对象
//    AVCaptureDevice *device = nil;
//    //如果当前的输入设备是后置摄像头 那么获取前置摄像头
//    if (self.videoDeviceInput.device.position == AVCaptureDevicePositionBack) {
//        device = [self cameraWithPosition:AVCaptureDevicePositionFront];
//    }else
//    {
//        device = [self cameraWithPosition:AVCaptureDevicePositionBack];
//    }
//
//    if (!device) {
//        return;
//    }
//
//    NSError *error = nil;
//    AVCaptureDeviceInput *videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:device error:&error];
//    if(error) {
//        [self passError:error];
//        [self.session commitConfiguration];
//        return;
//    }
//
//    _position = cameraPosition;
//
//    if ([self.session canAddInput:videoInput]) {
//        [self.session addInput:videoInput];
//    }
//    [self.session commitConfiguration];
//    self.videoCaptureDevice = device;
//    self.videoDeviceInput = videoInput;
//
//    [self setMirror:_mirror];
}

#pragma mark - getter
-(BOOL)isFlashAvailable
{
    return self.videoCamera.inputCamera.hasFlash && self.videoCamera.inputCamera.isFlashAvailable;
}

-(BOOL)isTorchAvailable
{
    return self.videoCamera.inputCamera.hasTorch && self.videoCamera.inputCamera.isTorchAvailable;
}

#pragma mark - Other
 - (LVCapturePosition)changePosition
{
    if (!self.videoCamera.inputCamera) {
        return self.position;
    }
    
    if (self.position == LVCapturePositionFront) {
        self.cameraPosition = LVCapturePositionRear;
    }else
    {
        self.cameraPosition = LVCapturePositionFront;
    }
    
    return self.position;
}

//更新闪光灯模式
- (BOOL)updateFlashMode:(LVCaptureFlash)cameraFlash
{
    if (!self.videoCamera.captureSession)
        return NO;
    
    AVCaptureFlashMode flashMode;
    
    if (cameraFlash == LVCaptureFlashOn) {
        flashMode = AVCaptureFlashModeOn;
    }else if (cameraFlash == LVCaptureFlashAuto)
    {
        flashMode = AVCaptureFlashModeAuto;
    }else
    {
        flashMode = AVCaptureFlashModeOff;
    }
    
    if ([self.videoCamera.inputCamera isFlashModeSupported:flashMode]) {
        NSError *error;
        if([self.videoCamera.inputCamera lockForConfiguration:&error]) {
            self.videoCamera.inputCamera.flashMode = flashMode;
            [self.videoCamera.inputCamera unlockForConfiguration];
            _flash = cameraFlash;
            return YES;
        } else {
            [self passError:error];
            return NO;
        }
    }else{
        return NO;
    }
}

- (void)passError:(NSError *)error
{
    if(self.onError) {
        __weak typeof(self) weakSelf = self;
        self.onError(weakSelf, error);
    }
}

/**
 *  改变设备属性的统一操作方法
 *
 *  @param propertyChange 属性改变操作
 */
-(void)changeDeviceProperty:(PropertyChangeBlock)propertyChange{
    AVCaptureDevice *captureDevice= self.videoCamera.inputCamera;
    NSError *error;
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }else{
        [self passError:error];
    }
}

//返回一个指定的相机设备
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition) position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) return device;
    }
    return nil;
}

//图片裁剪
- (UIImage *)cropImage:(UIImage *)image usingPreviewLayer:(AVCaptureVideoPreviewLayer *)previewLayer
{
    CGRect previewBounds = previewLayer.bounds;
    CGRect outputRect = [previewLayer metadataOutputRectOfInterestForRect:previewBounds];
    
    CGImageRef takenCGImage = image.CGImage;
    size_t width = CGImageGetWidth(takenCGImage);
    size_t height = CGImageGetHeight(takenCGImage);
    CGRect cropRect = CGRectMake(outputRect.origin.x * width, outputRect.origin.y * height,
                                 outputRect.size.width * width, outputRect.size.height * height);
    
    CGImageRef cropCGImage = CGImageCreateWithImageInRect(takenCGImage, cropRect);
    image = [UIImage imageWithCGImage:cropCGImage scale:1 orientation:image.imageOrientation];
    CGImageRelease(cropCGImage);
    
    return image;
}

#pragma mark - Controller
-(void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    self.preview.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    CGRect bounds = self.preview.bounds;
    self.filterView.bounds = bounds;
}

- (AVCaptureVideoOrientation)orientationForConnection
{
    AVCaptureVideoOrientation videoOrientation = AVCaptureVideoOrientationPortrait;
    
    if(self.useDeviceOrientation) {
        switch ([UIDevice currentDevice].orientation) {
            case UIDeviceOrientationLandscapeLeft:
                // yes to the right, this is not bug!
                videoOrientation = AVCaptureVideoOrientationLandscapeRight;
                break;
            case UIDeviceOrientationLandscapeRight:
                videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
                break;
            default:
                videoOrientation = AVCaptureVideoOrientationPortrait;
                break;
        }
    }
    else {
        switch ([[UIApplication sharedApplication] statusBarOrientation]) {
            case UIInterfaceOrientationLandscapeLeft:
                videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
                break;
            case UIInterfaceOrientationLandscapeRight:
                videoOrientation = AVCaptureVideoOrientationLandscapeRight;
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
                break;
            default:
                videoOrientation = AVCaptureVideoOrientationPortrait;
                break;
        }
    }
    
    return videoOrientation;
}

//旋转的时候重新布局
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    // layout subviews is not called when rotating from landscape right/left to left/right
    if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation) && UIInterfaceOrientationIsLandscape(toInterfaceOrientation)) {
        [self.view setNeedsLayout];
    }
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Class Methods Premission

+ (void)requestCameraPermission:(void (^)(BOOL granted))completionBlock
{
    if ([AVCaptureDevice respondsToSelector:@selector(requestAccessForMediaType: completionHandler:)]) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            // return to main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                if(completionBlock) {
                    completionBlock(granted);
                }
            });
        }];
    } else {
        completionBlock(YES);
    }
}

+ (void)requestMicrophonePermission:(void (^)(BOOL granted))completionBlock
{
    if([[AVAudioSession sharedInstance] respondsToSelector:@selector(requestRecordPermission:)]) {
        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
            // return to main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                if(completionBlock) {
                    completionBlock(granted);
                }
            });
        }];
    }
}

+ (BOOL)isFrontCameraAvailable
{
    return [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceFront];
}

+ (BOOL)isRearCameraAvailable
{
    return [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear];
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

@end
