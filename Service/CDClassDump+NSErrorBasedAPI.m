//
//  CDClassDump+NSErrorBasedAPI.m
//  class-dump
//
//  Created by Damien DeVille on 8/3/13.
//  Copyright (c) 2013 Damien DeVille. All rights reserved.
//

#import "CDClassDump+NSErrorBasedAPI.h"
@import ClassDump;
#import "ClassDump-Constants.h"
#import "ClassDumpService-Constants.h"

@implementation CDClassDump (NSErrorBasedAPI)

- (BOOL)fmw_loadFile:(CDFile *)file error:(NSError **)errorRef
{
    NSError *error = nil;
    
    BOOL loaded = [self loadFile:file error:&error];
    if (loaded) {
        return YES;
    }
    
    if (errorRef == NULL) {
        return NO;
    }
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setValue:NSLocalizedStringFromTableInBundle(@"There was an unknown error while loading the file", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"CDClassDump+Extensions file loading error description") forKey:NSLocalizedDescriptionKey];
    [userInfo setValue:[error localizedDescription] forKey:NSLocalizedRecoverySuggestionErrorKey];
    *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorFileLoading userInfo:userInfo];
    
    return NO;
}

@end
