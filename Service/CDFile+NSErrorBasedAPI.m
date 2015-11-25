//
//  CDFile+NSErrorBasedAPI.m
//  class-dump
//
//  Created by Damien DeVille on 8/3/13.
//  Copyright (c) 2013 Damien DeVille. All rights reserved.
//

#import "CDFile+NSErrorBasedAPI.h"
@import ClassDump;
#import "ClassDump-Constants.h"
#import "ClassDumpService-Constants.h"

#define CDFileRecoverySuggestion    NSLocalizedStringFromTableInBundle(@"Please make sure that the file you have selected is an executable, a framework or an application bundle.", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"CDFile+Extensions input file not executable error recovery suggestion")

@implementation CDFile (NSErrorBasedAPI)

+ (id)fmw_fileWithContentsOfFile:(NSString *)filename searchPathState:(CDSearchPathState *)searchPathState error:(NSError **)errorRef
{
    CDFile *file = [self fileWithContentsOfFile:filename searchPathState:searchPathState];
    if (file != nil) {
        return file;
    }
    
    if (errorRef == NULL) {
        return nil;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:filename]) {
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"The input file doesn\u2019t contain an executable", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"CDFile+Extensions input file not executable error description"),
            NSLocalizedRecoverySuggestionErrorKey : CDFileRecoverySuggestion,
        };
        *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorExecutableNotFound userInfo:userInfo];
        
        return nil;
    }
    
    if (![[NSFileManager defaultManager] isReadableFileAtPath:filename]) {
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"The executable is not readable", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"CDFile+Extensions input file not readable error description"),
            NSLocalizedRecoverySuggestionErrorKey : CDFileRecoverySuggestion,
        };
        *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorExecutableNotReadable userInfo:userInfo];
        
        return nil;
    }
    
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"The executable type is not supported", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"CDFile+Extensions input file not readable error description"),
        NSLocalizedRecoverySuggestionErrorKey : CDFileRecoverySuggestion,
    };
    *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorExecutableUnsupportedType userInfo:userInfo];
    
    return nil;
}

- (BOOL)fmw_bestMatchForArch:(CDArch *)ioArchPtr error:(NSError **)errorRef
{
    BOOL archRetrieved = [self bestMatchForArch:ioArchPtr];
    if (archRetrieved) {
        return YES;
    }
    
    if (errorRef == NULL) {
        return NO;
    }
    
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Couldn\u2019t retrieve executable architecture", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"CDFile+Extensions arch retrieval error description"),
        NSLocalizedRecoverySuggestionErrorKey : NSLocalizedStringFromTableInBundle(@"Please make sure that the executable that you have selected is either a Mach-O file or a fat archive.", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"CDFile+Extensions arch retrieval error recovery suggestion"),
    };
    *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorCannotRetrieveArch userInfo:userInfo];
    
    return NO;
}

@end

#undef CDFileRecoverySuggestion
