//
//  TestViewController.m
//  GPUImageDemo
//
//  Created by canoe on 2018/1/25.
//  Copyright © 2018年 canoe. All rights reserved.
//

#import "TestViewController.h"
#import "XCaptureController.h"
#import "XCategoryHeader.h"
#import "XMacros.h"

//滤镜
#import "FWNashvilleFilter.h"
#import "FWLordKelvinFilter.h"
#import "FWAmaroFilter.h"
#import "FWRiseFilter.h"
#import "FWHudsonFilter.h"
#import "FW1977Filter.h"
#import "FWValenciaFilter.h"
#import "FWXproIIFilter.h"
#import "FWWaldenFilter.h"
#import "FWLomofiFilter.h"
#import "FWInkwellFilter.h"
#import "FWSierraFilter.h"
#import "FWEarlybirdFilter.h"
#import "FWSutroFilter.h"
#import "FWToasterFilter.h"
#import "FWBrannanFilter.h"
#import "FWHefeFilter.h"
#import "GPUImageBeautifyFilter.h"
#import "LFGPUImageBeautyFilter.h"
#import "FSKGPUImageBeautyFilter.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import "DealVideoController.h"

@interface TestViewController ()<XFaceDetectionDelegate>

@property(nonatomic, strong) XCaptureController *capture;

@property(nonatomic, assign) NSInteger index;
@property(nonatomic, strong) NSArray *titleArray;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *faceButton;
@property(nonatomic, strong) UIImageView *currentFace;

@end

@implementation TestViewController

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.capture start];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.capture stop];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.capture = [[XCaptureController alloc] initWithQuality:AVCaptureSessionPresetHigh position:XCapturePositionFront enableRecording:YES];
    [self.capture attachToViewController:self withFrame:self.view.bounds];
    //点击聚焦
    self.capture.tapToFocus = YES;
    //设置人脸识别代理
    self.capture.faceDetectionDelegate = self;
    //设置检测区域为中心正方形
    self.capture.detectionRect = CGRectMake(0, (KScreenHeight - KScreenWidth)/2, KScreenWidth, KScreenWidth);
    
    [self createUI];
    
    self.index = 0;
    self.titleArray = @[@"原图", @"经典LOMO", @"流年", @"HDR", @"碧波", @"上野", @"优格", @"彩虹瀑", @"云端",@"美颜1",@"美颜2",@"美颜3"];
}

-(void)createUI
{
    UIButton *flash = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.view addSubview:flash];
        flash.titleLabel.font = [UIFont systemFontOfSize:14];
    [flash setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [flash setTitle:@"闪光灯:on" forState:UIControlStateSelected];
    [flash setTitle:@"闪光灯:off" forState:UIControlStateNormal];
    __weak __typeof(flash)weakFlash = flash;
    __weak __typeof(self)weakSelf = self;
    [flash addActionHandler:^(NSInteger tag) {
        weakFlash.selected = !weakFlash.isSelected;
        if (weakFlash.isSelected) {
            [weakSelf.capture updateFlashMode:XCaptureFlashOn];
        }else
        {
            [weakSelf.capture updateFlashMode:XCaptureFlashOff];
        }
    }];
    flash.frame = CGRectMake(0, 20, 80, 40);
    
    UIButton *changePosition = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.view addSubview:changePosition];
    changePosition.titleLabel.font = [UIFont systemFontOfSize:14];
    [changePosition setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [changePosition setTitle:@"切换相机" forState:UIControlStateNormal];
    [changePosition addActionHandler:^(NSInteger tag) {
        [weakSelf.capture changePosition];
    }];
    changePosition.frame = CGRectMake(80, 20, 60, 40);
    
    UIImageView *imageView = [self.view addImageViewWithImage:nil];
    imageView.frame = CGRectMake(0, 100, KScreenWidth/4, KScreenHeight/4);
    
    UIButton *capture = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.view addSubview:capture];
    capture.backgroundColor = [UIColor whiteColor];
    capture.clipsToBounds = YES;
    capture.layer.cornerRadius = 30;
    capture.frame = CGRectMake((KScreenWidth - 40)/2, KScreenHeight - 80, 60, 60);
    
    
    
    NSURL *outputURL = [[[self applicationDocumentsDirectory]
                         URLByAppendingPathComponent:@"output"] URLByAppendingPathExtension:@"mov"];

    __weak __typeof(capture)weakCapture = capture;
    [capture addActionHandler:^(NSInteger tag) {
        
        //拍摄照片
        [weakSelf.capture capture:^(XCaptureController *camera, UIImage *image, NSError *error) {
            if (weakSelf.didFinishCapture) {
                weakSelf.didFinishCapture(image);
            }
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        }];
        
        //录制5秒视频
//        weakCapture.backgroundColor = [UIColor redColor];
//        weakCapture.enabled = NO;
//        [weakSelf.capture startRecordingWithOutputUrl:outputURL didRecord:^(XCaptureController *camera, NSURL *outputFileUrl, NSError *error) {
//            DealVideoController *vc = [[DealVideoController alloc] initWithVideoUrl:outputURL];
//            [weakSelf presentViewController:vc animated:NO completion:nil];
//        }];
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//            weakCapture.backgroundColor = [UIColor whiteColor];
//            [weakSelf.capture stopRecording];
//        weakCapture.enabled = YES;
//        });
    }];
    

    
    UIButton *beauty = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.view addSubview:beauty];
    beauty.titleLabel.font = [UIFont systemFontOfSize:14];
    [beauty setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [beauty setTitle:@"开关美颜" forState:UIControlStateNormal];
    [beauty addActionHandler:^(NSInteger tag) {
        weakSelf.capture.openBeautyFilter = !weakSelf.capture.openBeautyFilter;
    }];
    beauty.frame = CGRectMake(160, 20, 60, 40);
    
    UIButton *change = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.view addSubview:change];
    change.titleLabel.font = [UIFont systemFontOfSize:14];
    [change setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [change setTitle:@"切换滤镜" forState:UIControlStateNormal];
    [change addActionHandler:^(NSInteger tag) {
        if (weakSelf.index == weakSelf.titleArray.count - 1) {
            weakSelf.index = 0;
        }else
        {
            weakSelf.index ++;
        }
    }];
    change.frame = CGRectMake(240, 20, 60, 40);
    
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    self.titleLabel.textColor = [UIColor whiteColor];
    [self.view addSubview:self.titleLabel];
    self.titleLabel.frame = CGRectMake(0, 100, KScreenWidth, 100);
    self.titleLabel.center = self.view.center;
    self.titleLabel.hidden = YES;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    
    UIButton *face = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.view addSubview:face];
    face.titleLabel.font = [UIFont systemFontOfSize:14];
    [face setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [face setTitle:@"人脸识别:关" forState:UIControlStateNormal];
    [face setTitle:@"人脸识别:开" forState:UIControlStateSelected];
    [face addActionHandler:^(NSInteger tag) {
        weakSelf.faceButton.selected = !weakSelf.faceButton.isSelected;
        weakSelf.capture.openFaceDetection = !weakSelf.capture.openFaceDetection;
        if (weakSelf.faceButton.isSelected == NO) {
            weakSelf.faceButton.backgroundColor = [UIColor redColor];
        }
    }];
    face.backgroundColor = [UIColor redColor];
    face.frame = CGRectMake(20, KScreenHeight - 100, 90, 40);
    self.faceButton = face;
    
    self.currentFace = [[UIImageView alloc] init];
    self.currentFace.frame = CGRectMake(KScreenWidth - KScreenWidth/4, KScreenHeight - KScreenHeight/4, KScreenWidth/4, KScreenHeight/4);
    [self.view addSubview:self.currentFace];
    self.currentFace.contentMode = UIViewContentModeScaleAspectFit;
}


-(void)setIndex:(NSInteger)index
{
    _index = index;
    self.titleLabel.text = self.titleArray[index];
    self.titleLabel.hidden = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.titleLabel.hidden = YES;
    });
    switch (index) {
        case 0:
            self.capture.filters = nil;
            break;
            
        case 1:
            self.capture.filters= [[GPUImageSketchFilter alloc] init];
            break;
            
        case 2:
            self.capture.filters = [[GPUImageSoftEleganceFilter alloc] init];
            break;
            
        case 3:
            self.capture.filters = [[GPUImageMissEtikateFilter alloc] init];
            break;
            
        case 4:
            self.capture.filters = [[FWNashvilleFilter alloc] init];
            break;
            
        case 5:
            self.capture.filters = [[FWLordKelvinFilter alloc] init];
            break;
            
        case 6:
            self.capture.filters = [[FWAmaroFilter alloc] init];
            break;
            
        case 7:
            self.capture.filters = [[FWRiseFilter alloc] init];
            break;
            
        case 8:
            self.capture.filters= [[FWHudsonFilter alloc] init];
            break;
        case 9:
            self.capture.filters= [[GPUImageBeautifyFilter alloc] init];
            break;
        case 10:
            self.capture.filters= [[LFGPUImageBeautyFilter alloc] init];
            break;
        case 11:
            self.capture.filters= [[FSKGPUImageBeautyFilter alloc] init];
            break;
    }
}



#pragma mark - 人脸识别回调

-(void)faceDetectionSuccessWithImage:(UIImage *)image
{
    if (image) {
        self.currentFace.image = image;
    }
}

-(void)faceDetectionSuccess:(BOOL)hasFace faceCount:(NSUInteger)faceCount
{
    if (hasFace) {
        self.faceButton.backgroundColor = [UIColor greenColor];
        NSLog(@"！！！！！！发现一张大脸");
    }else
    {
        self.faceButton.backgroundColor = [UIColor redColor];
        NSLog(@"没有人脸 ---------> ");
    }
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

- (NSURL *)applicationDocumentsDirectory{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

-(void)saveVideoToAblumWithUrl:(NSURL *)url
{
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path))
    {
        [library writeVideoAtPathToSavedPhotosAlbum:url completionBlock:^(NSURL *assetURL, NSError *error)
         {
             dispatch_async(dispatch_get_main_queue(), ^{
                 
                 if (error) {
                     UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"视频保存失败" message:nil
                                                                    delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                     [alert show];
                 } else {
                     UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"视频保存成功" message:nil
                                                                    delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                     [alert show];
                 }
             });
         }];
    }
}
@end
