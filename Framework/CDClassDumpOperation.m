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
@property (copy, nonatomic) NSURL *bundleOrExecutableLocation, *exportDirectoryLocation;
@property (nonatomic) NSXPCConnection *connection;
@end

@interface CDClassDumpOperation (/* NSOperation */)

@property (nonatomic) BOOL isExecuting, isFinished;
@property (readwrite, copy, atomic) NSURL * (^completionProvider)(NSError **errorRef);
@property (readwrite, copy, atomic)  void (^completionReporter)(id info, NSError **errorRef);
@end

@implementation CDClassDumpOperation

+ (instancetype) instanceWithBundleOrExecutable:(NSURL*)b completion:(void(^)(id,NSError**))informer {
    return [self.class.alloc initWithBundleOrExecutable:b completion:informer];
}
+ (instancetype) instanceWithBundleOrExecutable:(NSURL*)bOrELoc
                                      exportDir:(NSURL*)eDir {
    return [self.class.alloc initWithBundleOrExecutable:bOrELoc exportDir:eDir];
}
- (id)initWithBundleOrExecutable:(NSURL*)b completion:(void(^)(id,NSError**))informer { if (!(self = super.init)) return nil;
    NSParameterAssert(b);
    _bundleOrExecutableLocation = b.copy;
    _completionReporter = [informer copy];
    [self _setupXPCConnectionAlt];
    return self;
}
- (id)initWithBundleOrExecutable:(NSURL*)bundleOrExecutableLocation
                       exportDir:(NSURL*)exportDirectoryLocation { if (!(self = super.init)) return nil;

    NSParameterAssert(bundleOrExecutableLocation);  _bundleOrExecutableLocation = bundleOrExecutableLocation.copy;
    NSParameterAssert(exportDirectoryLocation);     _exportDirectoryLocation    = exportDirectoryLocation.copy;

    _completionProvider = [^NSURL*(NSError**errorRef){
        if (errorRef) *errorRef = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
        return nil;
    } copy];
    [self _setupXPCConnection];
    return self;
}
- (BOOL)isConcurrent { return YES; }

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

    if ([self isCancelled]) { setFinished(YES); return; }

    setExecuting(YES);

    [self _doAsynchronousWorkWithReacquirer:^ { setExecuting(NO); setFinished(YES); }];
}

- (void)_setupXPCConnectionAlt {

}
- (void)_setupXPCConnection
{
    NSXPCConnection *connection = [NSXPCConnection.alloc initWithServiceName:CDClassDumpServiceName];
    [self setConnection:connection];
    SEL iSel = @selector(classDumpBundleOrExecutableBookmarkData:exportDirectoryBookmarkData:response:);

    NSXPCInterface *classDumpServerInterface = [NSXPCInterface interfaceWithProtocol:@protocol(CDClassDumpServerInterface)];
    [classDumpServerInterface setClasses:[NSSet setWithObject:  NSData.class] forSelector:iSel argumentIndex:0 ofReply:NO];
    [classDumpServerInterface setClasses:[NSSet setWithObject:  NSData.class] forSelector:iSel argumentIndex:1 ofReply:NO];
    [classDumpServerInterface setClasses:[NSSet setWithObject:NSNumber.class] forSelector:iSel argumentIndex:0 ofReply:YES];
    [classDumpServerInterface setClasses:[NSSet setWithObject: NSError.class] forSelector:iSel argumentIndex:1 ofReply:YES];

    [connection setRemoteObjectInterface:classDumpServerInterface];
    [connection resume];
}

- (void)_doAsynchronousWorkWithReacquirer:(void (^)(void))reacquirer {

    NSURL *bundleOrExecutableLocation = self.bundleOrExecutableLocation;

    NSError *bundleOrExecutableBookmarkDataCreationError = nil;
    NSData *bundleOrExecutableBookmarkData = [self _createBundleOrExecutableBookmarkData:bundleOrExecutableLocation error:&bundleOrExecutableBookmarkDataCreationError];
    if (!bundleOrExecutableBookmarkData)
        return [self setCompletionProvider:^ NSURL * (NSError **errorRef) {
            if (errorRef != NULL) *errorRef = bundleOrExecutableBookmarkDataCreationError;
            return nil;
        }];

    NSURL *exportDirectoryLocation = self.exportDirectoryLocation;
    NSError *exportDirectoryBookmarkDataCreationError = nil;
    NSData *exportDirectoryBookmarkData = [self _createExportDirectoryBookmarkData:exportDirectoryLocation error:&exportDirectoryBookmarkDataCreationError];
    if (!exportDirectoryBookmarkData)
        return [self setCompletionProvider:^ NSURL * (NSError **errorRef) {
            if (!!errorRef) *errorRef = exportDirectoryBookmarkDataCreationError;
            return nil;
        }];

    id <CDClassDumpServerInterface> classDumpServer = [self.connection remoteObjectProxyWithErrorHandler:^ (NSError *error) {
        NSError *classDumpError = [self _remoteProxyObjectError:error];
        [self setCompletionProvider:^ id (NSError **errorRef) {
            if (!!errorRef) *errorRef = classDumpError; return nil;
        }];
        reacquirer();
    }];

    [classDumpServer classDumpBundleOrExecutableBookmarkData:bundleOrExecutableBookmarkData exportDirectoryBookmarkData:exportDirectoryBookmarkData response:^ (NSNumber *success, NSError *error) {
        [self setCompletionProvider:^ NSURL * (NSError **errorRef) {
            if (!!errorRef) *errorRef = error;
            return !!success ? exportDirectoryLocation : nil;
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
                                       NSUnderlyingErrorKey : error};
            *errorRef = [NSError errorWithDomain:CDClassDumpErrorDomain code:CDClassDumpErrorExportDirectoryCreationError userInfo:userInfo];
        }
     };

    NSError *exportDirectoryCreationError = nil;
    BOOL exportDirectoryCreated = [NSFileManager.defaultManager createDirectoryAtURL:exportDirectoryLocation withIntermediateDirectories:YES attributes:nil error:&exportDirectoryCreationError];
    if (!exportDirectoryCreated) return wrapAndPopulateError(exportDirectoryCreationError), nil;

    NSError *bookmarkDataCreationError = nil;
    NSData *bookmarkData = [exportDirectoryLocation bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)0 includingResourceValuesForKeys:nil relativeToURL:nil error:&bookmarkDataCreationError];
    return bookmarkData ?: wrapAndPopulateError(bookmarkDataCreationError), nil;
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
