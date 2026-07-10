#import <Foundation/Foundation.h>

@interface NppMacLanguageDefinition : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, copy) NSString *lexerName;
@end

@interface NppMacLanguageCatalog : NSObject

@property(nonatomic, readonly) NSArray<NppMacLanguageDefinition *> *allLanguages;

- (instancetype)initWithXMLURL:(NSURL *)url error:(NSError **)error;
- (NppMacLanguageDefinition *)languageForFileURL:(NSURL *)url;
- (NppMacLanguageDefinition *)definitionWithName:(NSString *)name;

@end
