/*
 Copyright (c) 2013, OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "OEHIDDeviceParser.h"

#import "NSDictionary+OpenEmuSDK.h"
#import "OEControllerDescription.h"
#import "OEControlDescription.h"
#import "OEControlDescription.h"
#import "OEDeviceDescription.h"
#import "OEMultiHIDDeviceHandler.h"
#import "OEPS3HIDDeviceHandler.h"
#import "OEPS4HIDDeviceHandler.h"
#import "OEXBox360HIDDeviceHander.h"
#import "OEWiimoteHIDDeviceHandler.h"
#import "OESwitchProControllerHIDDeviceHandler.h"
#import "OEControllerDescription_Internal.h"

NS_ASSUME_NONNULL_BEGIN

#define ELEM(e) ((__bridge IOHIDElementRef)e)
#define ELEM_TO_VALUE(e) ([NSValue valueWithPointer:e])
#define VALUE_TO_ELEM(e) ((IOHIDElementRef)[e pointerValue])

@interface OEHIDEvent ()
+ (instancetype)OE_eventWithElement:(IOHIDElementRef)element value:(NSInteger)value;
@end

@interface _OEHIDDeviceAttributes : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDeviceHandlerClass:(Class)handlerClass;

@property(readonly) Class deviceHandlerClass;

- (void)applyAttributesToDevice:(IOHIDDeviceRef)device;
- (void)applyAttributesToElement:(IOHIDElementRef)element;
- (void)setAttributes:(NSDictionary<NSString *, id> *)attributes forElementCookie:(NSUInteger)cookie;

@property(nonatomic, copy) NSDictionary<NSNumber *, OEDeviceDescription *> *subdeviceIdentifiersToDeviceDescriptions;

@end

@interface _OEHIDDeviceElementTree : NSObject

- (instancetype)initWithHIDDevice:(IOHIDDeviceRef)device;

- (NSUInteger)numberOfChildrenOfElement:(IOHIDElementRef)element;
- (NSArray<NSValue *> *)childrenOfElement:(IOHIDElementRef)element;
- (void)enumerateChildrenOfElement:(nullable IOHIDElementRef)element usingBlock:(void(^)(IOHIDElementRef element, BOOL *stop))block;

@end

@implementation OEHIDDeviceParser

- (Class)OE_deviceHandlerClassForIOHIDDevice:(IOHIDDeviceRef)aDevice
{
    if([OEWiimoteHIDDeviceHandler canHandleDevice:aDevice])
        return [OEWiimoteHIDDeviceHandler class];
    else if([OEPS3HIDDeviceHandler canHandleDevice:aDevice])
        return [OEPS3HIDDeviceHandler class];
    else if([OEPS4HIDDeviceHandler canHandleDevice:aDevice])
        return [OEPS4HIDDeviceHandler class];
    else if([OEXBox360HIDDeviceHander canHandleDevice:aDevice])
        return [OEXBox360HIDDeviceHander class];
    else if ([OESwitchProControllerHIDDeviceHandler canHandleDevice:aDevice])
        return [OESwitchProControllerHIDDeviceHandler class];

    return [OEHIDDeviceHandler class];
}

- (OEHIDDeviceHandler *)deviceHandlerForIOHIDDevice:(IOHIDDeviceRef)device;
{
    Class deviceHandlerClass = [self OE_deviceHandlerClassForIOHIDDevice:device];
    id<OEHIDDeviceParser> parser = [deviceHandlerClass deviceParser];

    if(parser != self)
        return [parser deviceHandlerForIOHIDDevice:device];

    return [self OE_parseIOHIDDevice:device];
}

- (void)OE_setUpElementsOfIOHIDDevice:(IOHIDDeviceRef)device withAttributes:(NSDictionary *)elementAttributes
{
    NSArray *allElements = (__bridge_transfer NSArray *)IOHIDDeviceCopyMatchingElements(device, NULL, 0);

    for(id e in allElements) {
        IOHIDElementRef elem = (__bridge IOHIDElementRef)e;

        NSDictionary *attributes = elementAttributes[@(IOHIDElementGetCookie(elem))];

        [attributes enumerateKeysAndObjectsUsingBlock:^(NSString *key, id attribute, BOOL *stop) {
            IOHIDElementSetProperty(elem, (__bridge CFStringRef)key, (__bridge CFTypeRef)attribute);
        }];
    }
}

- (OEHIDDeviceHandler *)OE_parseIOHIDDevice:(IOHIDDeviceRef)device
{
    NSUInteger vendorID = [(__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDVendorIDKey)) integerValue];
    NSUInteger productID = [(__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey)) integerValue];
    NSString *productName = (__bridge NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));

    OEControllerDescription *controllerDescription = [OEControllerDescription OE_controllerDescriptionForVendorID:vendorID productID:productID product:productName];
    OEDeviceDescription *deviceDesc = [controllerDescription deviceDescriptionForVendorID:vendorID productID:productID cookie:0];
    _OEHIDDeviceAttributes *attributes = [self OE_deviceAttributesForIOHIDDevice:device controllerDescription:controllerDescription vendorID:vendorID productID:productID];

    OEHIDDeviceHandler *handler = nil;
    if([[attributes subdeviceIdentifiersToDeviceDescriptions] count] != 0)
        handler = [[[attributes deviceHandlerClass] alloc] initWithIOHIDDevice:device deviceDescription:deviceDesc subdeviceDescriptions:[attributes subdeviceIdentifiersToDeviceDescriptions]];
    else
        handler = [[[attributes deviceHandlerClass] alloc] initWithIOHIDDevice:device deviceDescription:deviceDesc];

    return handler;
}

- (_OEHIDDeviceAttributes *)OE_deviceAttributesForIOHIDDevice:(IOHIDDeviceRef)device controllerDescription:(OEControllerDescription *)controllerDescription vendorID:(NSUInteger)vendorID productID:(NSUInteger)productID
{
    NSDictionary<NSString *, NSDictionary<NSString *, id> *> *representation = [OEControllerDescription OE_representationForControllerDescription:controllerDescription];

    _OEHIDDeviceAttributes *attributes = nil;
    if(representation != nil)
        attributes = [self OE_deviceAttributesForKnownIOHIDDevice:device controllerDescription:controllerDescription representations:representation];
    else
        attributes = [self OE_deviceAttributesForUnknownIOHIDDevice:device controllerDescription:controllerDescription vendorID:vendorID productID:productID];

    return attributes;
}

- (nullable IOHIDElementRef)OE_findElementInArray:(NSMutableArray *)targetArray withCookie:(NSUInteger)cookie usage:(NSUInteger)usage
{
    __block IOHIDElementRef elem = NULL;

    [targetArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        IOHIDElementRef testedElement = (__bridge IOHIDElementRef)obj;

        if(IOHIDElementGetType(testedElement) == kIOHIDElementTypeCollection
           || (cookie != OEUndefinedCookie && cookie != IOHIDElementGetCookie(testedElement))
           || usage != IOHIDElementGetUsage(testedElement))
            return;

        elem = testedElement;
        // Make sure you stop enumerating right after modifying the array
        // or else it will throw an exception.
        [targetArray removeObjectAtIndex:idx];
        *stop = YES;
    }];

    return elem;
}

typedef NS_ENUM(NSInteger, OEElementType) {
    OEElementTypeButton,
    OEElementTypeGenericDesktop,
    OEElementTypeConsumer,
    OEElementTypeSimulation,
};

- (OEElementType)OE_elementTypeForHIDEventType:(OEHIDEventType)eventType usage:(NSUInteger)usage
{
    if (eventType == OEHIDEventTypeTrigger) {
        switch(usage) {
            case kHIDUsage_Sim_Brake :
            case kHIDUsage_Sim_Accelerator :
                return OEElementTypeSimulation;
            default :
                break;
        }
    }

    if (eventType != OEHIDEventTypeButton)
        return OEElementTypeGenericDesktop;

    switch(usage) {
        case kHIDUsage_GD_DPadUp :
        case kHIDUsage_GD_DPadDown :
        case kHIDUsage_GD_DPadLeft :
        case kHIDUsage_GD_DPadRight :
        case kHIDUsage_GD_Start :
        case kHIDUsage_GD_Select :
        case kHIDUsage_GD_SystemMainMenu :
            return OEElementTypeGenericDesktop;

        case kHIDUsage_Csmr_ACHome :
        case kHIDUsage_Csmr_ACBack :
        case kHIDUsage_Csmr_ACForward :
        case kHIDUsage_Csmr_ACExit :
        case kHIDUsage_Csmr_ACProperties :
        case kHIDUsage_Csmr_Record :
            return OEElementTypeConsumer;

        case kHIDUsage_Sim_Brake :
        case kHIDUsage_Sim_Accelerator :
            return OEElementTypeSimulation;
    }

    return OEElementTypeButton;
}

- (_OEHIDDeviceAttributes *)OE_deviceAttributesForKnownIOHIDDevice:(IOHIDDeviceRef)device controllerDescription:(OEControllerDescription *)controllerDesc representations:(NSDictionary<NSString *, NSDictionary<NSString *, id> *> *)controlRepresentations
{
    _OEHIDDeviceAttributes *attributes = [[_OEHIDDeviceAttributes alloc] initWithDeviceHandlerClass:[self OE_deviceHandlerClassForIOHIDDevice:device]];

    NSMutableArray *genericDesktopElements = [(__bridge_transfer NSArray *)IOHIDDeviceCopyMatchingElements(device, (__bridge CFDictionaryRef)@{ @kIOHIDElementUsagePageKey : @(kHIDPage_GenericDesktop) }, 0) mutableCopy];
    NSMutableArray *buttonElements = [(__bridge_transfer NSArray *)IOHIDDeviceCopyMatchingElements(device, (__bridge CFDictionaryRef)@{ @kIOHIDElementUsagePageKey : @(kHIDPage_Button) }, 0) mutableCopy];
    NSMutableArray *consumerElements = [(__bridge_transfer NSArray *)IOHIDDeviceCopyMatchingElements(device, (__bridge CFDictionaryRef)@{ @kIOHIDElementUsagePageKey : @(kHIDPage_Consumer) }, 0) mutableCopy];
    NSMutableArray *simulationElements = [(__bridge_transfer NSArray *)IOHIDDeviceCopyMatchingElements(device, (__bridge CFDictionaryRef)@{ @kIOHIDElementUsagePageKey : @(kHIDPage_Simulation) }, 0) mutableCopy];

    [controlRepresentations enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, NSDictionary<NSString *, id> *rep, BOOL *stop) {
        OEHIDEventType type = OEHIDEventTypeFromNSString(rep[@"Type"]);
        NSUInteger cookie = [rep[@"Cookie"] integerValue];
        NSUInteger usage = OEUsageFromUsageStringWithType(rep[@"Usage"], type);

        // Find the element for the current description.
        NSMutableArray *targetArray;
        switch ([self OE_elementTypeForHIDEventType:type usage:usage]) {
            case OEElementTypeButton:
                targetArray = buttonElements;
                break;
            case OEElementTypeGenericDesktop:
                targetArray = genericDesktopElements;
                break;
            case OEElementTypeConsumer:
                targetArray = consumerElements;
                break;
            case OEElementTypeSimulation:
                targetArray = simulationElements;
                break;
        }

        IOHIDElementRef elem = [self OE_findElementInArray:targetArray withCookie:cookie usage:usage];

        if(elem == NULL) {
            NSLog(@"Could not find element for control of type: %@, cookie: %@, usage: %@", rep[@"Type"], rep[@"Cookie"], rep[@"Usage"]);
            return;
        }

        cookie = IOHIDElementGetCookie(elem);

        // Create attributes for the element if necessary. We need to apply the attributes
        // on the elements because OEHIDEvent depend on them to setup the event.
        switch(type) {
            case OEHIDEventTypeTrigger :
                [attributes setAttributes:@{ @kOEHIDElementIsTriggerKey : @YES } forElementCookie:cookie];
                [attributes applyAttributesToElement:elem];
                break;
            case OEHIDEventTypeHatSwitch :
                [attributes setAttributes:@{ @kOEHIDElementHatSwitchTypeKey : @([self OE_hatSwitchTypeForElement:elem]) } forElementCookie:cookie];
                [attributes applyAttributesToElement:elem];
                break;
            default :
                break;
        }

        // Attempt to create an event for it, dump it if it's not possible.
        OEHIDEvent *genericEvent = [OEHIDEvent OE_eventWithElement:elem value:0];
        if(genericEvent == nil) return;

        // Add the control description.
        [controllerDesc addControlWithIdentifier:identifier name:rep[@"Name"] event:genericEvent valueRepresentations:rep[@"Values"]];
    }];

    [genericDesktopElements removeObjectsAtIndexes:[genericDesktopElements indexesOfObjectsPassingTest:^ BOOL (id elem, NSUInteger idx, BOOL *stop) {
        return [OEHIDEvent OE_eventWithElement:(__bridge IOHIDElementRef)elem value:0] == nil;
    }]];

    if([genericDesktopElements count] == 1)
        NSLog(@"WARNING: There is %ld generic desktop element unaccounted for in %@. Element details: %@", genericDesktopElements.count, controllerDesc.name, genericDesktopElements.description);
    
    if([genericDesktopElements count] > 1)
        NSLog(@"WARNING: There are %ld generic desktop elements unaccounted for in %@. Elements in detail: %@", genericDesktopElements.count, controllerDesc.name, genericDesktopElements.description);

    if([buttonElements count] == 1)
        NSLog(@"WARNING: There is %ld button element unaccounted for in %@. Element details: %@", buttonElements.count, controllerDesc.name, buttonElements.description);
    
    if([buttonElements count] > 1)
        NSLog(@"WARNING: There are %ld button elements unaccounted for in %@. Elements in detail: %@", buttonElements.count, controllerDesc.name, buttonElements.description);

    return attributes;
}

- (_OEHIDDeviceAttributes *)OE_deviceAttributesForUnknownIOHIDDevice:(IOHIDDeviceRef)device controllerDescription:(OEControllerDescription *)controllerDesc vendorID:(NSUInteger)vendorID productID:(NSUInteger)productID
{
    _OEHIDDeviceElementTree *tree = [[_OEHIDDeviceElementTree alloc] initWithHIDDevice:device];

    NSMutableArray<NSValue *> *rootJoysticks = [NSMutableArray array];
    [tree enumerateChildrenOfElement:nil usingBlock:^(IOHIDElementRef element, BOOL *stop)  {
        if(IOHIDElementGetUsagePage(element) != kHIDPage_GenericDesktop) return;

        NSUInteger usage = IOHIDElementGetUsage(element);
        if(usage == kHIDUsage_GD_Joystick || usage == kHIDUsage_GD_GamePad)
            [rootJoysticks addObject:ELEM_TO_VALUE(element)];
    }];

    if([rootJoysticks count] == 0)
        return nil;

    if([rootJoysticks count] == 1) {
        _OEHIDDeviceAttributes *attributes = [[_OEHIDDeviceAttributes alloc] initWithDeviceHandlerClass:[OEHIDDeviceHandler class]];

        [self OE_parseJoystickElement:VALUE_TO_ELEM(rootJoysticks[0]) intoControllerDescription:controllerDesc attributes:attributes deviceIdentifier:nil usingElementTree:tree];

        return attributes;
    }

    _OEHIDDeviceAttributes *attributes = [[_OEHIDDeviceAttributes alloc] initWithDeviceHandlerClass:[OEMultiHIDDeviceHandler class]];

    const NSUInteger subdeviceVendorID = vendorID << 32;
    const NSUInteger subdeviceProductIDBase = productID << 32;
    NSUInteger lastDeviceIndex = 0;

    NSMutableDictionary<NSNumber *, OEDeviceDescription *> *deviceIdentifiers = [[NSMutableDictionary alloc] initWithCapacity:[rootJoysticks count]];

    for(id e in rootJoysticks) {
        NSNumber *deviceIdentifier = @(++lastDeviceIndex);
        IOHIDElementRef elem = VALUE_TO_ELEM(e);

        [self OE_parseJoystickElement:elem intoControllerDescription:controllerDesc attributes:attributes deviceIdentifier:deviceIdentifier usingElementTree:tree];

        deviceIdentifiers[deviceIdentifier] = [controllerDesc OE_addDeviceDescriptionWithVendorID:subdeviceVendorID productID:subdeviceProductIDBase | lastDeviceIndex product:[[controllerDesc name] stringByAppendingFormat:@" %@", deviceIdentifier] cookie:IOHIDElementGetCookie(elem)];
    }

    attributes.subdeviceIdentifiersToDeviceDescriptions = deviceIdentifiers;

    return attributes;
}

typedef enum {
    OEParsedTypeNone,
    OEParsedTypeButton,
    OEParsedTypeHatSwitch,
    OEParsedTypeGroupedAxis,
    OEParsedTypePositiveAxis,
    OEParsedTypeSymmetricAxis,
    OEParsedTypeTrigger,
} OEParsedType;

- (void)OE_enumerateChildrenOfElement:(IOHIDElementRef)rootElement inElementTree:(_OEHIDDeviceElementTree *)elementTree usingBlock:(void(^)(IOHIDElementRef element, OEParsedType parsedType))block;
{
    BOOL isJoystickCollection = [self OE_isCollectionElement:rootElement joystickCollectionInElementTree:elementTree];

    [elementTree enumerateChildrenOfElement:rootElement usingBlock:^(IOHIDElementRef element, BOOL *stop) {
        if(IOHIDElementGetType(element) == kIOHIDElementTypeCollection) {
            [self OE_enumerateChildrenOfElement:element inElementTree:elementTree usingBlock:block];
            return;
        }

        switch(OEHIDEventTypeFromIOHIDElement(element)) {
            case OEHIDEventTypeAxis :
                if(isJoystickCollection)
                    block(element, OEParsedTypeGroupedAxis);
                else if(IOHIDElementGetLogicalMin(element) >= 0)
                    block(element, OEParsedTypePositiveAxis);
                else if(IOHIDElementGetLogicalMax(element) > 0)
                    block(element, OEParsedTypeSymmetricAxis);
                break;
            case OEHIDEventTypeButton :
                if (OEIOHIDElementIsTrigger(element)) {
                    block(element, OEParsedTypeTrigger);
                    break;
                }

                block(element, OEParsedTypeButton);
                break;
            case OEHIDEventTypeHatSwitch :
                block(element, OEParsedTypeHatSwitch);
                break;
            default :
                break;
        }
    }];
}

- (BOOL)OE_isCollectionElement:(IOHIDElementRef)rootElement joystickCollectionInElementTree:(_OEHIDDeviceElementTree *)elementTree
{
    __block NSUInteger axisElementsCount = 0;
    [elementTree enumerateChildrenOfElement:rootElement usingBlock:^(IOHIDElementRef element, BOOL *stop) {
        // Ignore subcollections.
        if(IOHIDElementGetType(element) == kIOHIDElementTypeCollection)
            return;

        switch(OEHIDEventTypeFromIOHIDElement(element)) {
            case OEHIDEventTypeAxis :
                axisElementsCount++;
                break;
            case OEHIDEventTypeButton :
            case OEHIDEventTypeHatSwitch :
                // If we find a non-axis element, we can just stop the search,
                // we will need to sort out the axis types later.
                axisElementsCount = 0;
                *stop = YES;
                break;
            default:
                break;
        }
    }];

    // Joysticks go by pairs, 2 by 2 like on the 360 or 4 for all joysticks on PS3.
    // If we don't have an even number just forget it.
    return axisElementsCount != 0 && axisElementsCount % 2 == 0;
}

- (void)OE_parseJoystickElement:(IOHIDElementRef)rootElement intoControllerDescription:(OEControllerDescription *)desc attributes:(_OEHIDDeviceAttributes *)attributes deviceIdentifier:(nullable id)deviceIdentifier usingElementTree:(_OEHIDDeviceElementTree *)elementTree
{
    NSMutableArray *buttonElements      = [NSMutableArray array];
    NSMutableArray *hatSwitchElements   = [NSMutableArray array];
    NSMutableArray *groupedAxisElements = [NSMutableArray array];

    NSMutableArray *posNegAxisElements  = [NSMutableArray array];
    NSMutableArray *posAxisElements     = [NSMutableArray array];

    NSMutableArray *triggerElements     = [NSMutableArray array];

    [self OE_enumerateChildrenOfElement:rootElement inElementTree:elementTree usingBlock:^(IOHIDElementRef element, OEParsedType parsedType) {
        id elem = (__bridge id)element;
        switch(parsedType) {
            case OEParsedTypeNone :
                NSAssert(NO, @"All elements should have a type!");
                break;
            case OEParsedTypeButton :
                [buttonElements addObject:elem];
                break;
            case OEParsedTypeHatSwitch :
                [hatSwitchElements addObject:elem];
                break;
            case OEParsedTypeGroupedAxis :
                [groupedAxisElements addObject:elem];
                break;
            case OEParsedTypePositiveAxis :
                [posAxisElements addObject:elem];
                break;
            case OEParsedTypeSymmetricAxis :
                [posNegAxisElements addObject:elem];
                break;
            case OEParsedTypeTrigger :
                [triggerElements addObject:elem];
                break;
        }
    }];
    
    NSDictionary *baseAttrib;
    if (deviceIdentifier)
        baseAttrib = @{@kOEHIDElementDeviceIdentifierKey : deviceIdentifier};
    else
        baseAttrib = @{};

    // Setup HatSwitch element attributes and create a control in the controller description.
    for(id e in hatSwitchElements) {
        IOHIDElementRef elem = ELEM(e);

        NSDictionary *attr = [baseAttrib OE_dictionaryByAddingEntriesFromDictionary:@{
            @kOEHIDElementHatSwitchTypeKey : @([self OE_hatSwitchTypeForElement:elem])}];

        [attributes setAttributes:attr forElementCookie:IOHIDElementGetCookie(elem)];
        [attributes applyAttributesToElement:elem];

        OEHIDEvent *genericEvent = [OEHIDEvent OE_eventWithElement:elem value:0];
        if(genericEvent != nil)
            [desc addControlWithIdentifier:nil name:nil event:genericEvent];
    }

    // Setup events that only have the device identifier as attribute.
    void(^setUpControlsInArray)(NSArray *) = ^(NSArray *elements) {
        for(id e in elements) {
            IOHIDElementRef elem = ELEM(e);
            OEHIDEvent *genericEvent = [OEHIDEvent OE_eventWithElement:elem value:0];
            if(genericEvent == nil)
                continue;
            
            if(deviceIdentifier != nil) {
                [attributes setAttributes:baseAttrib forElementCookie:IOHIDElementGetCookie(elem)];
                [attributes applyAttributesToElement:elem];
            }

            [desc addControlWithIdentifier:nil name:nil event:genericEvent];
        }
    };

    void(^setUpTriggerControlsInArray)(NSArray *) = ^(NSArray *elements) {
        for(id e in elements) {
            IOHIDElementRef elem = ELEM(e);

            NSDictionary *attr = [baseAttrib OE_dictionaryByAddingEntriesFromDictionary:@{
                @kOEHIDElementIsTriggerKey : @YES}];

            [attributes setAttributes:attr forElementCookie:IOHIDElementGetCookie(elem)];
            [attributes applyAttributesToElement:elem];

            OEHIDEvent *genericEvent = [OEHIDEvent OE_eventWithElement:elem value:0];
            if(genericEvent != nil) [desc addControlWithIdentifier:nil name:nil event:genericEvent];
        }
    };

    if(([posNegAxisElements count] + [groupedAxisElements count]) != 0 && [posAxisElements count] != 0) {
        // When there is at least one grouped or symmetric axis, we assume
        // that all positive-only axes are in fact triggers.
        setUpTriggerControlsInArray(posAxisElements);
    } else if ([posAxisElements count] == 6) {
        // Assume that if we have 6 axes the first 4 are analog controls and the last 2 are triggers.
        setUpControlsInArray([posAxisElements subarrayWithRange:NSMakeRange(0, 4)]);
        setUpTriggerControlsInArray([posAxisElements subarrayWithRange:NSMakeRange(4, 2)]);
    } else {
        setUpControlsInArray(posAxisElements);
    }

    setUpTriggerControlsInArray(triggerElements);
    setUpControlsInArray(buttonElements);
    setUpControlsInArray(groupedAxisElements);
    setUpControlsInArray(posNegAxisElements);
}

- (OEHIDEventHatSwitchType)OE_hatSwitchTypeForElement:(IOHIDElementRef)element
{
    NSInteger count = IOHIDElementGetLogicalMax(element) - IOHIDElementGetLogicalMin(element) + 1;
    OEHIDEventHatSwitchType type = OEHIDEventHatSwitchTypeUnknown;
    switch(count) {
        case 4 :
            type = OEHIDEventHatSwitchType4Ways;
            break;
        case 8 :
            type = OEHIDEventHatSwitchType8Ways;
            break;
    }

    return type;
}

@end

@implementation _OEHIDDeviceAttributes {
    NSMutableDictionary<NSNumber *, NSDictionary<NSString *, id> *> *_elementAttributes;
}

- (instancetype)init
{
    return nil;
}

- (instancetype)initWithDeviceHandlerClass:(Class)handlerClass;
{
    if((self = [super init]))
    {
        _deviceHandlerClass = handlerClass;
        _elementAttributes = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)applyAttributesToDevice:(IOHIDDeviceRef)device
{
    [_elementAttributes enumerateKeysAndObjectsUsingBlock:^(NSNumber *cookie, NSDictionary<NSString *, id> *attributes, BOOL *stop) {
        NSArray *elements = (__bridge_transfer NSArray *)IOHIDDeviceCopyMatchingElements(device, (__bridge CFDictionaryRef)@{ @kIOHIDElementCookieKey : cookie }, 0);
        NSAssert(elements.count == 1, @"There should be only one element attached to a given cookie.");
        [self _applyAttributes:attributes toElement:(__bridge IOHIDElementRef)elements[0]];
    }];
}
- (void)applyAttributesToElement:(IOHIDElementRef)element;
{
    [self _applyAttributes:_elementAttributes[@(IOHIDElementGetCookie(element))] toElement:element];
}

- (void)_applyAttributes:(NSDictionary *)attributes toElement:(IOHIDElementRef)element;
{
    [attributes enumerateKeysAndObjectsUsingBlock:^(NSString *key, id attribute, BOOL *stop) {
        IOHIDElementSetProperty(element, (__bridge CFStringRef)key, (__bridge CFTypeRef)attribute);
    }];
}

- (void)setAttributes:(NSDictionary<NSString *, id> *)attributes forElementCookie:(NSUInteger)cookie;
{
    _elementAttributes[@(cookie)] = [attributes copy];
}

@end

@implementation _OEHIDDeviceElementTree {
    IOHIDDeviceRef _device;
    CFArrayRef _elements;
    NSDictionary<NSValue *, NSValue *> *_elementTree;
}

- (void)dealloc
{
    CFRelease(_device);
    if (_elements != NULL) CFRelease(_elements);
}

- (instancetype)init
{
    return nil;
}

- (instancetype)initWithHIDDevice:(IOHIDDeviceRef)device;
{
    if(!(self = [super init]))
        return nil;

    _device = (IOHIDDeviceRef)CFRetain(device);
    _elements = IOHIDDeviceCopyMatchingElements(_device, NULL, 0);

    // IOHIDDeviceCopyMatchingElements can return NULL under memory pressure or
    // when the device is torn down by IOKit mid-call (e.g. a controller plugged
    // in on a low-memory system). Without a non-nil element list there's no
    // device to parse, and proceeding would leave _elements NULL — which would
    // then crash in dealloc on CFRelease(NULL). Bail out so the caller can skip.
    if (_elements == NULL) {
        NSLog(@"OEHIDDeviceParser: IOHIDDeviceCopyMatchingElements returned NULL for device %p; skipping parse.", device);
        return nil;
    }

    NSMutableDictionary<NSValue *, NSValue *> *elementTree = [NSMutableDictionary dictionary];
    for(id e in (__bridge NSArray *)_elements) {
        IOHIDElementRef elem = ELEM(e);
        IOHIDElementRef parent = IOHIDElementGetParent(elem);

        elementTree[ELEM_TO_VALUE(elem)] = ELEM_TO_VALUE(parent);
    }

    _elementTree = [elementTree copy];

    return self;
}

- (NSArray<NSValue *> *)childrenOfElement:(IOHIDElementRef)element
{
    NSArray<NSValue *> *children = [_elementTree allKeysForObject:ELEM_TO_VALUE(element)];

    return [children sortedArrayUsingComparator:^NSComparisonResult (NSValue *obj1, NSValue *obj2) {
        return [@(IOHIDElementGetCookie(VALUE_TO_ELEM(obj1))) compare:@(IOHIDElementGetCookie(VALUE_TO_ELEM(obj2)))];
    }];
}

- (NSUInteger)numberOfChildrenOfElement:(IOHIDElementRef)element;
{
    return [[_elementTree allKeysForObject:ELEM_TO_VALUE(element)] count];
}

- (void)enumerateChildrenOfElement:(nullable IOHIDElementRef)element usingBlock:(void(^)(IOHIDElementRef element, BOOL *stop))block;
{
    [[self childrenOfElement:element] enumerateObjectsUsingBlock:^(NSValue *obj, NSUInteger idx, BOOL *stop) {
        block(VALUE_TO_ELEM(obj), stop);
    }];
}

- (NSString *)description
{
    NSMutableString *string = [NSMutableString stringWithFormat:@"<%@ %p {\n", [self class], self];
    [_elementTree enumerateKeysAndObjectsUsingBlock:^(NSValue *key, NSValue *obj, BOOL *stop) {
        [string appendFormat:@"\t%p --> %p\n", [obj pointerValue], [key pointerValue]];
    }];
    [string appendString:@"}>"];
    return string;
}

@end

NS_ASSUME_NONNULL_END
