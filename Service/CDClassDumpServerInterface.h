//
//  CDClassDumpServerInterface.h
//  class-dump
//
//  Created by Damien DeVille on 8/3/13.
//  Copyright (c) 2013 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol CDClassDumpServerInterface <NSObject>

- (void)classDumpBundleOrExecutableBookmarkData:(NSData*)bundleOrExecutableBookmarkData
                    exportDirectoryBookmarkData:(NSData*)exportDirectoryBookmarkData
                                       response:(void(^)(NSNumber*success, NSError*error))response;

@end
