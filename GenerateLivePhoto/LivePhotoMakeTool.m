//
//  LivePhotoMakeTool.m
//  GenerateLivePhoto
//
//  Created by Emy on 2021/4/24.
//

#import "LivePhotoMakeTool.h"
#import "JPEG.h"
#import "QuickTimeMov.h"
#import <Photos/Photos.h>

@interface LivePhotoMakeTool ()
@property (nonatomic,assign) BOOL isImageWrited;
@property (nonatomic,assign) BOOL isVideoWrited;
@end

@implementation LivePhotoMakeTool

/**
 * Live Photo 制作方法调用
 * imagePath    : Live Photo静态时展示的图片路径
 * videoPath    : 制作Live Photo的视频路径
 * toImagePath  : 处理后的图片存储路径
 * toVideoPath  : 处理后的视频存储路径
 * tmpImagePath : 临时处理的图片存储路径
 * SuccessHandler   : Block返回存储结果
 */
- (void)livePhotoMakeWithImagePath:(NSString * _Nonnull)imagePath VideoPath:(NSString * _Nonnull)videoPath toImagePath:(NSString * __nullable)toImagePath toVideoPath:(NSString * __nullable)toVideoPath tmpImagePath:(NSString * __nullable)tmpImagePath Success:(void(^)(BOOL Successed))SuccessHandler{
    NSString * assetIdentifier = [[NSUUID UUID] UUIDString];
    // 如果没有给临时存储路径，默认为沙盒/tmp文件下
    if (tmpImagePath.length<1) {
        tmpImagePath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tmp/%@.jpg",[[imagePath lastPathComponent] stringByDeletingPathExtension]]];
    }
    // 如果没有给最终存储图片地址，则默认Document文件下
    if (toImagePath.length<1) {
        toImagePath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@.jpg",[[imagePath lastPathComponent] stringByDeletingPathExtension]]];
    }
    // 如果没有给最终存储视频地址，则默认Document文件下
    if (toVideoPath.length<1) {
        toVideoPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@.mov",[[videoPath lastPathComponent] stringByDeletingPathExtension]]];
    }
    
    UIImage *or = [UIImage imageWithContentsOfFile:imagePath];
    if (_isVideoWrited && _isImageWrited) {
        //如果是已经处理好了，那就直接展示。
        //展示LivePhoto
        [PHLivePhoto requestLivePhotoWithResourceFileURLs:@[[NSURL fileURLWithPath:videoPath],[NSURL fileURLWithPath:imagePath]] placeholderImage:nil targetSize:[or size] contentMode:PHImageContentModeAspectFit resultHandler:^(PHLivePhoto * _Nullable livePhoto, NSDictionary * _Nonnull info) {
            if (SuccessHandler) {
                if (livePhoto) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"refreshLiveView" object:livePhoto];
                    SuccessHandler(YES);
                } else {
                    SuccessHandler(NO);
                }
            }
        }];
        [[NSUserDefaults standardUserDefaults] setObject:toVideoPath forKey:@"toVideoPath"];
        [[NSUserDefaults standardUserDefaults] setObject:toImagePath forKey:@"toImagePath"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return;
    }
    
    NSData *imageData = UIImageJPEGRepresentation(or, 1.0);
    BOOL isok = [imageData writeToFile:tmpImagePath atomically:YES];
    if (!isok) {
        NSLog(@"图片写入错误！！");
        SuccessHandler(NO);
        return;
    }
    //1.先把旧文件移除
    [[NSFileManager defaultManager] removeItemAtPath:toImagePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:toVideoPath error:nil];
    
    NSLog(@"制作中....");
    
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t globle = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    __weak typeof (self)bSelf = self;
    //任务一 写入 图片
    dispatch_group_async(group, globle, ^{
        JPEG *jpeg = [[JPEG alloc] initWithPath:tmpImagePath];
        [jpeg writeWithDest:toImagePath assetIdentifier:assetIdentifier result:^(BOOL res) {
            bSelf.isImageWrited = res;
        }];
    });
    //任务二 写入 视频
    dispatch_group_async(group, globle, ^{
        QuickTimeMov *quickMov = [[QuickTimeMov alloc] initWithPath:videoPath];
        [quickMov writeWithDest:toVideoPath assetIdentifier:assetIdentifier result:^(BOOL res) {
            bSelf.isVideoWrited = res;
        }];
    });
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (self.isVideoWrited && self.isImageWrited) {
            //展示LivePhoto
            [PHLivePhoto requestLivePhotoWithResourceFileURLs:@[[NSURL fileURLWithPath:toVideoPath],[NSURL fileURLWithPath:toImagePath]] placeholderImage:nil targetSize:[or size] contentMode:PHImageContentModeAspectFit resultHandler:^(PHLivePhoto * _Nullable livePhoto, NSDictionary * _Nonnull info) {
                if (SuccessHandler) {
                    if (livePhoto) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"refreshLiveView" object:livePhoto];
                        SuccessHandler(YES);
                    } else {
                        SuccessHandler(NO);
                    }
                }
            }];
            [[NSUserDefaults standardUserDefaults] setObject:toVideoPath forKey:@"toVideoPath"];
            [[NSUserDefaults standardUserDefaults] setObject:toImagePath forKey:@"toImagePath"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    });
}

#pragma mark - save
- (void)writeLive:(NSURL *)videoPath image:(NSURL *)imagePath Success:(void(^)(BOOL isSuccess))SuccessHandler {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized) {
            //已经授权,直接保存
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                PHAssetCreationRequest * request = [PHAssetCreationRequest creationRequestForAsset];
                [request addResourceWithType:PHAssetResourceTypePhoto fileURL:imagePath options:nil];
                [request addResourceWithType:PHAssetResourceTypePairedVideo fileURL:videoPath options:nil];
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                if (SuccessHandler) {
                    SuccessHandler(success);
                }
            }];
        }else {
            //未授权，给一个提示框
            UIAlertController * alertCon = [UIAlertController alertControllerWithTitle:@"提示" message:@"App需要访问你的相册才能将数据写入相册，是否现在开启权限？" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction * cancel = [UIAlertAction actionWithTitle:@"NO" style:UIAlertActionStyleDefault handler:nil];
            UIAlertAction * action = [UIAlertAction actionWithTitle:@"YES" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                NSURL * URL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                if ([[UIApplication sharedApplication] canOpenURL:URL]) {
                    [[UIApplication sharedApplication] openURL:URL options:@{} completionHandler:nil];
                }
            }];
            [alertCon addAction:cancel];
            [alertCon addAction:action];
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertCon animated:YES completion:nil];
        }
    }];
}


@end
