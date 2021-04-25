//
//  JPEG.h
//  GenerateLivePhoto
//
//  Created by Emy on 2021/4/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface JPEG : NSObject

- (id)initWithPath:(NSString *)path;

- (void)writeWithDest:(NSString *)dest assetIdentifier:(NSString *)assetIdentifier result:(void(^)(BOOL res))result;

@end

NS_ASSUME_NONNULL_END
