// -*- mode: ObjC -*-

//  This file is part of class-dump, a utility for examining the Objective-C segment of Mach-O files.
//  Copyright (C) 1997-1998, 2000-2001, 2004-2014 Steve Nygard.

#import "CDClassDump.h"

#import "CDFatArch.h"
#import "CDFatFile.h"
#import "CDLCDylib.h"
#import "CDMachOFile.h"
#import "CDObjectiveCProcessor.h"
#import "CDType.h"
#import "CDTypeFormatter.h"
#import "CDTypeParser.h"
#import "CDVisitor.h"
#import "CDLCSegment.h"
#import "CDTypeController.h"
#import "CDSearchPathState.h"

NSString *CDErrorDomain_ClassDump = @"CDErrorDomain_ClassDump";
NSString *CDErrorKey_Exception    = @"CDErrorKey_Exception";

@implementation CDClassDump
{
    CDSearchPathState *_searchPathState;
    
    BOOL _shouldProcessRecursively,
         _shouldSortClasses,                // And categories, protocols
         _shouldSortClassesByInheritance,   // And categories, protocols
         _shouldSortMethods;
    
    BOOL _shouldShowIvarOffsets,
         _shouldShowMethodAddresses,
         _shouldShowHeader;
    
    NSRegularExpression *_regularExpression;
    NSString            *_sdkRoot;
    NSMutableDictionary *_machOFilesByName;
    NSMutableArray      *_machOFiles,
                        *_objcProcessors;

    CDTypeController    *_typeController;
    
    CDArch _targetArch;
}

- (id)init;
{
    if (!(self = [super init])) return nil;
    _sdkRoot            = nil;
    _searchPathState    = CDSearchPathState.new;
    _machOFiles         = NSMutableArray.new;
    _machOFilesByName   = NSMutableDictionary.new;
    _objcProcessors     = NSMutableArray.new;
    _typeController     = [CDTypeController.alloc initWithClassDump:self];
    
    // These can be ppc, ppc7400, ppc64, i386, x86_64
    _targetArch.cputype     = CPU_TYPE_ANY;
    _targetArch.cpusubtype  = 0;
    
    _shouldShowHeader = YES;
    return self;
}

#pragma mark - Regular expression handling

- (BOOL)shouldShowName:(NSString *)name;
{
    return !!_regularExpression
    ? !![self.regularExpression firstMatchInString:name options:(NSMatchingOptions)0
                                             range:NSMakeRange(0, [name length])]
    : YES;
}

#pragma mark -

- (BOOL)containsObjectiveCData;
{
    for (CDObjectiveCProcessor *processor in self.objcProcessors)
        if ([processor hasObjectiveCData]) return YES;
    return NO;
}

- (BOOL)hasEncryptedFiles;
{
    for (CDMachOFile *machOFile in self.machOFiles)
        if ([machOFile isEncrypted]) return YES;
    return NO;
}

- (BOOL)hasObjectiveCRuntimeInfo;
{
    return self.containsObjectiveCData || self.hasEncryptedFiles;
}

- (BOOL)loadFile:(CDFile *)file error:(NSError *__autoreleasing *)error;
{
    //NSLog(@"targetArch: (%08x, %08x)", targetArch.cputype, targetArch.cpusubtype);
    CDMachOFile *machOFile = [file machOFileWithArch:_targetArch];
    //NSLog(@"machOFile: %@", machOFile);
    if (!machOFile) {
        if (error != NULL) {

            NSString *targetArchName = CDNameForCPUType(_targetArch.cputype, _targetArch.cpusubtype);

            NSString *failureReason  = [file isKindOfClass:[CDFatFile class]] &&
                                       [(CDFatFile *)file containsArchitecture:_targetArch]
            ? [NSString stringWithFormat:@"Fat file doesn't contain a valid Mach-O file for the specified architecture (%@).  "
                                          "It probably means that class-dump was run on a static library, which is not supported.", targetArchName]
            : [NSString stringWithFormat:@"File doesn't contain the specified architecture (%@).  Available architectures are %@.", targetArchName, file.architectureNameDescription];

            NSDictionary *userInfo = @{ NSLocalizedFailureReasonErrorKey : failureReason };
            *error = [NSError errorWithDomain:CDErrorDomain_ClassDump code:0 userInfo:userInfo];
        }
        return NO;
    }

    // Set before processing recursively.  This was getting caught on CoreUI on 10.6
    assert([machOFile filename] != nil);
    [_machOFiles addObject:machOFile];
    _machOFilesByName[machOFile.filename] = machOFile;

    if ([self shouldProcessRecursively]) {
        @try {
            for (CDLoadCommand *loadCommand in [machOFile loadCommands]) {
                if ([loadCommand isKindOfClass:[CDLCDylib class]]) {
                    CDLCDylib *dylibCommand = (CDLCDylib *)loadCommand;
                    if ([dylibCommand cmd] == LC_LOAD_DYLIB) {
                        [self.searchPathState pushSearchPaths:[machOFile runPaths]];
                        {
                            NSString *loaderPathPrefix = @"@loader_path";
                            NSString *path = [dylibCommand path];
                            if ([path hasPrefix:loaderPathPrefix]) {
                                NSString *loaderPath = [machOFile.filename stringByDeletingLastPathComponent];
                                path = [[path stringByReplacingOccurrencesOfString:loaderPathPrefix withString:loaderPath] stringByStandardizingPath];
                            }
                            [self machOFileWithName:path]; // Loads as a side effect
                        }
                        [self.searchPathState popSearchPaths];
                    }
                }
            }
        }
        @catch (NSException *exception) {
            NSLog(@"Caught exception: %@", exception);
            if (error != NULL) {
                NSDictionary *userInfo = @{
                NSLocalizedFailureReasonErrorKey : @"Caught exception",
                            CDErrorKey_Exception : exception };
                *error = [NSError errorWithDomain:CDErrorDomain_ClassDump code:0 userInfo:userInfo];
            }
            return NO;
        }
    }
    return YES;
}

#pragma mark -

- (void)processObjectiveCData;
{
    for (CDMachOFile *machOFile in self.machOFiles) {
        CDObjectiveCProcessor *processor = [[[machOFile processorClass] alloc] initWithMachOFile:machOFile];
        [processor process];
        [_objcProcessors addObject:processor];
    }
}

// This visits everything segment processors, classes, categories.  It skips over modules.  Need something to visit modules so we can generate separate headers.
- (void)recursivelyVisit:(CDVisitor *)visitor;
{
    [visitor willBeginVisiting];

    for (CDObjectiveCProcessor *processor in self.objcProcessors)
        [processor recursivelyVisit:visitor];

    [visitor didEndVisiting];
}

- (CDMachOFile *)machOFileWithName:(NSString *)name;
{
    NSString *adjustedName = nil;
    NSString *executablePathPrefix = @"@executable_path";
    NSString *rpathPrefix = @"@rpath";

    if ([name hasPrefix:executablePathPrefix]) {
        adjustedName = [name stringByReplacingOccurrencesOfString:executablePathPrefix withString:self.searchPathState.executablePath];
    } else if ([name hasPrefix:rpathPrefix]) {
        //NSLog(@"Searching for %@ through run paths: %@", name, [searchPathState searchPaths]);
        for (NSString *searchPath in [self.searchPathState searchPaths]) {
            NSString *str = [name stringByReplacingOccurrencesOfString:rpathPrefix withString:searchPath];
            //NSLog(@"trying %@", str);
            if ([NSFileManager.defaultManager fileExistsAtPath:str]) {
                adjustedName = str;
                //NSLog(@"Found it!");
                break;
            }
        }
        adjustedName = adjustedName ?: name; //NSLog(@"Did not find it.");

    } else adjustedName = self.sdkRoot ? [self.sdkRoot stringByAppendingPathComponent:name] : name;

    CDMachOFile *machOFile = _machOFilesByName[adjustedName];
    if (!machOFile) {

        CDFile *file = [CDFile fileWithContentsOfFile:adjustedName searchPathState:self.searchPathState];

        !file || ![self loadFile:file error:NULL] ?
            NSLog(@"Warning: Failed to load: %@", adjustedName) : nil;

        !(machOFile = _machOFilesByName[adjustedName]) ?
            NSLog(@"Warning: Couldn't load MachOFile with ID: %@, adjustedID: %@", name, adjustedName) : nil;
    }

    return machOFile;
}

- (void)appendHeaderToString:(NSMutableString *)resultString;
{
    // Since this changes each version, for regression testing it'll be better to be able to not show it.
    if (!self.shouldShowHeader) return;

    [resultString appendFormat: @"/*"
        CD_NEWLINE "Generated by 𝖼𝗅𝖺𝗌𝗌-𝖽𝗎𝗆𝗉 %s"
        CD_NEWLINE "𝖼𝗅𝖺𝗌𝗌-𝖽𝗎𝗆𝗉 is Copyright © 1997-1998, 2000-2001, 2004-2014 by Steve Nygard."
        "%@"                // SDK ?
        "\n */\n\n",        // END HEADER BANNER
        CLASS_DUMP_VERSION, CD_MAYBE_FMT(_sdkRoot,"SDK Root:%@",_sdkRoot)];
}

- (void)registerTypes;
{
    for (CDObjectiveCProcessor *processor in self.objcProcessors)
        [processor registerTypesWithObject:self.typeController phase:0];

    [self.typeController endPhase:0];
    [self.typeController workSomeMagic];
}

- (void)showHeader;
{
    if (self.machOFiles.count) [[self.machOFiles.lastObject headerString:YES] print];
}

- (void)showLoadCommands;
{
    if (self.machOFiles.count) [[self.machOFiles.lastObject loadCommandString:YES] print];
}

@end
