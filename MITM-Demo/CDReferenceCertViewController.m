//
//  CDReferenceCertViewController.m
//  MITM-Demo
//
//  Created by Daniel Schneller on 06.06.13.
//  Copyright (c) 2013 CenterDevice GmbH. All rights reserved.
//

#import "CDReferenceCertViewController.h"

@interface CDReferenceCertViewController ()

@property (nonatomic, readonly) NSArray* referenceCerts;

@end

@implementation CDReferenceCertViewController
@synthesize referenceCerts = _referenceCerts;

- (NSArray *)referenceCerts
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Load reference certificate from our main bundle
        NSMutableArray* certDatas = [NSMutableArray array];
        NSArray* certificateFiles = @[@"star.centerdevice.de", @"www.centerdevice.de"];
        for (NSUInteger i = 0; i<certificateFiles.count; i++)
        {
            NSString *certificateFileLocation = [[NSBundle mainBundle] pathForResource:certificateFiles[i] ofType:@"der"];
            NSData *certificateData = [[NSData alloc] initWithContentsOfFile:certificateFileLocation];
            [certDatas addObject:certificateData];
        }
        _referenceCerts = [NSArray arrayWithArray:certDatas];
    });
    return _referenceCerts;
}

#pragma mark - SSL related NSURLConnectionDelegate methods


-(void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (!self.progressController.working) { return; }
    [self.progressController appendLog:@"Authentication challenge received"];
    
    SecTrustRef receivedServerCertificate = challenge.protectionSpace.serverTrust;
    if ([self matchesKnownCertificates:receivedServerCertificate]) {
        // certificate matched a known reference cert. Create a credential and proceed.
        [self.progressController appendLog:@"Certificate validated. Proceeding."];
        
        NSURLCredential* cred = [NSURLCredential credentialForTrust:receivedServerCertificate];
        [challenge.sender useCredential:cred forAuthenticationChallenge:challenge];
    } else {
        // presented certificate did not match one on file. This means we have no conclusive
        // idea about the identity of the server and will therefore abort the connection here.
        [self.progressController appendLog:@"Validation Failed! Canceling connection!"];
        [challenge.sender cancelAuthenticationChallenge:challenge];
    }
    
}



- (BOOL)matchesKnownCertificates:(SecTrustRef)presentedTrustInformation {
    // prepare return value
    BOOL certificateVerified = NO; // defensive default
    
    
    // Perform default trust evaluation first, to make sure the format of the presented
    // data is correct and there are no other trust issues
    SecTrustResultType evaluationResult;
    OSStatus status = SecTrustEvaluate(presentedTrustInformation, &evaluationResult);
    
    // status now contains the general success/failure result of the evaluation call.
    // evaluationResult has the concrete outcome of the certificate check.
    // only if the call was successful do we need to look a the actual evaluation result
    if (status == errSecSuccess)
    {
        // only in these 2 cases the certificate could be definitely verified.
        // now we still need to double check the received certificates by comparing
        // them to the reference certificates. That way we make sure we are talking
        // to the correct server, and not merely have an encrypted channel.
        
        // otherwise someone could attempt a man-in-the-middle attack using
        // a certificate that was correctly signed by any of the many root-CAs
        // the system trusts by default.
        if (evaluationResult == kSecTrustResultUnspecified
            || evaluationResult == kSecTrustResultProceed)
        {
            NSUInteger referenceCertCount =  [self.referenceCerts count];
            for (NSUInteger i = 0; i<referenceCertCount && !certificateVerified; i++)
            {
                NSData* referenceCert = self.referenceCerts[i];
                
                [self.progressController appendLog:[NSString stringWithFormat:@"Check against ref. cert #%d", i]];
                
                CFIndex presentedCertsCount = SecTrustGetCertificateCount(presentedTrustInformation);
                for (CFIndex j = 0; j<presentedCertsCount && !certificateVerified; j++)
                {
                    SecCertificateRef currentCert = SecTrustGetCertificateAtIndex(presentedTrustInformation, i);
                    CFDataRef certData = SecCertificateCopyData(currentCert);
                    certificateVerified = [referenceCert isEqualToData:CFBridgingRelease(certData)];
                }
            }
        }
        [self.progressController appendLog:[NSString stringWithFormat:@"  Verified: %@",
                                            certificateVerified ? @"YES" : @"NO"]];
    } else {
        [self.progressController appendLog:@"Problem occurred executing SecTrustEvaluate. Rejecting connection."];
    }
    
    
    return certificateVerified;
}



@end
