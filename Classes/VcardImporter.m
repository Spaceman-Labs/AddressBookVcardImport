//
//  VcardImporter.m
//  AddressBookVcardImport
//
//  Created by Alan Harper on 20/10/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "VcardImporter.h"
#import "BaseSixtyFour.h"

@implementation VcardImporter

- (id) init {
    if (self = [super init]) {
        addressBook = ABAddressBookCreateWithOptions(NULL, NULL);
		ABAddressBookRequestAccessWithCompletion(addressBook, ^(bool granted, CFErrorRef error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self parse];
			});
		});
    }
    
    return self;
}

- (void) dealloc {
    CFRelease(addressBook);
    [super dealloc];
}

- (void)parse {
    [self emptyAddressBook];
    
    NSString *filename = [[NSBundle mainBundle] pathForResource:@"vCards" ofType:@"vcf"];
    NSLog(@"openning file %@", filename);
    NSData *stringData = [NSData dataWithContentsOfFile:filename];
    NSString *vcardString = [[NSString alloc] initWithData:stringData encoding:NSUTF8StringEncoding];
    
    
    NSArray *lines = [vcardString componentsSeparatedByString:@"\n"];
    
    for(NSString* line in lines) {
		@autoreleasepool {
			[self parseLine:line];
		}

    }
    
    ABAddressBookSave(addressBook, NULL);

    [vcardString release];
	NSLog(@"done parsing");
}

- (void) parseLine:(NSString *)line {
    if (self.base64image && [line hasPrefix:@" "]) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.base64image = [self.base64image stringByAppendingString:trimmedLine];
    } else if (self.base64image) {
        // finished contatenating image string
        [self parseImage];
    } else if ([line hasPrefix:@"BEGIN"]) {
        personRecord = ABPersonCreate();
    } else if ([line hasPrefix:@"END"]) {
        ABAddressBookAddRecord(addressBook,personRecord, NULL);
    } else if ([line hasPrefix:@"N:"]) {
        [self parseName:line];
    } else if ([line hasPrefix:@"EMAIL;"]) {
        [self parseEmail:line];
    } else if ([line hasPrefix:@"PHOTO;BASE64"]) {
        self.base64image = [NSString string];
    } else if ([line hasPrefix:@"PHOTO;ENCODING=b"]) {
		NSArray *parts = [line componentsSeparatedByString:@":"];
		NSString *base64 = [parts lastObject];
		self.base64image = [base64 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	} else if ([line hasPrefix:@"TEL"]) {
		[self parsePhoneNumber:line];
	}
				
}

- (void) parseName:(NSString *)line {
    NSArray *upperComponents = [line componentsSeparatedByString:@":"];
    NSArray *components = [[upperComponents objectAtIndex:1] componentsSeparatedByString:@";"];
    ABRecordSetValue (personRecord, kABPersonLastNameProperty,[components objectAtIndex:0], NULL);
    ABRecordSetValue (personRecord, kABPersonFirstNameProperty,[components objectAtIndex:1], NULL);
    ABRecordSetValue (personRecord, kABPersonPrefixProperty,[components objectAtIndex:3], NULL);
}

- (void) parseEmail:(NSString *)line {
	NSString *fuckNewLines = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *mainComponents = [fuckNewLines componentsSeparatedByString:@":"];
    NSString *emailAddress = [mainComponents objectAtIndex:1];
    CFStringRef label;
    ABMutableMultiValueRef multiEmail;
    
    if ([line rangeOfString:@"WORK"].location != NSNotFound) {
        label = kABWorkLabel;
    } else if ([line rangeOfString:@"HOME"].location != NSNotFound) {
        label = kABHomeLabel;
    } else {
        label = kABOtherLabel;
    }

    ABMultiValueRef immutableMultiEmail = ABRecordCopyValue(personRecord, kABPersonEmailProperty);
    if (immutableMultiEmail) {
        multiEmail = ABMultiValueCreateMutableCopy(immutableMultiEmail);
    } else {
        multiEmail = ABMultiValueCreateMutable(kABMultiStringPropertyType);
    }
    ABMultiValueAddValueAndLabel(multiEmail, emailAddress, label, NULL);
    ABRecordSetValue(personRecord, kABPersonEmailProperty, multiEmail,nil);
    
    CFRelease(multiEmail);
    if (immutableMultiEmail) {
        CFRelease(immutableMultiEmail);
    }
}

- (void)parsePhoneNumber:(NSString *)line
{
	ABMutableMultiValueRef multiEmail = ABMultiValueCreateMutable(kABMultiStringPropertyType);
	
	NSString *fuckNewLines = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSArray *mainComponents = [fuckNewLines componentsSeparatedByString:@":"];
	NSString *phoneNumber = [mainComponents lastObject];
	NSString *labelsString = [mainComponents firstObject];
	labelsString = [labelsString stringByReplacingOccurrencesOfString:@"TEL;" withString:@""];
	labelsString = [labelsString stringByReplacingOccurrencesOfString:@"type=VOICE;" withString:@""];
	labelsString = [labelsString stringByReplacingOccurrencesOfString:@"type=pref;" withString:@""];
	NSArray *labels = [labelsString componentsSeparatedByString:@";"];
	
	CFStringRef abLabel;
	NSString *labelValue = [labels firstObject];
	labelValue = [labelValue stringByReplacingOccurrencesOfString:@"type=" withString:@""];
	
	if ([labelValue isEqualToString:@"CELL"]) {
		abLabel = kABPersonPhoneMobileLabel;
	} else if ([labelValue isEqualToString:@"WORK"]) {
		abLabel = kABWorkLabel;
	} else if ([labelValue isEqualToString:@"IPHONE"]) {
		abLabel = kABPersonPhoneIPhoneLabel;
	} else if ([labelValue isEqualToString:@"HOME"]) {
		abLabel = kABHomeLabel;
	} else {
        abLabel = kABOtherLabel;
    }
	
	ABMultiValueAddValueAndLabel(multiEmail, phoneNumber, abLabel, NULL);
	
	ABRecordSetValue(personRecord, kABPersonPhoneProperty, multiEmail, nil);
	CFRelease(multiEmail);
}

- (void) parseImage {
    NSData *imageData = [BaseSixtyFour decode:self.base64image];
    self.base64image = nil;
    ABPersonSetImageData(personRecord, (CFDataRef)imageData, NULL);
    
}
- (void) emptyAddressBook {
    CFArrayRef people = ABAddressBookCopyArrayOfAllPeople(addressBook);
    int arrayCount = CFArrayGetCount(people);
    ABRecordRef abrecord;
    
    for (int i = 0; i < arrayCount; i++) {
        abrecord = CFArrayGetValueAtIndex(people, i);
        ABAddressBookRemoveRecord(addressBook,abrecord, NULL);
    }
    CFRelease(people);
}
@end
