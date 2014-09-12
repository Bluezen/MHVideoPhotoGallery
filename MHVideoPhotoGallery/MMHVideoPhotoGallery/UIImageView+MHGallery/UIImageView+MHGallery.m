//
//  UIImageView+MHGallery.m
//  MHVideoPhotoGallery
//
//  Created by Mario Hahn on 06.02.14.
//  Copyright (c) 2014 Mario Hahn. All rights reserved.
//

#import "UIImageView+MHGallery.h"
#import "MHGallery.h"
#import <SDWebImage/SDImageCache.h>
#import <SDWebImage/UIImageView+WebCache.h>

@implementation UIImageView (MHGallery)

-(void)setThumbWithURL:(NSString*)URL
          successBlock:(void (^)(UIImage *image,NSUInteger videoDuration,NSError *error, NSURL *imageURL))succeedBlock{
    
    __weak typeof(self) weakSelf = self;
    
    [MHGallerySharedManager.sharedManager startDownloadingThumbImage:URL
                                                        successBlock:^(UIImage *image, NSUInteger videoDuration, NSError *error, NSURL *imageURL) {
                                                            
                                                            if (!weakSelf) return;
                                                            dispatch_main_sync_safe(^{
                                                                if (!weakSelf) return;
                                                                if (image){
                                                                    weakSelf.image = image;
                                                                    [weakSelf setNeedsLayout];
                                                                }
                                                                if (succeedBlock) {                                                                     succeedBlock(image,videoDuration,error,imageURL);
                                                                }
                                                            });
                                                        }];
}

-(void)setImageForMHGalleryItem:(MHGalleryItem*)item
                      imageType:(MHImageType)imageType
                   successBlock:(void (^)(UIImage *image,NSError *error))succeedBlock{
    
    __weak typeof(self) weakSelf = self;
    
    if ([item.URLString rangeOfString:MHAssetLibrary].location != NSNotFound && item.URLString) {
        
        MHAssetImageType assetType = MHAssetImageTypeThumb;
        if (imageType == MHImageTypeFull) {
            assetType = MHAssetImageTypeFull;
        }
        
        [MHGallerySharedManager.sharedManager getImageFromAssetLibrary:item.URLString
                                                             assetType:assetType
                                                          successBlock:^(UIImage *image, NSError *error) {
                                                              [weakSelf setImage:image imageType:imageType successBlock:succeedBlock];
                                                          }];
    }else if(item.image){
        [self setImage:item.image imageType:imageType successBlock:succeedBlock];
    }else{
        
        NSString *placeholderURL = item.thumbnailURL;
        NSString *toLoadURL = item.URLString;
        
        if (imageType == MHImageTypeThumb) {
            toLoadURL = item.thumbnailURL;
            placeholderURL = item.URLString;
        }
        
        [SDImageCache.sharedImageCache
         queryDiskCacheForKey:placeholderURL
         done:^(UIImage *image, SDImageCacheType cacheType) {
             
             if (image != nil)
             {
                 if ([placeholderURL isEqualToString:toLoadURL]) {
                     [weakSelf setImage:image imageType:imageType successBlock:succeedBlock];
                     return;
                 } else {
                     [weakSelf setImage:image imageType:imageType successBlock:nil];
                 }
             }
        
             [SDWebImageManager.sharedManager
              downloadImageWithURL:[NSURL URLWithString:toLoadURL]
              options:SDWebImageContinueInBackground|SDWebImageTransformAnimatedImage
              progress:nil
              completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL)
              {
                  [weakSelf setImage:image imageType:imageType successBlock:succeedBlock];
                  
              }];
        }];
        
        
    }
}


-(void)setImage:(UIImage*)image
      imageType:(MHImageType)imageType
   successBlock:(void (^)(UIImage *image,NSError *error))succeedBlock{
    
    __weak typeof(self) weakSelf = self;
    
    if (!weakSelf) return;
    dispatch_main_sync_safe(^{
        weakSelf.image = image;
        [weakSelf updateContentModeForImageType:imageType];
        [weakSelf setNeedsLayout];
        if (succeedBlock) {
            succeedBlock(image,nil);
        }
    });
}

-(void)updateContentModeForImageType:(MHImageType)imageType
{
    if (imageType == MHImageTypeThumb) {
        self.contentMode = UIViewContentModeScaleAspectFill;
        return;
    }
    
    CGSize  imgSize = self.image.size;
    
    CGFloat heightThreshold = self.bounds.size.height * 0.50f;
    CGFloat widthThreshold  = self.bounds.size.width  * 0.50f;
    
    if (imgSize.height > heightThreshold || imgSize.width > widthThreshold || self.image.images.count > 1) {
        self.contentMode = UIViewContentModeScaleAspectFit;
    } else {
        self.contentMode = UIViewContentModeCenter;
    }
}

@end
