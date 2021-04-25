//
//  LivePhotoMakeTool.h
//  GenerateLivePhoto
//
//  Created by Emy on 2021/4/24.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LivePhotoMakeTool : NSObject

/**
 * Live Photo 制作方法调用
 * imagePath    : Live Photo静态时展示的图片路径
 * videoPath    : 制作Live Photo的视频路径
 * toImagePath  : 处理后的图片存储路径
 * toVideoPath  : 处理后的视频存储路径
 * tmpImagePath : 临时处理的图片存储路径
 * SuccessHandler   : Block返回存储结果
 */
- (void)livePhotoMakeWithImagePath:(NSString * _Nonnull)imagePath VideoPath:(NSString * _Nonnull)videoPath toImagePath:(NSString * __nullable)toImagePath toVideoPath:(NSString * __nullable)toVideoPath tmpImagePath:(NSString * __nullable)tmpImagePath Success:(void(^)(BOOL Successed))SuccessHandler;

/**
 * Live Photo 保存方法调用
 * imagePath    : Live Photo静态时展示的图片路径
 * videoPath    : 制作Live Photo的视频路径
 * SuccessHandler   : Block返回存储结果
 */
- (void)writeLive:(NSURL *)videoPath image:(NSURL *)imagePath Success:(void(^)(BOOL isSuccess))SuccessHandler;
@end

NS_ASSUME_NONNULL_END
