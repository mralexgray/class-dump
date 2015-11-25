//
//  CDClassDumpOperation.m
//  class-dump
//
//  Created by Damien DeVille on 8/3/13.
//  Copyright (c) 2013 Damien DeVille. All rights reserved.
//

#import "CDClassDumpOperation.h"

#import "CDClassDumpServerInterface.h"

#import "ClassDump-Constants.h"
#import "ClassDumpService-Constants.h"

@interface CDClassDumpOperation ()

@property (copy, nonatomic) NSURL *bundleOrExecutableLocation;
@property (copy, nonatomic) NSURL *exportDirectoryLocation;

@property (strong, nonatomic) NSXPCConnection *connection;

@end

@interface CDClassDumpOperation (/* NSOperation */)

@property (assign, nonatomic) BOOL isExecuting, isFinished;

@property (readwrite, copy, atomic) NSURL * (^completionProvider)(NSError **errorRef);

@end

@implementation CDClassDumpOperation

- (id)initWithBundleOrExecutableLocation:(NSURL *)bundleOrExecutableLocation exportDirectoryLocation:(NSURL *)exportDirectoryLocation
{
    self = [self init];
    if (self == nil) {
        return nil;
    }
    
    NSParameterAssert(bundleOrExecutableLocation != nil);
    _bundleOrExecutableLocation = [bundleOrExecutableLocation copy];
    
    NSParameterAssert(exportDirectoryLocation != nil);
    _exportDirectoryLocation = [exportDirectoryLocation copy];
    
    _completionProvider = [^ NSURL * (NSError **errorRef) {
        if (errorRef != NULL) {
            *errorRef = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
        }
        return nil;
    } copy];
    
    [self _setupXPCConnection];
    
    return self;
}

- (BOOL)isConcurrent
{
    return YES;
}

- (void)start
{
    void (^setExecuting)(BOOL) = ^ void (BOOL executing) {
        [self willChangeValueForKey:@"isExecuting"];
        [self setIsExecuting:executing];
        [self didChangeValueForKey:@"isExecuting"];
    };
    
    void (^setFinished)(BOOL) = ^ void (BOOL finished) {
        [self willChangeValueForKey:@"isFinished"];
        [self setIsFinished:finished];
        [self didChangeValueForKey:@"isFinished"];
    };
    
    if ([self isCancelled]) {
        setFinished(YES);
        return;
    }
    
    setExecuting(YES);
    
    [self _doAsynchronousWorkWithReacquirer:^ {
        setExecuting(NO);
        setFinished(YES);
    }];
}

- (void)_setupXPCConnection
{
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithServiceName:CDClassDumpServiceName];
    [self setConnection:connection];
    
    NSXPCInterface *classDumpServerInterface = [NSXPCInterface interfaceWithProtocol:@protocol(CDClassDumpServerInterface)];
    [classDumpServerInterface setClasses:[NSSet setWithObjects:[NSData class], nil] forSelector:@selector(classDumpBundleOrExecutableBookmarkData:exportDirectoryBookmarkData:response:) argumentIndex:0 ofReply:NO];
    [classDumpServerInterface setClasses:[NSSet setWithObjects:[NSData class], nil] forSelector:@selector(classDumpBundleOrExecutableBookmarkData:exportDirectoryBookmarkData:response:) argumentIndex:1 ofReply:NO];
    [classDumpServerInterface setClasses:[NSSet setWithObjects:[NSNumber class], nil] forSelector:@selector(classDumpBundleOrExecutableBookmarkData:exportDirectoryBookmarkData:response:) argumentIndex:0 ofReply:YES];
    [classDumpServerInterface setClasses:[NSSet setWithObjects:[NSError class], nil] forSelector:@selector(classDumpBundleOrExecutableBookmarkData:exportDirectoryBookmarkData:response:) argumentIndex:1 ofReply:YES];
    
    [connection setRemoteObjectInterface:classDumpServerInterface];
    [connection resume];
}

- (void)_doAsynchronousWorkWithReacquirer:(void (^)(void))reacquirer
{
    NSURL *bundleOrExecutableLocation = [self bundleOrExecutableLocation];
    
    NSError *bundleOrExecutableBookmarkDataCreationError = nil;
    NSData *bundleOrExecutableBookmarkData = [self _createBundleOrExecutableBookmarkData:bundleOrExecutableLocation error:&bundleOrExecutableBookmarkDataCreationError];
    if (bundleOrExecutableBookmarkData == nil) {
        [self setCompletionProvider:^ NSURL * (NSError **errorRef) {
            if (errorRef != NULL) {
                *errorRef = bundleOrExecutableBookmarkDataCreationError;
            }
            return nil;
        }];
        return;
    }
    
    NSURL *exportDirectoryLocation = [self exportDirectoryLocation];
    
    NSError *exportDirectoryBookmarkDataCreationError = nil;
    NSData *exportDirectoryBookmarkData = [self _createExportDirectoryBookmarkData:exportDirectoryLocation error:&exportDirectoryBookmarkDataCreationError];
    if (exportDirectoryBookmarkData == nil) {
        [self setCompletionProvider:^ NSURL * (NSError **errorRef) {
            if (errorRef != NULL) {
                *errorRef = exportDirectoryBookmarkDataCreationError;
            }
            return nil;
        }];
        return;
    }
    
    id <CDClassDumpServerInterface> classDumpServer = [[self connection] remoteObjectProxyWithErrorHandler:^ (NSError *error) {
        NSError *classDumpError = [self _remoteProxyObjectError:error];
        [self setCompletionProvider:^ id (NSError **errorRef) {
            if (errorRef != NULL) {
                *errorRef = classDumpError;
            }
            return nil;
        }];
        
        reacquirer();
    }];
    
    [classDumpServer classDumpBundleOrExecutableBookmarkData:bundleOrExecutableBookmarkData exportDirectoryBookmarkData:exportDirectoryBookmarkData response:^ (NSNumber *success, NSError *error) {
        [self setCompletionProvider:^ NSURL * (NSError **errorRef) {
            if (errorRef != NULL) {
                *errorRef = error;
            }
            return (success != nil) ? exportDirectoryLocation : nil;
        }];
        
        reacquirer();
    }];
}

- (NSData *)_createBundleOrExecutableBookmarkData:(NSURL *)bundleOrExecutableLocation error:(NSError **)errorRef
{
    NSError *bookmarkDataCreationError = nil;
    NSData *bookmarkData = [bundleOrExecutableLocation bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)0 includingResourceValuesForKeys:nil relativeToURL:nil error:&bookmarkDataCreationError];
    if (bookmarkData == nil) {
        if (errorRef != NULL) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Couldn\u2019t open the executable", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"_CDClassDumpOperation executable access error description"),
                NSLocalizedRecoverySuggestionErrorKey : NSLocalizedStringFromTableInBundle(@"There was an unknown error while opening the executable. Please try again.", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"_CDClassDumpOperation executable access error recovery suggestion"),
                NSUnderlyingErrorKey : bookmarkDataCreationError,
            };
            *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorExportDirectoryCreationError userInfo:userInfo];
        }
        return nil;
    }
    return bookmarkData;
}

- (NSData *)_createExportDirectoryBookmarkData:(NSURL *)exportDirectoryLocation error:(NSError **)errorRef
{
    void (^wrapAndPopulateError)(NSError *) = ^ void (NSError *error) {
        if (errorRef != NULL) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Couldn\u2019t create the export directory", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"_CDClassDumpOperation export directory creation error description"),
                NSLocalizedRecoverySuggestionErrorKey : NSLocalizedStringFromTableInBundle(@"There was an unknown error while creating the export directory. Please try again.", nil, [NSBundle bundleWithIdentifier:CDClassDumpServiceBundleIdentifier], @"_CDClassDumpOperation export directory creation error recovery suggestion"),
                NSUnderlyingErrorKey : error,
            };
            *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorExportDirectoryCreationError userInfo:userInfo];
        }
    };
    
    NSError *exportDirectoryCreationError = nil;
    BOOL exportDirectoryCreated = [[NSFileManager defaultManager] createDirectoryAtURL:exportDirectoryLocation withIntermediateDirectories:YES attributes:nil error:&exportDirectoryCreationError];
    if (!exportDirectoryCreated) {
        wrapAndPopulateError(exportDirectoryCreationError);
        return nil;
    }
    
    NSError *bookmarkDataCreationError = nil;
    NSData *bookmarkData = [exportDirectoryLocation bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)0 includingResourceValuesForKeys:nil relativeToURL:nil error:&bookmarkDataCreationError];
    if (bookmarkData == nil) {
        wrapAndPopulateError(bookmarkDataCreationError);
        return nil;
    }
    
    return bookmarkData;
}

- (NSError *)_remoteProxyObjectError:(NSError *)error
{
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Couldn\u2019t complete class-dump for this executable", nil, [NSBundle bundleWithIdentifier:CDClassDumpBundleIdentifier], @"CDClassDumpOperation XPC error description"),
        NSLocalizedRecoverySuggestionErrorKey : NSLocalizedStringFromTableInBundle(@"There was an unknown error when talking to a helper application.", nil, [NSBundle bundleWithIdentifier:CDClassDumpBundleIdentifier], @"CDClassDumpOperation XPC error recovery suggestion"),
        NSUnderlyingErrorKey : error,
    };
    return [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorXPCService userInfo:userInfo];
}

@end
