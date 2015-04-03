
//  CDClassDumpServer.m  class-dump
//  Created by Damien DeVille on 8/3/13. Copyright (c) 2013 Damien DeVille. All rights reserved.

#import "_CDClassDumpServer.h"
#import "CDClassDumpServerInterface.h"
#import "_CDClassDumpInternalOperation.h"
#import "ClassDump-Constants.h"
#import "ClassDumpService-Constants.h"

@interface _CDClassDumpServer ()    @property (nonatomic) NSOperationQueue *operationQueue; @end

@implementation _CDClassDumpServer - init { return self = super.init ? _operationQueue = NSOperationQueue.new, self : nil; }

#pragma mark - CDClassDumpServerInterface

- (void)classDumpBundleOrExecutableBookmarkData:(NSData *)bundleOrExecutableBookmarkData
                    exportDirectoryBookmarkData:(NSData *)exportDirectoryBookmarkData
                                       response:(void (^)(NSNumber *success, NSError *error))response
{
    NSError * bundleOrExecutableRetrievalError = nil, * exportLocationRetrievalError = nil;
    NSURL * bundleOrExecutableLocation, * exportDirectoryLocation;
    _CDClassDumpInternalOperation * classDumpOperation; NSOperation *responseOperation;

    if (!(bundleOrExecutableLocation  = [self _retrieveBundleOrExecutableLocation:bundleOrExecutableBookmarkData
                                                                            error:&bundleOrExecutableRetrievalError]))
                                                              return response(nil, bundleOrExecutableRetrievalError);

    if (!(exportDirectoryLocation  = [self _retrieveExportDirectoryLocation:exportDirectoryBookmarkData
                                                                      error:&exportLocationRetrievalError]))
                                                        return response(nil, exportLocationRetrievalError);

    [self.operationQueue addOperation:classDumpOperation =
       [_CDClassDumpInternalOperation.alloc initWithBundleOrExecutableLocation:bundleOrExecutableLocation
                                                       exportDirectoryLocation:exportDirectoryLocation]];
    
    responseOperation = [NSBlockOperation blockOperationWithBlock:^ { NSError *classDumpError = nil;
        NSURL *exportLocation = [classDumpOperation completionProvider](&classDumpError);
        if (!exportLocation) return response(nil, classDumpError);  response(@YES, nil);
    }];
    [responseOperation addDependency:classDumpOperation];  [self.operationQueue addOperation:responseOperation];
}

#pragma mark - Private

- (NSURL *)_retrieveBundleOrExecutableLocation:(NSData *)bundleOrExecutableBookmarkData error:(NSError **)errorRef
{
    NSError *bundleOrExecutableRetrievalError = nil;
    NSURL *bundleOrExecutableLocation = [NSURL URLByResolvingBookmarkData:bundleOrExecutableBookmarkData options:(NSURLBookmarkResolutionOptions)0 relativeToURL:nil bookmarkDataIsStale:NULL error:&bundleOrExecutableRetrievalError];
    return bundleOrExecutableLocation ?: ({
        if (!!errorRef)
            *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorExportDirectoryCreationError userInfo:@{
                NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Couldn\u2019t open the executable", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"_CDClassDumpServer executable access error description"),
                NSLocalizedRecoverySuggestionErrorKey : NSLocalizedStringFromTableInBundle(@"There was an unknown error while opening the executable. Please try again.", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"_CDClassDumpServer executable access error recovery suggestion"),
                NSUnderlyingErrorKey : bundleOrExecutableRetrievalError}];
    (id)nil; });
}

- (NSURL *)_retrieveExportDirectoryLocation:(NSData *)exportDirectoryBookmarkData error:(NSError **)errorRef
{
    NSError *exportLocationRetrievalError = nil;
    NSURL *exportDirectoryLocation = [NSURL URLByResolvingBookmarkData:exportDirectoryBookmarkData options:(NSURLBookmarkResolutionOptions)0 relativeToURL:nil bookmarkDataIsStale:NULL error:&exportLocationRetrievalError];
    if (!!exportDirectoryLocation) return exportDirectoryLocation;
    if (!!errorRef)
         *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorExportDirectoryCreationError userInfo:@{
                NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Couldn\u2019t create the export directory", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"_CDClassDumpServer export directory creation error description"),
                NSLocalizedRecoverySuggestionErrorKey : NSLocalizedStringFromTableInBundle(@"There was an unknown error while creating the export directory. Please try again.", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"_CDClassDumpServer export directory creation error recovery suggestion"),
                NSUnderlyingErrorKey : exportLocationRetrievalError,
        }];
    return nil;
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener*)listener shouldAcceptNewConnection:(NSXPCConnection*)connection {

    connection.exportedInterface    = [NSXPCInterface interfaceWithProtocol:@protocol(CDClassDumpServerInterface)];
    connection.exportedObject       = self;  [connection resume];  return YES;
}

@end
