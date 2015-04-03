//
//  CDClassDumpOperation.h
//  class-dump
//
//  Created by Damien DeVille on 8/3/13.
//  Copyright (c) 2013 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CDClassDumpOperation : NSOperation

+ (instancetype) instanceWithBundleOrExecutable:(NSURL*)bundleOrExecutableLoc
                                      exportDir:(NSURL*)exportDirectoryLoc;

@property (readonly,copy) NSURL* (^completionProvider)(NSError**errorRef);

@end
