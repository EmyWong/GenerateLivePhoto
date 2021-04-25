//
//  JPEG.m
//  GenerateLivePhoto
//
//  Created by Emy on 2021/4/24.
//

#import "JPEG.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <ImageIO/ImageIO.h>

#define kfigAppleMakerNote_AssetIdentifier @"17"

@interface JPEG ()

@property (nonatomic, strong) NSString *path;

@end

@implementation JPEG

- (id)initWithPath:(NSString *)path {
    if (self = [super init]) {
        self.path = path;
    }
    return self;
}

- (NSString *)read {
    NSDictionary *dic = [self metadata];
    if (!dic) {
        return nil;
    }
    NSDictionary *dict = [dic objectForKey:(__bridge NSString *)kCGImagePropertyMakerAppleDictionary];
    NSString *str = [dict objectForKey:kfigAppleMakerNote_AssetIdentifier];
    return str;
}

- (void)writeWithDest:(NSString *)dest assetIdentifier:(NSString *)assetIdentifier result:(void(^)(BOOL res))result{
    CGImageDestinationRef ref = CGImageDestinationCreateWithURL((CFURLRef)[NSURL fileURLWithPath:dest], kUTTypeJPEG, 1, nil);
    if (!ref) {
        if (result) {
            result(NO);
        }
        return;
    }
    CGImageSourceRef source = [self imageSource];
    if (!source) {
        if (result) {
            result(NO);
        }
        return;
    }
    NSMutableDictionary *dic = [[self metadata] mutableCopy];
    if (!dic) {
        if (result) {
            result(NO);
        }
        return;
    }
    
    NSMutableDictionary *makerNote = [[NSMutableDictionary alloc] init];
    [makerNote setObject:assetIdentifier forKey:kfigAppleMakerNote_AssetIdentifier];
    [dic setObject:makerNote forKey:(NSString *)kCGImagePropertyMakerAppleDictionary];
    CGImageDestinationAddImageFromSource(ref, source, 0, (CFDictionaryRef)dic);
    CFRelease(source);
    CGImageDestinationFinalize(ref);
    if (result) {
        result(YES);
    }
}

- (NSDictionary *)metadata {
    CGImageSourceRef ref = [self imageSource];
    NSDictionary *dict = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(ref, 0, nil));
    CFRelease(ref);
    return  dict;
}

- (CGImageSourceRef)imageSource {
     return CGImageSourceCreateWithData((CFDataRef)[self data], nil);
}

- (NSData *)data {
    return [NSData dataWithContentsOfURL: [NSURL fileURLWithPath:self.path]];
}
@end
