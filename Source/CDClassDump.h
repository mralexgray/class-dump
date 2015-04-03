// -*- mode: ObjC -*-

//  This file is part of class-dump, a utility for examining the Objective-C segment of Mach-O files.
//  Copyright (C) 1997-1998, 2000-2001, 2004-2014 Steve Nygard.

@import Foundation;
#import "CDFile.h" // For CDArch

#define CLASS_DUMP_BASE_VERSION "3.5 (64 bit)"

#ifdef DEBUG
#define CLASS_DUMP_VERSION CLASS_DUMP_BASE_VERSION " (Debug version compiled " __DATE__ " " __TIME__ ")"
#else
#define CLASS_DUMP_VERSION CLASS_DUMP_BASE_VERSION
#endif

@class CDFile, CDTypeController, CDVisitor, CDSearchPathState;

@interface CDClassDump : NSObject

@property (readonly) CDSearchPathState *searchPathState;

@property BOOL  shouldProcessRecursively,   shouldSortClasses,          shouldSortClassesByInheritance,
                shouldSortMethods,          shouldShowIvarOffsets,      shouldShowMethodAddresses,        shouldShowHeader;

@property NSString *sdkRoot;

@property (strong) NSRegularExpression *regularExpression;
- (BOOL)shouldShowName:(NSString*)name;


@property (readonly) NSArray *machOFiles;
@property (readonly) NSArray *objcProcessors;

@property CDArch targetArch;

@property (readonly) BOOL containsObjectiveCData, hasEncryptedFiles, hasObjectiveCRuntimeInfo;

@property (readonly) CDTypeController *typeController;

- (BOOL) loadFile:(CDFile*)file error:(NSError**)error;
- (void) processObjectiveCData;
- (void) recursivelyVisit:(CDVisitor *)visitor;
- (void) appendHeaderToString:(NSMutableString*)resultString;
- (void) registerTypes;
- (void) showHeader;
- (void) showLoadCommands;

@end    extern NSString *CDErrorDomain_ClassDump, *CDErrorKey_Exception;


#define CD_NEWLINE "\n *\t" // spacing helper
/*! @param IF_TRUE If this parameter resolved to NO, nothing will be printed.
    @param FMT char format string, followed by the appriate number of variadic arguments or the format string. */
#define CD_MAYBE_FMT(IF_TRUE,FMT,...) \
    !!IF_TRUE ? [NSString stringWithFormat:@"" CD_NEWLINE FMT,__VA_ARGS__] : @""
