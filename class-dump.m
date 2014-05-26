// -*- mode: ObjC -*-

//  This file is part of class-dump, a utility for examining the Objective-C segment of Mach-O files.
//  Copyright (C) 1997-1998, 2000-2001, 2004-2014 Steve Nygard.

#include <stdio.h>
#include <libc.h>
#include <unistd.h>
#include <getopt.h>
#include <stdlib.h>
#include <mach-o/arch.h>

#import "CDClassDump.h"
#import "CDFindMethodVisitor.h"
#import "CDClassDumpVisitor.h"
#import "CDMultiFileVisitor.h"
#import "CDFile.h"
#import "CDMachOFile.h"
#import "CDFatFile.h"
#import "CDFatArch.h"
#import "CDSearchPathState.h"

void print_usage(void)
{
  fprintf(stderr,
          "class-dump %s\n"
          "Usage: class-dump [options] <mach-o-file>\n"
          "\n"
          "  where options are:\n"
          "        -a             show instance variable offsets\n"
          "        -A             show implementation addresses\n"
          "        --arch <arch>  choose a specific architecture from a universal binary (ppc, ppc64, i386, x86_64, armv6, armv7, armv7s, arm64)\n"
          "        -C <regex>     only display classes matching regular expression\n"
          "        -f <str>       find string in method name\n"
          "        -H             generate header files in current directory, or directory specified with -o\n"
          "        -I             sort classes, categories, and protocols by inheritance (overrides -s)\n"
          "        -o <dir>       output directory used for -H\n"
          "        -r             recursively expand frameworks and fixed VM shared libraries\n"
          "        -s             sort classes and categories by name\n"
          "        -S             sort methods by name\n"
          "        -t             suppress header in output, for testing\n"
          "        --list-arches  list the arches in the file, then exit\n"
          "        --sdk-ios      specify iOS SDK version (will look for /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS<version>.sdk\n"
          "                       or /Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS<version>.sdk)\n"
          "        --sdk-mac      specify Mac OS X version (will look for /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX<version>.sdk\n"
          "                       or /Developer/SDKs/MacOSX<version>.sdk)\n"
          "        --sdk-root     specify the full SDK root path (or use --sdk-ios/--sdk-mac for a shortcut)\n"
          ,
          CLASS_DUMP_VERSION
          );
}

#define CD_OPT_ARCH        1
#define CD_OPT_LIST_ARCHES 2
#define CD_OPT_VERSION     3
#define CD_OPT_SDK_IOS     4
#define CD_OPT_SDK_MAC     5
#define CD_OPT_SDK_ROOT    6
#define CD_OPT_HIDE        7

int main(int argc, char *argv[]) {

  @autoreleasepool {

    int                  ch;
    CDArch       targetArch;
    NSString * searchString,
               * outputPath;

    BOOL                errorFlag = NO,
                 shouldListArches = NO,
               shouldPrintVersion = NO,
                 hasSpecifiedArch = NO,
    shouldGenerateSeparateHeaders = NO;

    NSMutableSet * hiddenSections = NSMutableSet.set;

    struct option longopts[] = {
      { "show-ivar-offsets",       no_argument,       NULL, 'a' },
      { "show-imp-addr",           no_argument,       NULL, 'A' },
      { "match",                   required_argument, NULL, 'C' },
      { "find",                    required_argument, NULL, 'f' },
      { "generate-multiple-files", no_argument,       NULL, 'H' },
      { "sort-by-inheritance",     no_argument,       NULL, 'I' },
      { "output-dir",              required_argument, NULL, 'o' },
      { "recursive",               no_argument,       NULL, 'r' },
      { "sort",                    no_argument,       NULL, 's' },
      { "sort-methods",            no_argument,       NULL, 'S' },
      { "arch",                    required_argument, NULL, CD_OPT_ARCH },
      { "list-arches",             no_argument,       NULL, CD_OPT_LIST_ARCHES },
      { "suppress-header",         no_argument,       NULL, 't' },
      { "version",                 no_argument,       NULL, CD_OPT_VERSION },
      { "sdk-ios",                 required_argument, NULL, CD_OPT_SDK_IOS },
      { "sdk-mac",                 required_argument, NULL, CD_OPT_SDK_MAC },
      { "sdk-root",                required_argument, NULL, CD_OPT_SDK_ROOT },
      { "hide",                    required_argument, NULL, CD_OPT_HIDE },
      { NULL,                      0,                 NULL, 0 },
    };

    if (argc == 1) print_usage(), exit(0);

    CDClassDump *classDump = CDClassDump.new;

    while ((ch = getopt_long(argc, argv, "aAC:f:HIo:rRsSt", longopts, NULL)) != -1) {

      switch (ch) {

        case CD_OPT_ARCH: {
          NSString *name = [NSString stringWithUTF8String:optarg];
          targetArch = CDArchFromName(name);
          if (targetArch.cputype != CPU_TYPE_ANY) hasSpecifiedArch = YES;
          else {
            fprintf(stderr, "Error: Unknown arch %s\n\n", optarg);
            errorFlag = YES;
          }
          break;
        }

        case CD_OPT_LIST_ARCHES:
          shouldListArches = YES;
          break;

        case CD_OPT_VERSION:
          shouldPrintVersion = YES;
          break;

        case CD_OPT_SDK_IOS: {
          //NSLog(@"root: %@", root);
          classDump.sdkRoot = [NSFileManager.defaultManager fileExistsAtPath: @"/Applications/Xcode.app"]
                            ? [NSString stringWithFormat:@"/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS%s.sdk", optarg]
                            : [NSFileManager.defaultManager fileExistsAtPath: @"/Developer"]
                            ? [NSString stringWithFormat:@"/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS%s.sdk", optarg]
                            : nil;
          break;
        }

        case CD_OPT_SDK_MAC: {
          NSString *root = [NSString stringWithUTF8String:optarg];
          //NSLog(@"root: %@", root);
          classDump.sdkRoot = [NSFileManager.defaultManager fileExistsAtPath: @"/Applications/Xcode.app"]
                            ? [NSString stringWithFormat:@"/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX%@.sdk", root]
                            : [NSFileManager.defaultManager fileExistsAtPath: @"/Developer"]
                            ? [NSString stringWithFormat:@"/Developer/SDKs/MacOSX%@.sdk", root]
                            : nil;
          break;
        }

        case CD_OPT_SDK_ROOT: {
          classDump.sdkRoot = [NSString stringWithUTF8String:optarg]; //NSLog(@"root: %@", root);
          break;
        }

        case CD_OPT_HIDE: {
          NSString *str = [NSString stringWithUTF8String:optarg];
          if ([str isEqualToString:@"all"]) {
            [hiddenSections addObject:@"structures"];
            [hiddenSections addObject:@"protocols"];
          } else {
            [hiddenSections addObject:str];
          }
          break;
        }

        case 'a':
          classDump.shouldShowIvarOffsets = YES;
          break;

        case 'A':
          classDump.shouldShowMethodAddresses = YES;
          break;

        case 'C': {
          NSError *error;
          NSRegularExpression *regularExpression = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithUTF8String:optarg]
                                                                                             options:(NSRegularExpressionOptions)0
                                                                                               error:&error];
          if (regularExpression != nil) {
            classDump.regularExpression = regularExpression;
          } else {
            fprintf(stderr, "class-dump: Error with regular expression: %s\n\n", [[error localizedFailureReason] UTF8String]);
            errorFlag = YES;
          }

          // Last one wins now.
          break;
        }

        case 'f': {
          searchString = [NSString stringWithUTF8String:optarg];
          break;
        }

        case 'H':
          shouldGenerateSeparateHeaders = YES;
          break;

        case 'I':
          classDump.shouldSortClassesByInheritance = YES;
          break;

        case 'o':
          outputPath = [NSString stringWithUTF8String:optarg];
          break;

        case 'r':
          classDump.shouldProcessRecursively = YES;
          break;

        case 's':
          classDump.shouldSortClasses = YES;
          break;

        case 'S':
          classDump.shouldSortMethods = YES;
          break;

        case 't':
          classDump.shouldShowHeader = NO;
          break;

        case '?':
        default:
          errorFlag = YES;
          break;
      }
    }

    if (errorFlag) print_usage(), exit(2);

    if (shouldPrintVersion) printf("class-dump %s compiled %s\n", CLASS_DUMP_VERSION, __DATE__ " " __TIME__), exit(0);

    if (optind < argc) { /*! @note optind is "The index of the next argument to be processed by the getopts builtin command." */

      NSString *            arg = [NSString stringWithFileSystemRepresentation:argv[optind]];
      NSString * executablePath = arg.executablePathForFilename;

      if (shouldListArches) {
        if (!executablePath) printf("none\n");
        else {
          CDSearchPathState *searchPathState = CDSearchPathState.new;
          searchPathState.executablePath = executablePath;
          id macho = [CDFile fileWithContentsOfFile:executablePath searchPathState:searchPathState];
          printf("%s\n", !macho ? "none"
                                : [[macho isKindOfClass:CDMachOFile.class]
                                ? [macho archName]
                                : [macho isKindOfClass:CDFatFile.class]
                                ? [[macho archNames] componentsJoinedByString:@" "] : @"" UTF8String]);
        }
      }
      else {
        if (!executablePath)
          fprintf(stderr, "class-dump: Input file (%s) doesn't contain an executable.\n",
            arg.fileSystemRepresentation), exit(1);

        classDump.searchPathState.executablePath = executablePath.stringByDeletingLastPathComponent;
        CDFile *file = [CDFile fileWithContentsOfFile:executablePath searchPathState:classDump.searchPathState];
        if (!file)

          fprintf(stderr, "class-dump: Input file (%s) %s\n", executablePath.UTF8String,
            [NSFileManager.defaultManager     fileExistsAtPath:executablePath]
          ? [NSFileManager.defaultManager isReadableFileAtPath:executablePath]
          ? "is neither a Mach-O file nor a fat archive." : "is not readable (check read permissions)."
                                                          : "does not exist."), exit(1);

        if (!hasSpecifiedArch && ![file bestMatchForLocalArch:&targetArch])
            fprintf(stderr, "Error: Couldn't get local architecture\n"), exit(1);
//      NSLog(@"No arch specified, best match for local arch is: (%08x, %08x)", targetArch.cputype, targetArch.cpusubtype);
//      else NSLog(@"chosen arch is: (%08x, %08x)", targetArch.cputype, targetArch.cpusubtype);

        classDump.targetArch                     = targetArch;
        classDump.searchPathState.executablePath = executablePath.stringByDeletingLastPathComponent;

        NSError *error;
        if (![classDump loadFile:file error:&error])
          fprintf(stderr, "Error: %s\n", error.localizedFailureReason.UTF8String), exit(1);

        [classDump processObjectiveCData];
        [classDump         registerTypes];

        id (^visitorOfClass)(Class) = ^id(Class k){
            CDVisitor *new = [k new]; new.classDump = classDump; return new;
        };

        id visitor;
        if (searchString) {
          [visitor = visitorOfClass(CDFindMethodVisitor.class) setSearchString:searchString];
        } else if (shouldGenerateSeparateHeaders) {
          classDump.typeController.delegate = (visitor = visitorOfClass(CDMultiFileVisitor.class));
          [visitor setOutputPath:outputPath];
        } else {
          visitor = visitorOfClass(CDClassDumpVisitor.class);
          [visitor setShouldShowStructureSection:![hiddenSections containsObject:@"structures"]];
          [visitor  setShouldShowProtocolSection:![hiddenSections containsObject: @"protocols"]];
        }
        [classDump recursivelyVisit:visitor];
      }
    }
    exit(0); // avoid costly autorelease pool drain, we’re exiting anyway
  }
}

