#import <OpenEmuBase/OEGameCore.h>
@interface OELibretroCoreTranslator : OEGameCore
/// Extracts the internal 'library_version' from a Libretro dylib without full initialization.
+ (nullable NSString *)libraryVersionForCoreAtURL:(nonnull NSURL *)url;
@end
