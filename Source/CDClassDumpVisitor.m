// -*- mode: ObjC -*-

//  This file is part of class-dump, a utility for examining the Objective-C segment of Mach-O files.
//  Copyright (C) 1997-1998, 2000-2001, 2004-2014 Steve Nygard.

#import "CDClassDumpVisitor.h"

#include <mach-o/arch.h>

#import "CDClassDump.h"
#import "CDObjectiveCProcessor.h"
#import "CDMachOFile.h"
#import "CDLCDylib.h"
#import "CDLCDylinker.h"
#import "CDLCEncryptionInfo.h"
#import "CDLCRunPath.h"
#import "CDLCSegment.h"
#import "CDLCSourceVersion.h"
#import "CDLCVersionMinimum.h"
#import "CDTypeController.h"

@implementation CDClassDumpVisitor

- (void)willBeginVisiting;
{
    [super willBeginVisiting];
    [self.classDump appendHeaderToString:self.resultString];
    if (self.classDump.hasObjectiveCRuntimeInfo && self.shouldShowStructureSection)
        [self.classDump.typeController appendStructuresToString:self.resultString];
}

- (void)didEndVisiting;
{
    [super didEndVisiting];
    [self writeResultToStandardOutput];
}

- (void)visitObjectiveCProcessor:(CDObjectiveCProcessor *)processor;
{
    CDMachOFile * machOFile = processor.machOFile;
    CDLCDylib * identifier  = machOFile.filetype != MH_DYLIB ? nil : machOFile.dylibIdentifier;

    [self.resultString appendFormat:
        @"#pragma mark - %@\n\n/*"      // MACHO
         CD_NEWLINE "File: %@"          // FILENAME
         "%@"                           // UUID ?
         CD_NEWLINE "Arch: %@"          // ARCH
         "%@"                           // DYLD ?
         "%@"                           // VERSION ?
         "%@"                           // AVAILABILITY OSX ?
         "%@"                           // AVAILABILITY iOS ?
         "%@"                           // GC ?
         "%@"                           // DYLD_ENV ?
         "%@"                           // RUNPATHS ?
         "%@"                           // ENCRYPTION ?
         "%@"                           // NO INFO ?
         CD_NEWLINE "\n */\n\n",

                    machOFile.filename.lastPathComponent, machOFile.filename,

      CD_MAYBE_FMT (machOFile.UUID, "UUID: %@", machOFile.UUID.UUIDString),

  CDNameForCPUType (machOFile.cputype, machOFile.cpusubtype),

      CD_MAYBE_FMT (identifier, "Current version: %@"CD_NEWLINE"Compat. version: %@",
                    identifier.formattedCurrentVersion, identifier.formattedCompatibilityVersion),

      CD_MAYBE_FMT (machOFile.sourceVersion, "Source version: %@",
                    machOFile.sourceVersion.sourceVersionString),

      CD_MAYBE_FMT (machOFile.minVersionMacOSX, "Min. OS X version: %@"CD_NEWLINE"OS X SDK: %@",
                    machOFile.minVersionMacOSX.minimumVersionString, machOFile.minVersionMacOSX.SDKVersionString),

      CD_MAYBE_FMT (machOFile.minVersionIOS, "Min. iOS version: %@"CD_NEWLINE"iOS SDK: %@",
                    machOFile.minVersionIOS.minimumVersionString, machOFile.minVersionIOS.SDKVersionString),

      CD_MAYBE_FMT (processor.garbageCollectionStatus, "Objective-C GC: %@",
                    processor.garbageCollectionStatus),

      CD_MAYBE_FMT (machOFile.dyldEnvironment.count, "DYLD environment: \n *\t\t%@",
                  [[machOFile.dyldEnvironment valueForKey:@"name"] componentsSeparatedByString:@"\n *\t\t"]),

      CD_MAYBE_FMT (machOFile.runPathCommands.count, CD_NEWLINE "%@", ^{

      id rpaths = [NSMutableString stringWithFormat:@"Run paths: "];
      for (CDLCRunPath *runPath in machOFile.runPathCommands)
      [rpaths appendFormat:@"" CD_NEWLINE "  %@ -> %@", runPath.path, runPath.resolvedRunPath];

      return rpaths; }()
    ),

    CD_MAYBE_FMT (machOFile.isEncrypted || machOFile.hasProtectedSegments, CD_NEWLINE "%@", ^{

      id security = @"".mutableCopy;

      if (machOFile.isEncrypted) {
        [security appendFormat:@""CD_NEWLINE"This file is encrypted:"];
        for (CDLoadCommand *loadCommand in machOFile.loadCommands) { CDLCEncryptionInfo *encryptionInfo;
          if (!(encryptionInfo = [loadCommand isKindOfClass:CDLCEncryptionInfo.class] ? (id)loadCommand : nil)) continue;
            [security appendFormat:@""CD_NEWLINE"\t\t\tcryptid: 0x%08x"CD_NEWLINE"cryptoff: 0x%08x"CD_NEWLINE"\t\t\tcryptsize: 0x%08x",
                                        encryptionInfo.cryptid,    encryptionInfo.cryptoff,          encryptionInfo.cryptsize];
        }
      } else {
          [security appendFormat:@""CD_NEWLINE"This file has protected segments%s",
            machOFile.canDecryptAllSegments  ? ", decrypting." : " that can't be decrypted:"];

          [machOFile.loadCommands enumerateObjectsUsingBlock:^(CDLoadCommand *loadCommand, NSUInteger index, BOOL *stop){
            if ([loadCommand isKindOfClass:CDLCSegment.class] && !((CDLCSegment*)loadCommand).canDecrypt)
              [security appendFormat:@""CD_NEWLINE"\t\tLoad command %lu, segment encryption: %@\n",
                   index, CDSegmentEncryptionTypeName(((CDLCSegment*)loadCommand).encryptionType)];
          }];
      }
      return security; }() // Returns "s" ENCRYPTION ?
    ),
    CD_MAYBE_FMT(!self.classDump.hasObjectiveCRuntimeInfo, "%s","This file does not contain any Objective-C runtime information.")
  ];
}

@end
