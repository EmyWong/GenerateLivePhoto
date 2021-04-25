//
//  ViewController.m
//  GenerateLivePhoto
//
//  Created by Emy on 2021/4/24.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import "LivePhotoMakeTool.h"

#define kScreenWidth  [UIScreen mainScreen].bounds.size.width
#define kScreenHeight [UIScreen mainScreen].bounds.size.height

@interface ViewController ()<UINavigationControllerDelegate, UIImagePickerControllerDelegate>
{
    UIButton *selectBtn; //选择视频的按钮
    UIButton *stateBtn; //播放状态的按钮
    CGFloat ratio;
}

@property (nonatomic, copy) NSURL *videoURL; //视频的URL
@property (nonatomic, strong) AVPlayer *player; //播放视频
@property (nonatomic, strong) AVPlayerLayer *playerLayer; //展示视频的layer
@property (nonatomic, strong) AVPlayerItem *item; //视频信息
@property (nonatomic, assign) Float64 duration; //视频长度
@property (nonatomic, strong) UISlider *slider; //进度条
@property (nonatomic, assign) Float64 seekTime; //选择时间
@property (nonatomic, strong) UIImageView *imageView; //展示选择封面的视图
@property (nonatomic, strong) PHLivePhotoView *livePhotoView; //展示livePhoto的视图
@property (nonatomic, copy) NSURL *imageURL; //livePhoto封面页地址
@property (nonatomic, assign) BOOL canPlay; //视频可播放状态

@end

@implementation ViewController

/**
 Live Photo的本质是一张jpg图片+一段MOV视频另外再加入一些信息一起写入到相册内即可生成livePhoto。
 涉及到的技术
 相册数据的读取和写入
 share Extension的使用
 视频中提取某一帧图片
 不同进程间的通讯
 PHLivPhotoView展示livePhoto图片
 */

- (void)viewDidLoad {
    [super viewDidLoad];

    ratio = kScreenWidth / 375.0;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshLiveView:) name:@"refreshLiveView" object:nil];
    [self initButton];
}

//初始化打开相册选择视频的Button
- (void)initButton {
    selectBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    selectBtn.frame = CGRectMake((kScreenWidth - 140 * ratio) / 2.0, 50 * ratio, 140 * ratio, 40 * ratio);
    [selectBtn setTitle:@"从相册中选取" forState:UIControlStateNormal];
    [selectBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [selectBtn addTarget:self action:@selector(selectVideoFromAblum:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:selectBtn];
    selectBtn.titleLabel.font = [UIFont systemFontOfSize:17 * ratio];
    selectBtn.layer.borderColor = [UIColor blackColor].CGColor;
    selectBtn.layer.borderWidth = 0.5;
    selectBtn.layer.cornerRadius = 20 * ratio;
}

//弹出相册选择视频
- (void)selectVideoFromAblum:(UIButton *)sender {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.allowsEditing = NO;
    picker.videoMaximumDuration = 1.0;
    picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
    picker.mediaTypes = [NSArray arrayWithObjects:@"public.movie", nil];
    picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate

//选择视频后获取视频的URL 并进行展示
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:@"public.movie"]) {
        NSURL *url = [info objectForKey:UIImagePickerControllerMediaURL];
        self.videoURL = url;
        [self initAVPlayerView];
    }
    if (self.livePhotoView.livePhoto) {
        self.livePhotoView.livePhoto = nil;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

//初始化展示视频
- (void)initAVPlayerView {
    if (self.playerLayer.superlayer) {
        [self.playerLayer removeFromSuperlayer];
    }
    AVAsset *asset = [AVAsset assetWithURL:self.videoURL];
    self.item = [AVPlayerItem playerItemWithAsset:asset];
    [self.item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:@"item.status"];
    [self.item addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:@"item.loaded"];
    self.player = [AVPlayer playerWithPlayerItem:self.item];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.frame = CGRectMake(0, CGRectGetMaxY(selectBtn.frame) + 10 * ratio, kScreenWidth, 300 * ratio);
    self.playerLayer.backgroundColor = [UIColor blackColor].CGColor;
    [self.view.layer addSublayer:self.playerLayer];

    [self initSliderAndButton];

    //增加观察者 当播放完毕时执行handlePlayEnd方法
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePlayEnd) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];

    __weak typeof(self) weakSelf = self;
    //默认设置首图为封面
    UIImage *image = [self getVideoImageWithTime:0 videoPath:self.videoURL];
    self.imageView.image = image;

    //监听播放进度
    [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        CGFloat dur = CMTimeGetSeconds(time);
        strongSelf.slider.value = dur;
        UIImage *image = [strongSelf getVideoImageWithTime:dur videoPath:strongSelf.videoURL];
        strongSelf.imageView.image = image;
    }];
}

//播放结束执行
- (void)handlePlayEnd {
    stateBtn.selected = NO;
    [self.player seekToTime:CMTimeMake(0, 1)];
}

//初始化展示视频的进度条和按钮
- (void)initSliderAndButton {
    if (!stateBtn) {
        stateBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        stateBtn.frame = CGRectMake(0, CGRectGetMaxY(self.playerLayer.frame) - 40 * ratio, 40 * ratio, 40 * ratio);
        [stateBtn setImage:[UIImage imageNamed:@"start"] forState:UIControlStateNormal];
        [stateBtn setImage:[UIImage imageNamed:@"pause"] forState:UIControlStateSelected];
        [self.view addSubview:stateBtn];
        [stateBtn addTarget:self action:@selector(statePlay:) forControlEvents:UIControlEventTouchUpInside];
    }
    if (!self.slider) {
        self.slider = [[UISlider alloc] initWithFrame:CGRectMake(CGRectGetMaxX(stateBtn.frame), CGRectGetMaxY(self.playerLayer.frame) - 40 * ratio, kScreenWidth, 40 * ratio)];
        [self.view addSubview:self.slider];
        [self.slider addTarget:self action:@selector(selectTime:) forControlEvents:UIControlEventValueChanged];
        [self.slider setThumbImage:[UIImage imageNamed:@"cat"] forState:UIControlStateNormal];
        self.slider.tintColor = [UIColor whiteColor];
        [self initImageView];
        [self initPHLivePhotoView];
        [self initLookButton];
    }
    [self.view bringSubviewToFront:stateBtn];
    [self.view bringSubviewToFront:self.slider];
}

//状态按钮的状态切换和事件切换
- (void)statePlay:(UIButton *)sender {
    if (sender.selected) {
        [self.player pause];
    } else {
        if (self.canPlay) {
            [self.player play];
        }
    }
    sender.selected = !sender.selected;
}

//初始化展示封面的view
- (void)initImageView {
    if (!self.imageView) {
        self.imageView = [[UIImageView alloc] initWithFrame:CGRectMake(5 * ratio, CGRectGetMaxY(self.slider.frame) + 10 * ratio, (kScreenWidth - 15 * ratio) / 2.0, 300 * ratio)];
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.imageView.backgroundColor = [UIColor blackColor];
        [self.view addSubview:self.imageView];
    }
}

//初始化展示livephoto的view
- (void)initPHLivePhotoView {
    if (!self.livePhotoView) {
        self.livePhotoView = [[PHLivePhotoView alloc] initWithFrame:CGRectMake(CGRectGetMaxX(self.imageView.frame) + 5 * ratio, CGRectGetMinY(self.imageView.frame), CGRectGetWidth(self.imageView.frame), CGRectGetHeight(self.imageView.frame))];
        self.livePhotoView.contentMode = UIViewContentModeScaleAspectFit;
        self.livePhotoView.backgroundColor = [UIColor blackColor];
        [self.view addSubview:self.livePhotoView];
    }
}

//初始化制作按钮和保存按钮
- (void)initLookButton {
    UIButton *generateBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    generateBtn.frame = CGRectMake((kScreenWidth - 290 * ratio) / 2.0, CGRectGetMaxY(self.livePhotoView.frame) + 10 * ratio, 140 * ratio, 40 * ratio);
    [generateBtn setTitle:@"制作LivePhoto" forState:UIControlStateNormal];
    [generateBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [generateBtn addTarget:self action:@selector(createPhoto:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:generateBtn];
    generateBtn.layer.borderColor = [UIColor blackColor].CGColor;
    generateBtn.layer.borderWidth = 0.5;
    generateBtn.layer.cornerRadius = 20 * ratio;
    generateBtn.titleLabel.font = [UIFont systemFontOfSize:17 * ratio];

    UIButton *saveButton = [UIButton buttonWithType:UIButtonTypeCustom];
    saveButton.frame = CGRectMake(CGRectGetMaxX(generateBtn.frame) + 10 * ratio, CGRectGetMaxY(self.livePhotoView.frame) + 10 * ratio, 140 * ratio, 40 * ratio);
    [saveButton setTitle:@"保存LivePhoto" forState:UIControlStateNormal];
    [saveButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [saveButton addTarget:self action:@selector(savePhoto:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveButton];
    saveButton.layer.borderColor = [UIColor blackColor].CGColor;
    saveButton.layer.borderWidth = 0.5;
    saveButton.layer.cornerRadius = 20 * ratio;
    saveButton.titleLabel.font = [UIFont systemFontOfSize:17 * ratio];
}

//AVpalyer的观察者监听开始播放和缓存状态
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"status"] && context == @"item.status") {// 可播放状态
        if (((NSNumber *)[change objectForKey:NSKeyValueChangeNewKey]).integerValue == AVPlayerItemStatusReadyToPlay) {
            // 视频总时长
            self.duration = CMTimeGetSeconds(self.item.duration);
            self.slider.maximumValue = self.duration;
            //可播放
            self.canPlay = YES;
        } else if (((NSNumber *)[change objectForKey:NSKeyValueChangeNewKey]).integerValue == AVPlayerItemStatusFailed) {
            [self showToastMsg:@"播放失败" Duration:0];
            self.canPlay = NO;
        } else {
            [self showToastMsg:@"播放出现问题" Duration:0];
            self.canPlay = NO;
        }
    } else if ([keyPath isEqualToString:@"loadedTimeRanges"] && context == @"item.loaded") {
        // 缓冲进度 这里可以用单独的slide表示缓冲的进度
//        CMTimeRange rangeValue = [[change objectForKey:NSKeyValueChangeNewKey][0] CMTimeRangeValue];
    }
}

//进度条的事件 可以通过进度条滑动选择自己喜欢的封面
- (void)selectTime:(UISlider *)slider {
    CGFloat time = slider.value;
    [self.player seekToTime:CMTimeMake(time, 1)];
    UIImage *image = [self getVideoImageWithTime:time videoPath:self.videoURL];
    self.imageView.image = image;
}

/**
 获取视频的某一帧

 @prama currentTime 某一时刻单位 s
 @prama path 视频路径
 @prama return 返回image
 */
- (UIImage *)getVideoImageWithTime:(Float64)currentTime videoPath:(NSURL *)path {
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:self.videoURL options:nil];
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.requestedTimeToleranceAfter = kCMTimeZero;
    gen.requestedTimeToleranceBefore = kCMTimeZero;//精确提取到某一帧，需要这样处理

    CMTime time = CMTimeMakeWithSeconds(currentTime, 600);
    NSError *error = nil;
    CMTime actualTime;
    CGImageRef image = [gen copyCGImageAtTime:time actualTime:&actualTime error:&error];
    UIImage *img = [[UIImage alloc] initWithCGImage:image];
    CMTimeShow(actualTime);
    CGImageRelease(image);
    return img;
}

//生成livePhoto
- (void)createPhoto:(UIButton *)sender {
    //存储选择的图片到临时文件夹里作为封面图片的初始地址
    NSData *data = UIImagePNGRepresentation(self.imageView.image);
    NSString *imgPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tmp/%@.png", @"livephototemp"]];
    BOOL isok = [data writeToFile:imgPath atomically:YES];
    if (!isok) {
        NSLog(@"临时图片存储错误");
    } else {
        self.imageURL = [NSURL URLWithString:imgPath];
    }
    if (self.imageURL) {
        [[LivePhotoMakeTool new] livePhotoMakeWithImagePath:[NSString stringWithFormat:@"%@", self.imageURL] VideoPath:[NSString stringWithFormat:@"%@", [self.videoURL path]] toImagePath:nil toVideoPath:nil tmpImagePath:nil Success:^(BOOL Successed) {
        }];
    }
}

//保存livePhoto
- (void)savePhoto:(UIButton *)sender {
    if (self.livePhotoView.livePhoto) {
        LivePhotoMakeTool *tool = [[LivePhotoMakeTool alloc] init];
        NSString *toVideoPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"toVideoPath"];
        NSString *toImagePath = [[NSUserDefaults standardUserDefaults] objectForKey:@"toImagePath"];
        //存储live photo
        if (toVideoPath.length != 0 & toImagePath.length != 0) {
            [tool writeLive:[NSURL fileURLWithPath:toVideoPath] image:[NSURL fileURLWithPath:toImagePath] Success:^(BOOL isSuccess) {
                if (isSuccess) {
                    [self showToastMsg:@"保存成功" Duration:0];
                }
            }];
        } else {
            [self showToastMsg:@"出现错误" Duration:0];
        }
    } else {
        [self showToastMsg:@"请先制作livePhoto" Duration:0];
    }
}

//显示状态
- (void)showToastMsg:(NSString *)message Duration:(float)duration {
    if (duration == 0) {
        duration = 3.0;
    }
    if (message == nil || [message isEqualToString:@""]) {
        message = @"";
    }

    //判断当前线程是主线程还是其他线程 刷新UI需要在主线程中完成
    if (strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), dispatch_queue_get_label(dispatch_get_main_queue())) == 0) {
        [self initToastViewMsg:message Duration:duration];
    } else {
        __weak typeof(self) weakSelf = self;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf initToastViewMsg:message Duration:duration];
        });
    }
}

//将相同代码分离出来封装成一个方法
- (void)initToastViewMsg:(NSString *)message Duration:(float)duration  {
    UIView *showView = [[UIView alloc] init];
    showView.backgroundColor = [UIColor blackColor];
    showView.frame = CGRectMake(1, 1, 1, 1);
    showView.alpha = 0.9f;
    showView.layer.cornerRadius = 6.0f;
    showView.layer.masksToBounds = YES;
    [self.view addSubview:showView];

    UILabel *label = [[UILabel alloc] init];

    CGSize LabelSize = [message boundingRectWithSize:CGSizeMake(kScreenWidth - 50, 9000) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{ NSFontAttributeName: [UIFont boldSystemFontOfSize:17.0] } context:nil].size;
    showView.frame = CGRectMake((kScreenWidth - LabelSize.width - 46.0) / 2.0, (kScreenHeight - LabelSize.height - 46.0) / 2., LabelSize.width + 46.0, LabelSize.height + 46.0);
    label.frame = CGRectMake(23., 23.0, LabelSize.width, LabelSize.height);
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont boldSystemFontOfSize:16.0];
    label.numberOfLines = 0;
    [showView addSubview:label];

    [UIView animateWithDuration:duration animations:^{
        showView.alpha = 0;
    }                completion:^(BOOL finished) {
        [showView removeFromSuperview];
    }];
}

//刷新livePhotoView
- (void)refreshLiveView:(NSNotification *)sender {
    PHLivePhoto *livePhoto = (PHLivePhoto *)sender.object;
    self.livePhotoView.livePhoto = livePhoto;
}

//不要忘记移除所有观察者，防止出现野指针
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.item removeObserver:self forKeyPath:@"status"];
    [self.item removeObserver:self forKeyPath:@"loadedTimeRanges"];
}

@end
