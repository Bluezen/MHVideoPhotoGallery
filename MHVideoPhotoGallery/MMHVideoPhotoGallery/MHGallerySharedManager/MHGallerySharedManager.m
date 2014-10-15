//
//  MHGallerySharedManager.m
//  MHVideoPhotoGallery
//
//  Created by Mario Hahn on 01.04.14.
//  Copyright (c) 2014 Mario Hahn. All rights reserved.
//

#import "MHGallerySharedManager.h"
#import "MHGallerySharedManagerPrivate.h"

#import <XCDYouTubeKit/XCDYouTubeKit.h>

@interface MHGallerySharedManager ()
@property (strong, nonatomic) dispatch_queue_t ioQueue;
@end

@implementation MHGallerySharedManager

+ (MHGallerySharedManager *)sharedManager{
    static MHGallerySharedManager *sharedManagerInstance = nil;
    static dispatch_once_t onceQueue;
    dispatch_once(&onceQueue, ^{
        sharedManagerInstance = self.new;
    });
    return sharedManagerInstance;
}

-(void)getImageFromAssetLibrary:(NSString*)urlString
                      assetType:(MHAssetImageType)type
                   successBlock:(void (^)(UIImage *image,NSError *error))succeedBlock{
    
    dispatch_async(self.ioQueue, ^(void){
        @autoreleasepool {
            ALAssetsLibrary *assetslibrary = ALAssetsLibrary.new;
            [assetslibrary assetForURL:[NSURL URLWithString:urlString]
                           resultBlock:^(ALAsset *asset){
                               
                               if (type == MHAssetImageTypeThumb) {
                                   dispatch_sync(dispatch_get_main_queue(), ^(void){
                                       UIImage *image = [UIImage.alloc initWithCGImage:asset.thumbnail];
                                       succeedBlock(image,nil);
                                   });
                               }else{
                                   ALAssetRepresentation *rep = asset.defaultRepresentation;
                                   CGImageRef iref = rep.fullScreenImage;
                                   if (iref) {
                                       dispatch_sync(dispatch_get_main_queue(), ^(void){
                                           UIImage *image = [UIImage.alloc initWithCGImage:iref];
                                           succeedBlock(image,nil);
                                       });
                                   }
                               }
                           }
                          failureBlock:^(NSError *error) {
                              dispatch_sync(dispatch_get_main_queue(), ^(void){
                                  succeedBlock(nil,error);
                              });
                          }];
        }
    });
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        // Create IO serial queue
        _ioQueue = dispatch_queue_create("com.marioh.MHGallerySharedManager", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}


-(BOOL)isUIViewControllerBasedStatusBarAppearance{
    NSNumber *isUIVCBasedStatusBarAppearance = [NSBundle.mainBundle objectForInfoDictionaryKey:@"UIViewControllerBasedStatusBarAppearance"];
    if (isUIVCBasedStatusBarAppearance) {
        return  isUIVCBasedStatusBarAppearance.boolValue;
    }
    return YES;
}

-(void)createThumbURL:(NSString*)urlString
         successBlock:(void (^)(UIImage *image,NSUInteger videoDuration,NSError *error,NSURL *imageURL))succeedBlock{
    
    [[SDImageCache sharedImageCache]
     queryDiskCacheForKey:urlString
     done:^(UIImage *image, SDImageCacheType cacheType)
    {
        NSMutableDictionary *dict = [NSMutableDictionary.alloc initWithDictionary:[NSUserDefaults.standardUserDefaults objectForKey:MHGalleryDurationData]];
        if (!dict) {
            dict = NSMutableDictionary.new;
        }
        if (image) {
            succeedBlock(image,[dict[urlString] integerValue],nil, [NSURL URLWithString:urlString]);
        }else{
            dispatch_async(self.ioQueue, ^(void){
            @autoreleasepool {
                NSURL *url = [NSURL URLWithString:urlString];
                AVURLAsset *asset=[AVURLAsset.alloc  initWithURL:url options:nil];
                
                AVAssetImageGenerator *generator = [AVAssetImageGenerator.alloc initWithAsset:asset];
                CMTime thumbTime = CMTimeMakeWithSeconds(0,40);
                CMTime videoDurationTime = asset.duration;
                NSUInteger videoDurationTimeInSeconds = CMTimeGetSeconds(videoDurationTime);
                
                NSMutableDictionary *dictToSave = [self durationDict];
                if (videoDurationTimeInSeconds !=0) {
                    dictToSave[urlString] = @(videoDurationTimeInSeconds);
                    [self setObjectToUserDefaults:dictToSave];
                }
                if(self.webPointForThumb == MHWebPointForThumbStart){
                    thumbTime = CMTimeMakeWithSeconds(0,40);
                }else if(self.webPointForThumb == MHWebPointForThumbMiddle){
                    thumbTime = CMTimeMakeWithSeconds(videoDurationTimeInSeconds/2,40);
                }else if(self.webPointForThumb == MHWebPointForThumbEnd){
                    thumbTime = CMTimeMakeWithSeconds(videoDurationTimeInSeconds,40);
                }
                
                AVAssetImageGeneratorCompletionHandler handler = ^(CMTime requestedTime, CGImageRef im, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error){
                    
                    if (result != AVAssetImageGeneratorSucceeded || im == nil) {
                        dispatch_async(dispatch_get_main_queue(), ^(void){
                            succeedBlock(nil,0,error, nil);
                        });
                    }else{
                        UIImage *image = [UIImage imageWithCGImage:im];
                        if (image != nil) {
                            [[SDImageCache sharedImageCache] storeImage:image
                                                                 forKey:urlString];
                            dispatch_async(dispatch_get_main_queue(), ^(void){
                                succeedBlock(image,videoDurationTimeInSeconds,nil,url);
                            });
                        }
                    }
                };
                if (self.webThumbQuality == MHWebThumbQualityHD720) {
                    generator.maximumSize = CGSizeMake(720, 720);
                }else if (self.webThumbQuality == MHWebThumbQualityMedium) {
                    generator.maximumSize = CGSizeMake(420 ,420);
                }else if(self.webThumbQuality == MHWebThumbQualitySmall) {
                    generator.maximumSize = CGSizeMake(220 ,220);
                }
                [generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:thumbTime]]
                                                completionHandler:handler];
            }
            });
        }

        
    }];
    
}

-(NSString*)languageIdentifier{
	static NSString *applicationLanguageIdentifier;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		applicationLanguageIdentifier = @"en";
		NSArray *preferredLocalizations = NSBundle.mainBundle.preferredLocalizations;
		if (preferredLocalizations.count > 0)
			applicationLanguageIdentifier = [NSLocale canonicalLanguageIdentifierFromString:preferredLocalizations[0]] ?: applicationLanguageIdentifier;
	});
	return applicationLanguageIdentifier;
}

-(void)getYoutubeURLforMediaPlayer:(NSString*)URL
                      successBlock:(void (^)(NSURL *URL,NSError *error))succeedBlock{
    
    NSString *videoID = [[URL componentsSeparatedByString:@"?v="] lastObject];
    [self fetchYoutubeURLWithIdentifier:videoID successBlock:succeedBlock];
}

-(void)fetchYoutubeURLWithIdentifier:(NSString *)videoIdentifier successBlock:(void (^)(NSURL *URL,NSError *error))succeedBlock {
    
    [[XCDYouTubeClient defaultClient]
     getVideoWithIdentifier:videoIdentifier
     completionHandler:^(XCDYouTubeVideo *video, NSError *error)
    {
        if (video) {
            NSURL *resultUrl = nil;
            NSDictionary *streamUrls = video.streamURLs;
            
            if (self.youtubeVideoQuality == MHYoutubeVideoQualityHD720) {
                resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualityHD720)];
            } else if (self.youtubeVideoQuality == MHYoutubeVideoQualityMedium) {
                resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualityMedium360)];
            } else if(self.youtubeVideoQuality == MHYoutubeVideoQualitySmall){
                resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualitySmall240)];
            }
            
            if (resultUrl == nil) {
                resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualityMedium360)];
                if(resultUrl == nil){
                    resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualitySmall240)];
                }
            }
            
            
            succeedBlock(resultUrl, nil);
        } else {
            succeedBlock(nil,nil);
        }
    }];
}


-(void)getURLForMediaPlayer:(NSString*)URLString
               successBlock:(void (^)(NSURL *URL,NSError *error))succeedBlock{
    
    if ([URLString rangeOfString:@"vimeo.com"].location != NSNotFound) {
        [self getVimeoURLforMediaPlayer:URLString successBlock:^(NSURL *URL, NSError *error) {
            succeedBlock(URL,error);
        }];
    }else if([URLString rangeOfString:@"youtube.com"].location != NSNotFound) {
        [self getYoutubeURLforMediaPlayer:URLString successBlock:^(NSURL *URL, NSError *error) {
            succeedBlock(URL,error);
        }];
    }else{
        succeedBlock([NSURL URLWithString:URLString],nil);
    }
    
    
}


-(void)getVimeoURLforMediaPlayer:(NSString*)URL
                    successBlock:(void (^)(NSURL *URL,NSError *error))succeedBlock{
    
    NSString *videoID = [[URL componentsSeparatedByString:@"/"] lastObject];
    NSURL *vimdeoURL= [NSURL URLWithString:[NSString stringWithFormat:MHVimeoVideoBaseURL, videoID]];
    
    NSMutableURLRequest *httpRequest = [NSMutableURLRequest requestWithURL:vimdeoURL
                                                               cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                           timeoutInterval:10];
    
    [httpRequest setValue:@"application/json"
       forHTTPHeaderField:@"Content-Type"];
    
    [NSURLConnection sendAsynchronousRequest:httpRequest
                                       queue:NSOperationQueue.new
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               if (!connectionError) {
                                   NSError *error;
                                   
                                   NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data
                                                                                            options:NSJSONReadingAllowFragments
                                                                                              error:&error];
                                   dispatch_async(dispatch_get_main_queue(), ^(void){
                                       NSDictionary *filesInfo = [jsonData valueForKeyPath:@"request.files.h264"];
                                       if (!filesInfo) {
                                           succeedBlock(nil,nil);
                                       }
                                       NSString *quality = NSString.new;
                                       if (self.vimeoVideoQuality == MHVimeoVideoQualityHD) {
                                           quality = @"hd";
                                           if(!filesInfo[quality]){
                                               quality = @"sd";
                                           }
                                       } else if (self.vimeoVideoQuality == MHVimeoVideoQualityMobile){
                                           quality = @"mobile";
                                       }else if(self.vimeoVideoQuality == MHVimeoVideoQualitySD){
                                           quality = @"sd";
                                       }
                                       NSDictionary *videoInfo =filesInfo[quality];
                                       if (!videoInfo[@"url"]) {
                                           succeedBlock(nil,nil);
                                       }
                                       succeedBlock([NSURL URLWithString:videoInfo[@"url"]],nil);
                                   });
                               }else{
                                   succeedBlock(nil,connectionError);
                               }
                               
                           }];
}

-(void)setObjectToUserDefaults:(NSMutableDictionary*)dict{
    [NSUserDefaults.standardUserDefaults setObject:dict forKey:MHGalleryDurationData];
    [NSUserDefaults.standardUserDefaults synchronize];
}
-(NSMutableDictionary*)durationDict{
    return [NSMutableDictionary.alloc initWithDictionary:[NSUserDefaults.standardUserDefaults objectForKey:MHGalleryDurationData]];
}


-(void)getYoutubeThumbImage:(NSString*)URL
               successBlock:(void (^)(UIImage *image,NSUInteger videoDuration,NSError *error,NSURL *imageURL))succeedBlock{
    
    [SDImageCache.sharedImageCache
     queryDiskCacheForKey:URL
     done:^(UIImage *image, SDImageCacheType cacheType)
     {
         if (image) {
             NSMutableDictionary *dict = [self durationDict];
             succeedBlock(image,[dict[URL] integerValue],nil, [NSURL URLWithString:URL]);
         }else{
             NSString *videoID = [[URL componentsSeparatedByString:@"?v="] lastObject];
             
             [[XCDYouTubeClient defaultClient]
              getVideoWithIdentifier:videoID
              completionHandler:^(XCDYouTubeVideo *video, NSError *error)
              {
                  if (video) {
                      NSURL *resultUrl = nil;
                      NSDictionary *streamUrls = video.streamURLs;
                      
                      if (self.youtubeVideoQuality == MHYoutubeVideoQualityHD720) {
                          resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualityHD720)];
                      } else if (self.youtubeVideoQuality == MHYoutubeVideoQualityMedium) {
                          resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualityMedium360)];
                      } else if(self.youtubeVideoQuality == MHYoutubeVideoQualitySmall){
                          resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualitySmall240)];
                      }
                      
                      if (resultUrl == nil) {
                          resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualityMedium360)];
                          if(resultUrl == nil){
                              resultUrl = [streamUrls objectForKey:@(XCDYouTubeVideoQualitySmall240)];
                          }
                      }
                      
                      
                      NSMutableDictionary *dictToSave = [self durationDict];
                      dictToSave[URL] = @(video.duration);
                      
                      [self setObjectToUserDefaults:dictToSave];
                      
                      NSURL *thumbURL = nil;
                      if (self.youtubeThumbQuality == MHYoutubeThumbQualityHQ) {
                          thumbURL = video.largeThumbnailURL;
                      }else if (self.youtubeThumbQuality == MHYoutubeThumbQualitySQ){
                          thumbURL = video.mediumThumbnailURL;
                      }
                      
                      if (thumbURL == nil) {
                          thumbURL = video.smallThumbnailURL;
                      }
                      
                      [SDWebImageManager.sharedManager
                       downloadImageWithURL:thumbURL
                       options:SDWebImageContinueInBackground
                       progress:nil
                       completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL)
                       {
                           [SDImageCache.sharedImageCache removeImageForKey:thumbURL.absoluteString];
                           [SDImageCache.sharedImageCache storeImage:image
                                                              forKey:URL];
                           if([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive)
                           {
                               succeedBlock(image, video.duration, nil, [NSURL URLWithString:URL]);
                           }
                       }];
                      
                  } else {
                      succeedBlock(nil,0,error, nil);
                  }
              }];
         }
     }];
    
}


-(void)getVimdeoThumbImage:(NSString*)URL
              successBlock:(void (^)(UIImage *image,NSUInteger videoDuration,NSError *error,NSURL *imageURL))succeedBlock{
    
    NSString *videoID = [[URL componentsSeparatedByString:@"/"] lastObject];
    NSString *vimdeoURLString= [NSString stringWithFormat:MHVimeoThumbBaseURL, videoID];
    NSURL *vimdeoURL= [NSURL URLWithString:vimdeoURLString];
    
    [SDImageCache.sharedImageCache
     queryDiskCacheForKey:vimdeoURLString
     done:^(UIImage *image, SDImageCacheType cacheType)
     {
         if (image) {
             NSMutableDictionary *dict = [self durationDict];
             succeedBlock(image,[dict[vimdeoURLString] integerValue],nil, [NSURL URLWithString:vimdeoURLString]);
         }else{
             NSMutableURLRequest *httpRequest = [NSMutableURLRequest requestWithURL:vimdeoURL
                                                                        cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                                    timeoutInterval:10];
             [NSURLConnection
              sendAsynchronousRequest:httpRequest
              queue:NSOperationQueue.new
              completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
              {
                  if (connectionError) {
                      succeedBlock(nil,0,connectionError, nil);
                  }else{
                      NSError *error;
                      NSArray *jsonData = [NSJSONSerialization JSONObjectWithData:data
                                                                          options:NSJSONReadingAllowFragments
                                                                            error:&error];
                      dispatch_async(dispatch_get_main_queue(), ^(void){
                          if (jsonData.count) {
                              
                              NSString *quality = NSString.new;
                              if (self.vimeoThumbQuality == MHVimeoThumbQualityLarge) {
                                  quality = @"thumbnail_large";
                              } else if (self.vimeoThumbQuality == MHVimeoThumbQualityMedium){
                                  quality = @"thumbnail_medium";
                              }else if(self.vimeoThumbQuality == MHVimeoThumbQualitySmall){
                                  quality = @"thumbnail_small";
                              }
                              if ([jsonData firstObject][quality]) {
                                  NSMutableDictionary *dictToSave = [self durationDict];
                                  dictToSave[vimdeoURLString] = @([jsonData[0][@"duration"] integerValue]);
                                  [self setObjectToUserDefaults:dictToSave];
                                  
                                  [SDWebImageManager.sharedManager
                                   downloadImageWithURL:[NSURL URLWithString:jsonData[0][quality]]
                                   options:SDWebImageContinueInBackground
                                   progress:nil
                                   completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL)
                                   {
                                       [SDImageCache.sharedImageCache removeImageForKey:jsonData[0][quality]];
                                       [SDImageCache.sharedImageCache storeImage:image
                                                                          forKey:vimdeoURLString];
                                       //
                                       // succeedBlock is likely to perform visual tasks, if it were to be OpenGL tasks while in background (mind the SDWebImageContinueInBackground), the app would crash.
                                       // This fix might not suit everybody needs.
                                       if([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive)
                                       {
                                           succeedBlock(image,[jsonData[0][@"duration"] integerValue],nil, [NSURL URLWithString:vimdeoURLString]);
                                       }
                                   }];
                              }else{
                                  succeedBlock(nil,0,nil, nil);
                              }
                              
                          }else{
                              succeedBlock(nil,0,nil, nil);
                          }
                      });
                  }
                  
                  
              }];
         }
     }];
    
}

-(void)startDownloadingThumbImage:(NSString*)urlString
                     successBlock:(void (^)(UIImage *image,NSUInteger videoDuration,NSError *error,NSURL *imageURL))succeedBlock{
    if ([urlString rangeOfString:@"vimeo.com"].location != NSNotFound) {
        [self getVimdeoThumbImage:urlString
                     successBlock:^(UIImage *image, NSUInteger videoDuration, NSError *error,NSURL *imageURL) {
                         succeedBlock(image,videoDuration,error, imageURL);
                     }];
    }else if([urlString rangeOfString:@"youtube.com"].location != NSNotFound) {
        [self getYoutubeThumbImage:urlString
                      successBlock:^(UIImage *image, NSUInteger videoDuration, NSError *error,NSURL *imageURL) {
                          succeedBlock(image,videoDuration,error, imageURL);
                      }];
    }else{
        [self createThumbURL:urlString
                successBlock:^(UIImage *image, NSUInteger videoDuration, NSError *error,NSURL *imageURL) {
                    succeedBlock(image,videoDuration,error, imageURL);
                }];
    }
}


-(void)getMHGalleryObjectsForYoutubeChannel:(NSString*)channelName
                                  withTitle:(BOOL)withTitle
                               successBlock:(void (^)(NSArray *MHGalleryObjects,NSError *error))succeedBlock{
    NSMutableURLRequest *httpRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:MHYoutubeChannel,channelName]] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:5];
    [NSURLConnection sendAsynchronousRequest:httpRequest queue:NSOperationQueue.new completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            succeedBlock(nil,connectionError);
            
        }else{
            dispatch_sync(dispatch_get_main_queue(), ^{
                
                NSError *error = nil;
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data
                                                                     options: NSJSONReadingMutableContainers
                                                                       error: &error];
                if (!error) {
                    NSMutableArray *galleryData = NSMutableArray.new;
                    for (NSDictionary *dictionary in dict[@"feed"][@"entry"]) {
                        NSString *string = [dictionary[@"link"] firstObject][@"href"];
                        
                        string = [string stringByReplacingOccurrencesOfString:@"&feature=youtube_gdata" withString:@""];
                        MHGalleryItem *item = [MHGalleryItem itemWithURL:string galleryType:MHGalleryTypeVideo];
                        if (withTitle) {
                            item.descriptionString = dictionary[@"title"][@"$t"];
                        }
                        [galleryData addObject:item];
                    }
                    succeedBlock(galleryData,nil);
                }else{
                    succeedBlock(nil,error);
                }
            });
        }
    }];
}


+(NSString*)stringForMinutesAndSeconds:(NSInteger)seconds
                              addMinus:(BOOL)addMinus{
    
    NSNumber *minutesNumber = @(seconds / 60);
    NSNumber *secondsNumber = @(seconds % 60);
    
    NSString *string = [NSString stringWithFormat:@"%@:%@",[MHNumberFormatterVideo() stringFromNumber:minutesNumber],[MHNumberFormatterVideo() stringFromNumber:secondsNumber]];
    if (addMinus) {
        return [NSString stringWithFormat:@"-%@",string];
    }
    return string;
}

@end