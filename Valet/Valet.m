//
//  Valet.m
//  Valet
//
//  Created by Dan Federman on 1/21/15.
//  Copyright (c) 2015 Square, Inc. All rights reserved.
//

#import "Valet.h"

#import "ValetDefines.h"


NSString *VALStringForAccessibility(VALAccessibility accessibility)
{
    switch (accessibility) {
        case VALAccessibleWhenUnlocked:
            return @"AccessibleWhenUnlocked";
        case VALAccessibleAfterFirstUnlock:
            return @"AccessibleAfterFirstUnlock";
        case VALAccessibleAlways:
            return @"AccessibleAlways";
        case VALAccessibleWhenPasscodeSetThisDeviceOnly:
            return @"AccessibleWhenPasscodeSetThisDeviceOnly";
        case VALAccessibleWhenUnlockedThisDeviceOnly:
            return @"AccessibleWhenUnlockedThisDeviceOnly";
        case VALAccessibleAfterFirstUnlockThisDeviceOnly:
            return @"AccessibleAfterFirstUnlockThisDeviceOnly";
        case VALAccessibleAlwaysThisDeviceOnly:
            return @"AccessibleAlwaysThisDeviceOnly";
        default:
            // Default to a secure option if we get something insane.
            return @"Unknown";
    }
}


@interface VALValet ()

@property (copy, readonly) NSDictionary *baseQuery;

@end


@implementation VALValet

#pragma mark - Initialization

- (instancetype)initWithIdentifier:(NSString *)identifier accessibility:(VALAccessibility)accessibility;
{
    VALCheckCondition(identifier.length > 0, nil, @"Valet requires a identifier");
    VALCheckCondition(accessibility > 0, nil, @"Valet requires a valid accessibility setting");

    self = [self init];
    if (self != nil) {
        _baseQuery = [[self _mutableBaseQueryWithIdentifier:identifier initializer:_cmd accessibility:accessibility] copy];
        _identifier = [identifier copy];
        _sharedAcrossApplications = NO;
    }
    
    return self;
}

- (instancetype)initWithSharedAccessGroupIdentifier:(NSString *)sharedAccessGroupIdentifier accessibility:(VALAccessibility)accessibility;
{
    VALCheckCondition(sharedAccessGroupIdentifier.length > 0, nil, @"Valet requires a sharedAccessGroupIdentifier");
    VALCheckCondition(accessibility > 0, nil, @"Valet requires a valid accessibility setting");

    self = [self init];
    if (self != nil) {
        NSMutableDictionary *baseQuery = [self _mutableBaseQueryWithIdentifier:sharedAccessGroupIdentifier initializer:_cmd accessibility:accessibility];
        baseQuery[(__bridge id)kSecAttrAccessGroup] = [NSString stringWithFormat:@"%@.%@", [self _sharedAccessGroupPrefix], sharedAccessGroupIdentifier];
        
        _baseQuery = [baseQuery copy];
        _identifier = [sharedAccessGroupIdentifier copy];
        _sharedAcrossApplications = YES;
    }
    
    return self;
}

#pragma mark - Public Methods

- (BOOL)canAccessKeychain;
{
    NSString *canaryKey = @"VAL_KeychainCanaryUsername";
    NSString *canaryValue = @"VAL_KeychainCanaryPassword";
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (![[self objectForKey:canaryKey] isEqual:canaryValue]) {
            [self setString:canaryValue forKey:canaryKey];
        }
    });
    
    NSString *const retrievedCanaryValue = [self stringForKey:canaryKey];
    return [retrievedCanaryValue isEqualToString:canaryValue];
}

- (BOOL)setObject:(NSData *)value forKey:(NSString *)key;
{
    return [self _setObject:value forKey:key options:nil];
}

- (NSData *)objectForKey:(NSString *)key;
{
    return [self _objectForKey:key options:nil];
}

- (BOOL)setString:(NSString *)string forKey:(NSString *)key;
{
    return [self _setString:string forKey:key options:nil];
}

- (NSString *)stringForKey:(NSString *)key;
{
    return [self _stringForKey:key options:nil];
}

- (BOOL)containsObjectForKey:(NSString *)key;
{
    OSStatus status = [self _containsObjectForKey:key options:nil];
    BOOL keyAlreadyInKeychain = (status == errSecSuccess);
    return keyAlreadyInKeychain;
}

- (NSSet *)allKeys;
{
    return [self _allKeysWithOptions:nil];
}

- (BOOL)removeObjectForKey:(NSString *)key;
{
    return [self _removeObjectForKey:key options:nil];
}

- (BOOL)removeAllObjects;
{
    return [self _removeAllObjectsWithOptions:nil];
}

#pragma mark Private Methods

- (BOOL)_supportsSynchronizableKeychainItems;
{
#if TARGET_IPHONE_SIMULATOR
    return NO;
#else
    return (&kSecAttrSynchronizable != NULL && &kSecAttrSynchronizableAny != NULL);
#endif
}

- (BOOL)_supportsLocalAuthentication;
{
#if TARGET_IPHONE_SIMULATOR
    return NO;
#else
    return (&kSecAttrAccessControl != NULL && &kSecUseOperationPrompt != NULL);
#endif
}

- (NSMutableDictionary *)_mutableBaseQueryWithIdentifier:(NSString *)identifier initializer:(SEL)initializer accessibility:(VALAccessibility)accessibility;
{
    return [@{
              // Valet only handles passwords.
              (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
              // Use the identifier, Valet type and accessibility settings to create the keychain service name.
              (__bridge id)kSecAttrService : [NSString stringWithFormat:@"VAL_%@_%@_%@_%@", NSStringFromClass([self class]), NSStringFromSelector(initializer), identifier, VALStringForAccessibility(accessibility)],
              // Set our accessibility.
              (__bridge id)kSecAttrAccessible : [self _secAccessibilityAttributeForAccessibility:accessibility],
              } mutableCopy];
}

/// Programatically grab the required prefix for the shared access group (i.e. Bundle Seed ID). The value for the kSecAttrAccessGroup key in queries for data that is shared between apps must be of the format bundleSeedID.sharedAccessGroup. For more information on the Bundle Seed ID, see https://developer.apple.com/library/ios/qa/qa1713/_index.html
- (NSString *)_sharedAccessGroupPrefix;
{
    NSDictionary *query = @{ (__bridge NSString *)kSecClass : (__bridge NSString *)kSecClassGenericPassword,
                             (__bridge id)kSecAttrAccount : @"SharedAccessGroupPrefixPlaceholder",
                             (__bridge id)kSecReturnAttributes : @YES };
    
    CFTypeRef outTypeRef = NULL;
    NSDictionary *queryResult = nil;
    
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &outTypeRef);
    queryResult = (__bridge_transfer NSDictionary *)outTypeRef;
    
    if (status == errSecItemNotFound) {
        status = SecItemAdd((__bridge CFDictionaryRef)query, &outTypeRef);
        queryResult = (__bridge_transfer NSDictionary *)outTypeRef;
    }
    
    if (status == errSecSuccess) {
        NSString *accessGroup = queryResult[(__bridge id)kSecAttrAccessGroup];
        NSArray *components = [accessGroup componentsSeparatedByString:@"."];
        NSString *bundleSeedID = components.firstObject;
        
        return bundleSeedID;
    }
    
    return nil;
}

- (BOOL)_setObject:(NSData *)value forKey:(NSString *)key options:(NSDictionary *)options;
{
    VALCheckCondition(key.length > 0, NO, @"Can not set a value with an empty key.");
    VALCheckCondition(value != nil, NO, @"Can not set nil value");
    
    OSStatus status = errSecUnimplemented;
    NSMutableDictionary *query = [self.baseQuery mutableCopy];
    [query addEntriesFromDictionary:[self _secItemFormatDictionaryWithKey:key]];
    if (options.count > 0) {
        [query addEntriesFromDictionary:options];
    }
    
    if ([self containsObjectForKey:key]) {
        // The item already exists, so just update it.
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData : value });
        
    } else {
        // No previous item found, add the new one.
        NSMutableDictionary *keychainData = [query mutableCopy];
        [keychainData addEntriesFromDictionary:@{ (__bridge id)kSecValueData : value }];
        
        status = SecItemAdd((__bridge CFDictionaryRef)keychainData, NULL);
    }
    
    return (status == errSecSuccess);
}

- (NSData *)_objectForKey:(NSString *)key options:(NSDictionary *)options;
{
    VALCheckCondition(key.length > 0, nil, @"Can not retrieve value with empty key.");
    NSMutableDictionary *query = [self.baseQuery mutableCopy];
    [query addEntriesFromDictionary:[self _secItemFormatDictionaryWithKey:key]];
    [query addEntriesFromDictionary:@{ (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne,
                                       (__bridge id)kSecReturnData : @YES }];
    if (options.count > 0) {
        [query addEntriesFromDictionary:options];
    }
    
    CFTypeRef outTypeRef = NULL;
    
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &outTypeRef);
    NSData *value = (__bridge_transfer NSData *)outTypeRef;
    return (status == errSecSuccess) ? value : nil;
}

- (BOOL)_setString:(NSString *)string forKey:(NSString *)key options:(NSDictionary *)options;
{
    VALCheckCondition(string.length > 0, nil, @"Can not set empty string for key.");
    NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (stringData.length > 0) {
        return [self _setObject:stringData forKey:key options:options];
    }
    
    return NO;
}

- (NSString *)_stringForKey:(NSString *)key options:(NSDictionary *)options;
{
    NSData *stringData = [self _objectForKey:key options:options];
    if (stringData.length > 0) {
        return [[NSString alloc] initWithBytes:stringData.bytes length:stringData.length encoding:NSUTF8StringEncoding];
    }
    
    return nil;
}

- (OSStatus)_containsObjectForKey:(NSString *)key options:(NSDictionary *)options;
{
    VALCheckCondition(key.length > 0, NO, @"Can not check if empty key exists in the keychain.");
    
    NSMutableDictionary *query = [self.baseQuery mutableCopy];
    [query addEntriesFromDictionary:[self _secItemFormatDictionaryWithKey:key]];
    if (options.count > 0) {
        [query addEntriesFromDictionary:options];
    }
    
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    return status;
}

- (NSSet *)_allKeysWithOptions:(NSDictionary *)options;
{
    NSSet *keys = nil;
    NSMutableDictionary *query = [self.baseQuery mutableCopy];
    [query addEntriesFromDictionary:@{ (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitAll,
                                       (__bridge id)kSecReturnAttributes : @YES }];
    if (options.count > 0) {
        [query addEntriesFromDictionary:options];
    }
    
    CFTypeRef outTypeRef = NULL;
    NSDictionary *queryResult = nil;
    
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &outTypeRef);
    queryResult = (__bridge_transfer NSDictionary *)outTypeRef;
    if (status == errSecSuccess) {
        if ([queryResult isKindOfClass:[NSArray class]]) {
            NSMutableSet *allKeys = [NSMutableSet new];
            for (NSDictionary *attributes in queryResult) {
                // There were many matches.
                if (attributes[(__bridge id)kSecAttrAccount]) {
                    [allKeys addObject:attributes[(__bridge id)kSecAttrAccount]];
                }
            }
            
            keys = [allKeys copy];
        } else if (queryResult[(__bridge id)kSecAttrAccount]) {
            // There was only one match.
            keys = [NSSet setWithObject:queryResult[(__bridge id)kSecAttrAccount]];
        }
    }
    
    return keys;
}

- (BOOL)_removeObjectForKey:(NSString *)key options:(NSDictionary *)options;
{
    VALCheckCondition(key.length > 0, NO, @"Can not remove object for empty key from the keychain.");
    
    NSMutableDictionary *query = [self.baseQuery mutableCopy];
    [query addEntriesFromDictionary:[self _secItemFormatDictionaryWithKey:key]];
    if (options.count > 0) {
        [query addEntriesFromDictionary:options];
    }
    
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    // We succeeded as long as we can confirm that the item is not in the keychain.
    return (status != errSecInteractionNotAllowed);
}

- (BOOL)_removeAllObjectsWithOptions:(NSDictionary *)options;
{
    for (NSString *key in [self allKeys]) {
        if (![self _removeObjectForKey:key options:options]) {
            return NO;
        }
    }
    
    return YES;
}

- (id)_secAccessibilityAttributeForAccessibility:(VALAccessibility)accessibility;
{
    switch (accessibility) {
        case VALAccessibleWhenUnlocked:
            return (__bridge id)kSecAttrAccessibleWhenUnlocked;
        case VALAccessibleAfterFirstUnlock:
            return (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        case VALAccessibleAlways:
            return (__bridge id)kSecAttrAccessibleAlways;
        case VALAccessibleWhenPasscodeSetThisDeviceOnly:
            return (__bridge id)kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly;
        case VALAccessibleWhenUnlockedThisDeviceOnly:
            return (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
        case VALAccessibleAfterFirstUnlockThisDeviceOnly:
            return (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        case VALAccessibleAlwaysThisDeviceOnly:
            return (__bridge id)kSecAttrAccessibleAlwaysThisDeviceOnly;
        default:
            // Default to a secure option if we get something insane.
            VALCheckCondition(NO, (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly, @"Unexpected accessibility option %@", @(accessibility));
    }
}

- (NSDictionary *)_secItemFormatDictionaryWithKey:(NSString *)key;
{
    if (key.length > 0) {
        return @{ (__bridge id)kSecAttrAccount : key };
    }
    
    return @{};
}

@end


#pragma mark - SynchronizableValet


@implementation VALSynchronizableValet

#pragma mark - Initialization

- (instancetype)initWithIdentifier:(NSString *)identifier accessibility:(VALAccessibility)accessibility;
{
    VALCheckCondition(accessibility == VALAccessibleWhenUnlocked || accessibility == VALAccessibleAfterFirstUnlock || accessibility == VALAccessibleAlways, nil, @"Accessibility must not be scoped to this device");
    VALCheckCondition([self _supportsSynchronizableKeychainItems], nil, @"This device does not support synchronizing data to iCloud.");
    
    return [super initWithIdentifier:identifier accessibility:accessibility];
}

- (instancetype)initWithSharedAccessGroupIdentifier:(NSString *)sharedAccessGroupIdentifier accessibility:(VALAccessibility)accessibility;
{
    VALCheckCondition(accessibility == VALAccessibleWhenUnlocked || accessibility == VALAccessibleAfterFirstUnlock || accessibility == VALAccessibleAlways, nil, @"Accessibility must not be scoped to this device");
    VALCheckCondition([self _supportsSynchronizableKeychainItems], nil, @"This device does not support synchronizing data to iCloud.");
    
    return [super initWithSharedAccessGroupIdentifier:sharedAccessGroupIdentifier accessibility:accessibility];
}

#pragma mark - Private Methods

- (NSMutableDictionary *)_mutableBaseQueryWithIdentifier:(NSString *)identifier initializer:(SEL)initializer accessibility:(VALAccessibility)accessibility;
{
    NSMutableDictionary *mutableBaseQuery = [super _mutableBaseQueryWithIdentifier:identifier initializer:initializer accessibility:accessibility];
    mutableBaseQuery[(__bridge id)kSecAttrSynchronizable] = @YES;
    
    return mutableBaseQuery;
}

@end


#pragma mark - SecureElementValet

@implementation VALSecureElementValet

#pragma mark - Initialization

- (instancetype)initWithIdentifier:(NSString *)identifier accessibility:(VALAccessibility)accessibility;
{
    VALCheckCondition(accessibility == VALAccessibleWhenPasscodeSetThisDeviceOnly, nil, @"Accessibility on SecureElementValet must be VALAccessibleWhenPasscodeSetThisDeviceOnly");
    VALCheckCondition([self _supportsLocalAuthentication], nil, @"This device does not support storing data on the secure element.");
    
    return [super initWithIdentifier:identifier accessibility:accessibility];
}

- (instancetype)initWithSharedAccessGroupIdentifier:(NSString *)sharedAccessGroupIdentifier accessibility:(VALAccessibility)accessibility;
{
    VALCheckCondition(accessibility == VALAccessibleWhenPasscodeSetThisDeviceOnly, nil, @"Accessibility on SecureElementValet must be VALAccessibleWhenPasscodeSetThisDeviceOnly");
    VALCheckCondition([self _supportsLocalAuthentication], nil, @"This device does not support storing data on the secure element.");
    
    return [super initWithSharedAccessGroupIdentifier:sharedAccessGroupIdentifier accessibility:accessibility];
}

#pragma mark - Public Methods

- (BOOL)setObject:(NSData *)value forKey:(NSString *)key userPrompt:(NSString *)userPrompt
{
    return [self _setObject:value forKey:key options:@{ (__bridge id)kSecUseOperationPrompt : userPrompt }];
}

- (NSData *)objectForKey:(NSString *)key userPrompt:(NSString *)userPrompt;
{
    return [self _objectForKey:key options:@{ (__bridge id)kSecUseOperationPrompt : userPrompt }];
}

- (BOOL)setString:(NSString *)string forKey:(NSString *)key userPrompt:(NSString *)userPrompt;
{
    return [self _setString:string forKey:key options:@{ (__bridge id)kSecUseOperationPrompt : userPrompt }];
}

- (NSString *)stringForKey:(NSString *)key userPrompt:(NSString *)userPrompt;
{
    return [self _stringForKey:key options:@{ (__bridge id)kSecUseOperationPrompt : userPrompt }];
}

- (BOOL)containsObjectForKey:(NSString *)key;
{
    OSStatus status = [self _containsObjectForKey:key options:@{ (__bridge id)kSecUseNoAuthenticationUI : @YES }];
    BOOL keyAlreadyInKeychain = (status == errSecInteractionNotAllowed);
    return keyAlreadyInKeychain;
}

- (NSSet *)allKeys;
{
    return [self _allKeysWithOptions:@{ (__bridge id)kSecUseNoAuthenticationUI : @YES }];
}

#pragma mark - Private Methods

- (NSMutableDictionary *)_mutableBaseQueryWithIdentifier:(NSString *)identifier initializer:(SEL)initializer accessibility:(VALAccessibility)accessibility;
{
    NSMutableDictionary *mutableBaseQuery = [super _mutableBaseQueryWithIdentifier:identifier initializer:initializer accessibility:accessibility];
    mutableBaseQuery[(__bridge id)kSecAttrAccessControl] = (__bridge id)SecAccessControlCreateWithFlags(NULL, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, kSecAccessControlUserPresence, NULL);
    
    return mutableBaseQuery;
}

@end
