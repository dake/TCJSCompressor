//
//  TCJSCompressor.h
//  TCKit
//
//  Created by dake on 16/5/26.
//  Copyright © 2016年 dake. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 @brief	Thanks JSMin
 
 code reference: https://github.com/douglascrockford/JSMin
 */

@interface TCJSCompressor : NSObject

// inPath should not be same as outPath
+ (BOOL)compressFile:(NSString *)inPath to:(NSString *)outPath error:(NSError **)err;

@end
