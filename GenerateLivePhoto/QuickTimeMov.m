//
//  QuickTimeMov.m
//  GenerateLivePhoto
//
//  Created by Emy on 2021/4/24.
//

#import "QuickTimeMov.h"
#import <AVFoundation/AVFoundation.h>

static NSString *const contentIdentifierKey = @"com.apple.quicktime.content.identifier";
static NSString *const stillImageTimeKey = @"com.apple.quicktime.still-image-time";
static NSString *const spaceQuickTimeMetadataKey = @"mdta";

static NSString *const firstCustomKey  = @"first";
static NSString *const secondCustomKey = @"second";

@interface QuickTimeMov ()

@property(nonatomic, copy)NSString *path;
@property(nonatomic, assign)CMTimeRange dummyTimeRange;
@property(nonatomic, strong)AVURLAsset *asset;

@end

@implementation QuickTimeMov
- (id)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        self.path = path;
    }
    return self;
}

- (CMTimeRange)dummyTimeRange {
    return CMTimeRangeMake(CMTimeMake(0, 1000), CMTimeMake(200, 300));
}

- (AVURLAsset *)asset {
    if (!_asset) {
        self.asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:self.path]];
    }
    return _asset;
}

- (NSString *)readAssetIdentifier {
    for (AVMetadataItem *item in [self metaData]) {
        if ((NSString *)item.key == contentIdentifierKey && item.keySpace == spaceQuickTimeMetadataKey) {
            return [NSString stringWithFormat:@"%@",item.value];
        }
    }
    return nil;
}

- (NSNumber *)readStillImageTime {
    AVAssetTrack *track = [self track:AVMediaTypeMetadata];
    if (track) {
        NSDictionary *dict = [self reader:track settings:nil];
        AVAssetReader *reader = [dict objectForKey:firstCustomKey];
        [reader startReading];
        AVAssetReaderOutput *output = [dict objectForKey:secondCustomKey];
        while (YES) {
            CMSampleBufferRef buffer = [output copyNextSampleBuffer];
            if (!buffer) {
                return nil;
            }
            if (CMSampleBufferGetNumSamples(buffer) != 0) {
                AVTimedMetadataGroup *group = [[AVTimedMetadataGroup alloc] initWithSampleBuffer:buffer];
                for (AVMetadataItem *item in group.items) {
                    if ((NSString *)(item.key) == stillImageTimeKey && item.keySpace == spaceQuickTimeMetadataKey) {
                        return item.numberValue;
                    }
                }
            }
        }
    }
    return nil;
}

- (void)writeWithDest:(NSString *)dest assetIdentifier:(NSString *)assetIdentifier result:(void (^)(BOOL))result {
    AVAssetReader *audioReader = nil;
    AVAssetWriterInput *audioWriterInput = nil;
    AVAssetReaderOutput *audioReaderOutput = nil;
    
    @try {
        AVAssetTrack *track = [self track:AVMediaTypeVideo];
        if (!track) {
            NSLog(@"not found video track");
            if (result) {
                result(NO);
            }
            return;
        }
        NSDictionary *dict = [self reader:track settings:@{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA]}];
        AVAssetReader *reader = [dict objectForKey:firstCustomKey];
        AVAssetReaderOutput *output = [dict objectForKey:secondCustomKey];
        // writer for mov
        NSError *writerError = nil;
        AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:dest] fileType:AVFileTypeQuickTimeMovie error:&writerError];
        writer.metadata = @[[self metadataFor:assetIdentifier]];
        // video track
        AVAssetWriterInput *input = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:[self videoSettings:track.naturalSize]];
        input.expectsMediaDataInRealTime = YES;
        input.transform = track.preferredTransform;
        [writer addInput:input];
        
        NSURL *url = [NSURL fileURLWithPath:self.path];
        AVAsset *aAudioAsset = [AVAsset assetWithURL:url];
        
        if (aAudioAsset.tracks.count > 1) {
            NSLog(@"Has Audio");
            // setup audio writer
            audioWriterInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:nil];
            
            audioWriterInput.expectsMediaDataInRealTime = NO;
            if ([writer canAddInput:audioWriterInput]) {
                [writer addInput:audioWriterInput];
            }
            // setup audio reader
            AVAssetTrack *audioTrack = [aAudioAsset tracksWithMediaType:AVMediaTypeAudio].firstObject;
            audioReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack outputSettings:nil];
            @try {
                NSError *audioReaderError = nil;
                audioReader = [AVAssetReader assetReaderWithAsset:aAudioAsset error:&audioReaderError];
                if (audioReaderError) {
                    NSLog(@"Unable to read Asset, error: %@",audioReaderError);
                }
            } @catch (NSException *exception) {
                NSLog(@"Unable to read Asset: %@", exception.description);
            } @finally {
                
            }
            
            if ([audioReader canAddOutput:audioReaderOutput]) {
                [audioReader addOutput:audioReaderOutput];
            } else {
                NSLog(@"cant add audio reader");
            }
        }
        
        // metadata track
        AVAssetWriterInputMetadataAdaptor *adapter = [self metadataAdapter];
        [writer addInput:adapter.assetWriterInput];
        
        // creating video
        [writer startWriting];
        [reader startReading];
        [writer startSessionAtSourceTime:kCMTimeZero];
        
        // write metadata track
        AVMetadataItem *metadataItem = [self metadataForStillImageTime];
        
        [adapter appendTimedMetadataGroup:[[AVTimedMetadataGroup alloc] initWithItems:@[metadataItem] timeRange:self.dummyTimeRange]];
        
        // write video track
        [input requestMediaDataWhenReadyOnQueue:dispatch_queue_create("assetVideoWriterQueue", 0) usingBlock:^{
            while (input.isReadyForMoreMediaData) {
                if (reader.status == AVAssetReaderStatusReading) {
                    CMSampleBufferRef buffer = [output copyNextSampleBuffer];
                    if (buffer) {
                        if (![input appendSampleBuffer:buffer]) {
                            NSLog(@"cannot write: %@", writer.error);
                            [reader cancelReading];
                        }
                        //释放内存，否则出现内存问题
                        CFRelease(buffer);
                    }
                } else {
                    [input markAsFinished];
                    if (reader.status == AVAssetReaderStatusCompleted && aAudioAsset.tracks.count > 1) {
                        [audioReader startReading];
                        [writer startSessionAtSourceTime:kCMTimeZero];
                        dispatch_queue_t media_queue = dispatch_queue_create("assetAudioWriterQueue", 0);
                        [audioWriterInput requestMediaDataWhenReadyOnQueue:media_queue usingBlock:^{
                            while ([audioWriterInput isReadyForMoreMediaData]) {
                                
                                CMSampleBufferRef sampleBuffer2 = [audioReaderOutput copyNextSampleBuffer];
                                if (audioReader.status == AVAssetReaderStatusReading && sampleBuffer2 != nil) {
                                    if (![audioWriterInput appendSampleBuffer:sampleBuffer2]) {
                                        [audioReader cancelReading];
                                    }
                                } else {
                                    [audioWriterInput markAsFinished];
                                    NSLog(@"Audio writer finish");
                                    [writer finishWritingWithCompletionHandler:^{
                                        NSError *e = writer.error;
                                        if (e) {
                                            NSLog(@"cannot write: %@",e);
                                        } else {
                                            NSLog(@"finish writing.");
                                        }
                                    }];
                                }
                                if (sampleBuffer2) {//释放内存，否则出现内存问题
                                    CFRelease(sampleBuffer2);
                                }
                            }
                        }];
                    } else {
                        NSLog(@"Video Reader not completed");
                        [writer finishWritingWithCompletionHandler:^{
                            NSError *e = writer.error;
                            if (e) {
                                NSLog(@"cannot write: %@",e);
                            } else {
                                NSLog(@"finish writing.");
                            }
                        }];
                    }
                }
            }
        }];
        while (writer.status == AVAssetWriterStatusWriting) {
           @autoreleasepool {
               [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
           }
        }
        if (writer.error) {
            if (result) {
                result(NO);
            }
            NSLog(@"cannot write: %@", writer.error);
        } else {
            if (result) {
                result(YES);
            }
            NSLog(@"write finish");
        }
    } @catch (NSException *exception) {
        if (result) {
            result(NO);
        }
        NSLog(@"error: %@", exception.description);
    } @finally {
        
    }
}

- (NSArray<AVMetadataItem *>*)metaData {
    return [self.asset metadataForFormat:AVMetadataFormatQuickTimeMetadata];
}

- (AVAssetTrack *)track:(NSString *)mediaType {
    return [self.asset tracksWithMediaType:mediaType].firstObject;
}

- (NSDictionary *)reader:(AVAssetTrack *)track settings:(NSDictionary *)settings {
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
    NSError *readerError = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:self.asset error:&readerError];
    [reader addOutput:output];
    return @{firstCustomKey:reader,secondCustomKey:output};
}

- (AVAssetWriterInputMetadataAdaptor *)metadataAdapter {
    NSDictionary *spec = @{
                           (__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier:[NSString stringWithFormat:@"%@/%@",spaceQuickTimeMetadataKey,stillImageTimeKey],
                           (__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType:@"com.apple.metadata.datatype.int8"
                           };
    
    CMFormatDescriptionRef desc = nil;
    
    CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, (__bridge CFArrayRef)@[spec], &desc);
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeMetadata outputSettings:nil sourceFormatHint:desc];
    return [AVAssetWriterInputMetadataAdaptor assetWriterInputMetadataAdaptorWithAssetWriterInput:input];
}

- (NSDictionary *)videoSettings:(CGSize)size {
    return @{
             AVVideoCodecKey : AVVideoCodecTypeH264,
             AVVideoWidthKey : @(size.width),
             AVVideoHeightKey : @(size.height)
             };
}

- (AVMetadataItem *)metadataFor:(NSString *)assetIdentifier {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.key = contentIdentifierKey;
    item.keySpace = spaceQuickTimeMetadataKey;
    item.value = assetIdentifier;
    item.dataType = @"com.apple.metadata.datatype.UTF-8";
    return item;
}

- (AVMetadataItem *)metadataForStillImageTime {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.key = stillImageTimeKey;
    item.keySpace = spaceQuickTimeMetadataKey;
    item.value = @(0);
    item.dataType = @"com.apple.metadata.datatype.int8";
    return item;
}
@end
